class TraitBank
  class Stats
    CheckResult = Struct.new(:valid, :reason) do
      def valid?
        valid
      end

      def self.invalid(reason)
        self.new(false, reason)
      end

      def self.valid
        self.new(true, nil)
      end
    end

    RECORD_THRESHOLD = 20_000
    MIN_RECORDS_FOR_HIST = 4
    OBJ_COUNT_LIMIT_PAD = 5

    class << self
      delegate :log, to: TraitBank::Logger

      def obj_counts(query, record_count, limit)
        raise_if_query_invalid_for_counts(query, record_count)

        key = "trait_bank/stats/obj_counts/v3/limit_#{limit}/#{query.to_cache_key}" # increment version number when changing query semantics

        Rails.cache.fetch(key) do
          params = {}
          q = if query.taxa?
                obj_counts_query_for_taxa(query, params)
              else
                obj_counts_query_for_records(query, params)
              end
          q.concat("\nLIMIT #{limit + OBJ_COUNT_LIMIT_PAD}")
          results = TraitBank.query(q, params)
          filter_identical_count_ancestors(TraitBank.results_to_hashes(results, "obj"), limit)
        end
      end


      # XXX: this isn't very performant, but the assumption is that that the filtering case is rare
      def filter_identical_count_ancestors(results, limit)
        grouped_results = results.group_by { |result| result[:count] }

        objs_to_filter = []
        grouped_results.each do |_, results_for_count|
          next if results_for_count.length == 1
          results_for_count.each do |result|
            results_for_count.each do |other_result|
              next if result == other_result
              obj = result[:obj][:uri]
              other_obj = other_result[:obj][:uri]
              objs_to_filter << obj if TraitBank::Terms.term_descendant_of_other?(other_obj, obj)
            end
          end
        end

        filtered = results.reject { |r| objs_to_filter.include?(r[:obj][:uri]) }
        filtered[0..limit]
      end

      # Returns:
      # bi: bucket index
      # bw: bucket width
      # c: count of records/pages in bucket
      # u: units term
      def histogram(query, record_count)
        raise_if_query_invalid_for_histogram(query, record_count)

        key = "trait_bank/stats/histogram/v2/#{query.to_cache_key}" # increment version number when changing query
        Rails.cache.fetch(key) do
          filter = query.filters.first

          wheres = ["t.normal_measurement IS NOT NULL"]
          wheres << "toFloat(t.normal_measurement) >= #{filter.num_val1}" if filter.num_val1.present?
          wheres << "toFloat(t.normal_measurement) <= #{filter.num_val2}" if filter.num_val2.present?

          count = query.record? ? "*" : "DISTINCT rec.page"

          buckets = [Math.sqrt(record_count), 20].min.ceil
          TraitBank.query(%Q[
            MATCH #{TraitBank.page_match(query, "page", "")},
            (tgt_p:Term{ uri: '#{filter.pred_uri}'}),
            (page)-[#{TraitBank::trait_rels_for_query_type(query)}]->(t:Trait)-[:predicate]->(:Term)-[#{TraitBank.parent_terms}]->(tgt_p)
            WITH DISTINCT page, t
            MATCH (t)-[:normal_units_term]->(u:Term)
            WITH page, u, toFloat(t.normal_measurement) AS m
            WHERE #{wheres.join(" AND ")}
            WITH u, collect({ page: page, val: m }) as recs, max(m) AS max, min(m) AS min
            WITH u, recs, max, min, max - min AS range
            WITH u, recs, #{self.num_fn_for_range("max", "ceil")} AS max,
            #{self.num_fn_for_range("min", "floor")} AS min
            WITH u, recs, max, min, max - min AS range
            WITH u, recs, max, min, CASE WHEN range < .001 THEN 1 ELSE (
            #{self.num_fn_for_range("range", "ceil", "/ #{buckets}")}
            ) END AS bw
            UNWIND recs as rec
            WITH rec, u, min, bw, floor((rec.val - min) / bw) AS bi
            WITH rec, u, min, bw, CASE WHEN bi = #{buckets} THEN bi - 1 ELSE bi END as bi
            WITH u, min, bi, bw, count(#{count}) AS c
            WITH u, collect({ min: min, bi: bi, bw: bw, c: c}) as units_rows
            ORDER BY reduce(total = 0, r in units_rows | total + r.c) DESC
            LIMIT 1
            UNWIND units_rows as r
            WITH u, r.min as min, r.bi as bi, r.bw as bw, r.c as c
            RETURN u, min, bi, bw, c
            ORDER BY bi ASC
          ])
        end
      end

      def num_fn_for_range(var, fn, add_op = nil)
        base_case  = add_op.nil? ?
          "#{fn}(#{var})" :
          "#{fn}(#{var} #{add_op})"

        %Q(
          CASE WHEN #{num_fn_for_range_case(0.002, 10000, fn, var, add_op)} ELSE (
            CASE WHEN #{num_fn_for_range_case(0.02, 1000, fn, var, add_op)} ELSE (
              CASE WHEN #{num_fn_for_range_case(0.2, 100, fn, var, add_op)} ELSE (
                CASE WHEN #{num_fn_for_range_case(2, 10, fn, var, add_op)} ELSE (
                  #{base_case}
                ) END
              ) END
            ) END
          ) END
        )
      end

      def num_fn_for_range_case(cutoff, coef, fn, var, add_op)
        fn_part = add_op.nil? ?
          "#{fn}(#{var} * #{coef}) / #{coef}" :
          "#{fn}((#{var} * #{coef}) #{add_op}) / #{coef}"

        "range < #{cutoff} THEN #{fn_part}"
      end

      #  "WITH ms, init_max, min, bw, (init_max - min) % bw as rem\n"\
      #  "WITH ms, min, bw, CASE WHEN rem = 0 THEN init_max ELSE init_max + bw - rem END AS max\n"\

      def check_query_valid_for_histogram(query, record_count)
        if record_count < MIN_RECORDS_FOR_HIST
          return CheckResult.invalid("record count doesn't meet minimum of #{MIN_RECORDS_FOR_HIST}")
        end

        if query.predicate_filters.length != 1
          return CheckResult.invalid("query must have a single predicate filter")
        end

        pred_uri = query.predicate_filters.first.pred_uri
        pred_result = check_predicate(pred_uri)
        return pred_result if !pred_result.valid?

        if query.object_term_filters.any?
          return CheckResult.invalid("query must not have any object term filters")
        end

        if !query.filters.first.units_for_pred?
          return CheckResult.invalid("query predicate does not have numerical values")
        end

        if !TraitBank::Terms.any_direct_records_for_pred?(pred_uri)
          return CheckResult.invalid("predicate does not have any directly associated records")
        end

        CheckResult.valid
      end


      def check_query_valid_for_counts(query)
        if query.filters.length != 1
          return CheckResult.invalid("query must have a single filter")
        end

        filter = query.filters.first
        pred_uri = filter.pred_uri

        if pred_uri.present?
          pred_result = check_predicate(pred_uri)
          return pred_result if !pred_result.valid?

          if filter.units_for_pred?
            return CheckResult.invalid("query predicate has numerical values")
          end

          #if (
          #    query.clade.present? &&
          #    record_count > RECORD_THRESHOLD
          #)
          #  return CheckResult.invalid("count exceeds threshold for search with clade")
          #end
        end

        if filter.numeric?
          return CheckResult.invalid("query must not be numeric")
        end

        CheckResult.valid
      end

      private

      def obj_counts_query_for_records(query, params)
        obj_var = "child_obj"
        trait_var = "trait"
        anc_var = "anc"
        match_part = TraitBank.term_record_search_matches(query, params, always_match_obj: true, obj_var: obj_var, trait_var: trait_var)

        %Q(
          #{match_part}
          WITH #{obj_var}, count(distinct #{trait_var}) AS trait_count
          #{count_query_anc_obj_match(query, obj_var, anc_var, params)}
          WITH DISTINCT #{anc_var}, #{obj_var}, trait_count
          WITH #{anc_var} AS obj, sum(trait_count) AS count
          RETURN obj, count
          ORDER BY count DESC
        )
      end

      def obj_counts_query_for_taxa(query, params)
        obj_var = "child_obj"
        anc_var = "anc"
        match_part = TraitBank.term_page_search_matches(query, params, always_match_obj: true, obj_var: obj_var)

        %Q(
          #{match_part}
          WITH #{obj_var}, collect(distinct page) as pages
          #{count_query_anc_obj_match(query, obj_var, anc_var, params)}
          WITH #{anc_var} AS obj, collect(pages) as list_of_lists_of_pages
          WITH obj, reduce(output = [], p in list_of_lists_of_pages | output + p) AS pages
          UNWIND pages AS page
          WITH obj, count(distinct page) AS count
          RETURN obj, count
          ORDER BY count DESC
        )
      end

      def count_query_anc_obj_match(query, obj_var, anc_var, params)
        result = "MATCH (#{obj_var})-[#{TraitBank.parent_terms}]->(#{anc_var}:Term)"
        filter = query.filters.first

        if filter.object_term?
          result.concat("-[#{TraitBank.parent_terms}]->(:Term { uri: $count_query_obj })")
          params[:count_query_obj] = filter.obj_uri
        end

        result.concat("\nWHERE #{anc_var}.is_hidden_from_select = false")

        result
      end

      def raise_if_query_invalid_for_counts(query)
        result = check_query_valid_for_counts(query)

        if !result.valid
          raise TypeError.new(result.reason)
        end
      end

      def raise_if_query_invalid_for_histogram(query, record_count)
        result = check_query_valid_for_histogram(query, record_count)

        if !result.valid
          raise TypeError.new(result.reason)
        end
      end

      def check_predicate(uri)
        predicate = uri && TermNode.find(uri)

        if predicate.nil?
          return CheckResult.invalid("failed to retrieve a Term with uri #{uri}")
        end

        if predicate.type != "measurement"
          return CheckResult.invalid("predicate type must be 'measurement'")
        end

        CheckResult.valid
      end
    end
  end
end
