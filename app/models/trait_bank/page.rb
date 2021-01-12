module TraitBank
  module Page
    class << self
      include TraitBank::Constants

      def page_traits_by_group(page_id, options = {})
        limit = options[:limit] || 5 # limit is per predicate
        key = "trait_bank/page_traits_by_group/v2/#{page_id}/limit_#{limit}"
        TraitBank::Caching.add_hash_to_key(key, options)

        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            OPTIONAL MATCH (page:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(predicate:Term)-[:parent_term|:synonym_of*0..]->(group_predicate:Term),
            (trait)-[:supplier]->(resource:Resource#{TraitBank::Queries.resource_filter_part(options[:resource_id])})
            WHERE NOT (group_predicate)-[:synonym_of]->(:Term)
            OPTIONAL MATCH #{EXEMPLAR_MATCH}
            WITH group_predicate, page, trait, predicate, resource, exemplar_value
            ORDER BY group_predicate.uri ASC, #{EXEMPLAR_ORDER}
            WITH group_predicate, page, collect(DISTINCT { trait: trait, predicate: predicate, resource: resource })[0..#{limit}] AS trait_rows, count(DISTINCT trait) AS trait_count
            UNWIND trait_rows AS trait_row
            WITH collect({ group_predicate: group_predicate, page_assoc_role: 'subject', page: page, trait_count: trait_count, trait: trait_row.trait, predicate: trait_row.predicate, resource: trait_row.resource }) AS subject_rows
            OPTIONAL MATCH (page:Page)-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(predicate:Term)-[:parent_term|:synonym_of*0..]->(group_predicate:Term), (trait)-[:object_page]->(object_page:Page { page_id: #{page_id} }),
            (trait)-[:supplier]->(resource:Resource#{TraitBank::Queries.resource_filter_part(options[:resource_id])})
            WHERE NOT (group_predicate)-[:synonym_of]->(:Term)
            OPTIONAL MATCH #{EXEMPLAR_MATCH}
            WITH group_predicate, page, trait, predicate, resource, exemplar_value, subject_rows
            ORDER BY group_predicate.uri ASC, #{EXEMPLAR_ORDER}
            WITH group_predicate, subject_rows, collect(DISTINCT { page: page, trait: trait, predicate: predicate, resource: resource })[0..#{limit}] AS trait_rows, count(DISTINCT trait) AS trait_count
            UNWIND trait_rows AS trait_row
            WITH subject_rows, collect({ group_predicate: group_predicate, page_assoc_role: 'object', trait_count: trait_count, page: trait_row.page, trait: trait_row.trait, predicate: trait_row.predicate, resource: trait_row.resource }) AS object_rows
            UNWIND (subject_rows + object_rows) AS row
            WITH row.group_predicate AS group_predicate, row.page_assoc_role AS page_assoc_role, row.trait_count AS trait_count, row.page AS page, row.trait AS trait, row.predicate AS predicate, row.resource AS resource, (row.trait.eol_pk + row.group_predicate.eol_id + row.page_assoc_role) AS row_id
            WHERE trait IS NOT NULL
            OPTIONAL MATCH (trait)-[:object_term]->(object_term:Term)
            OPTIONAL MATCH (trait)-[:sex_term]->(sex_term:Term)
            OPTIONAL MATCH (trait)-[:lifestage_term]->(lifestage_term:Term)
            OPTIONAL MATCH (trait)-[:statistical_method_term]->(statistical_method_term:Term)
            OPTIONAL MATCH (trait)-[:units_term]->(units:Term)
            OPTIONAL MATCH (trait)-[:object_page]->(object_page:Page)
            RETURN page_assoc_role, resource, page, trait, predicate, group_predicate, object_term, object_page, units, sex_term, lifestage_term, statistical_method_term, trait_count, row_id
          ))

          TraitBank::ResultHandling.build_trait_array(res, identifier: 'row_id')
        end
      end

      def all_page_trait_resource_ids(page_id, options = {})
        key = "trait_bank/all_page_trait_resource_ids/v1/#{page_id}"
        TraitBank::Caching.add_hash_to_key(key, options)

        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            OPTIONAL MATCH (:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(predicate:Term),
            (trait)-[:supplier]->(resource:Resource)
            WITH collect(DISTINCT resource) AS subj_resources
            OPTIONAL MATCH (:Page)-[#{TRAIT_RELS}]-(trait:Trait)-[:predicate]->(predicate:Term),
            (trait)-[:object_page]->(:Page { page_id: #{page_id} }),
            (trait)-[:supplier]->(resource:Resource)
            WITH collect(DISTINCT resource) AS obj_resources, subj_resources
            UNWIND (subj_resources + obj_resources) AS resource
            RETURN DISTINCT resource.resource_id
          ))

          res["data"].flatten
        end
      end

      def page_subj_trait_resource_ids(page_id, options = {})
        key = "trait_bank/page_subj_trait_resource_ids/v1/#{page_id}"
        add_hash_to_key(key, options)

        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            MATCH (:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(predicate:Term)#{predicate_filter_match_part(options)},
            (trait)-[:supplier]->(resource:Resource)
            RETURN DISTINCT resource.resource_id
          ))

          res["data"].flatten
        end
      end

      def page_obj_trait_resource_ids(page_id, options = {})
        key = "trait_bank/page_obj_trait_resource_ids/v1/#{page_id}"
        add_hash_to_key(key, options)

        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            MATCH (:Page)-[#{TRAIT_RELS}]-(trait:Trait)-[:predicate]->(predicate:Term)#{predicate_filter_match_part(options)},
            (trait)-[:object_page]->(:Page { page_id: #{page_id} }),
            (trait)-[:supplier]->(resource:Resource)
            RETURN DISTINCT resource.resource_id
          ))

          res["data"].flatten
        end
      end

      def page_subj_traits_for_pred(page_id, pred_uri, options = {})
        key = "trait_bank/page_subj_traits_for_pred/v2/#{page_id}/#{pred_uri}"
        TraitBank::Caching.add_hash_to_key(key, options)

        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            MATCH (:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(predicate:Term)-[:parent_term|:synonym_of*0..]->(group_predicate:Term{ uri: '#{pred_uri}'}),
            (trait)-[:supplier]->(resource:Resource#{TraitBank::Queries.resource_filter_part(options[:resource_id])})
            OPTIONAL MATCH (trait)-[:object_term]->(object_term:Term)
            OPTIONAL MATCH (trait)-[:sex_term]->(sex_term:Term)
            OPTIONAL MATCH (trait)-[:lifestage_term]->(lifestage_term:Term)
            OPTIONAL MATCH (trait)-[:statistical_method_term]->(statistical_method_term:Term)
            OPTIONAL MATCH (trait)-[:units_term]->(units:Term)
            OPTIONAL MATCH (trait)-[:object_page]->(object_page:Page)
            OPTIONAL MATCH #{EXEMPLAR_MATCH}
            RETURN resource, trait, predicate, group_predicate, object_term, object_page, units, sex_term, lifestage_term, statistical_method_term
            ORDER BY #{EXEMPLAR_ORDER}
          ))

          build_trait_array(res)
        end
      end

      def page_obj_traits_for_pred(page_id, pred_uri, options = {})
        key = "trait_bank/all_page_object_traits_for_pred/v2/#{page_id}/#{pred_uri}"
        TraitBank::Caching.add_hash_to_key(key, options)

        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            MATCH (page:Page)-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(predicate:Term)-[:parent_term|:synonym_of*0..]->(group_predicate:Term{ uri: '#{pred_uri}'}),
            (trait)-[:supplier]->(resource:Resource#{TraitBank::Queries.resource_filter_part(options[:resource_id])}),
            (trait)-[:object_page]->(object_page:Page { page_id: #{page_id} })
            OPTIONAL MATCH (trait)-[:object_term]->(object_term:Term)
            OPTIONAL MATCH (trait)-[:sex_term]->(sex_term:Term)
            OPTIONAL MATCH (trait)-[:lifestage_term]->(lifestage_term:Term)
            OPTIONAL MATCH (trait)-[:statistical_method_term]->(statistical_method_term:Term)
            OPTIONAL MATCH (trait)-[:units_term]->(units:Term)
            RETURN resource, trait, page, predicate, group_predicate, object_term, object_page, units, sex_term, lifestage_term, statistical_method_term
          ))

          build_trait_array(res)
        end
      end

      def page_trait_groups(page_id, options = {})
        key = "trait_bank/page_trait_groups/v1/#{page_id}"
        TraitBank::Caching.add_hash_to_key(key, options)
        Rails.cache.fetch(key) do
          res = TraitBank::Connector.query(%Q(
            OPTIONAL MATCH (:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(:Term)-[:parent_term|:synonym_of*0..]->(group_predicate:Term),
            (trait)-[:supplier]->(resource:Resource#{TraitBank::Queries.resource_filter_part(options[:resource_id])})
            WHERE NOT (group_predicate)-[:synonym_of]->(:Term)
            WITH DISTINCT group_predicate
            WITH collect({ group_predicate: group_predicate, page_assoc_role: 'subject' }) AS subj_rows
            OPTIONAL MATCH (:Page)-[#{TRAIT_RELS}]->(trait:Trait)-[:predicate]->(:Term)-[:parent_term|:synonym_of*0..]->(group_predicate:Term),
            (trait)-[:object_page]-(:Page { page_id: #{page_id} }),
            (trait)-[:supplier]->(resource:Resource#{TraitBank::Queries.resource_filter_part(options[:resource_id])})
            WHERE NOT (group_predicate)-[:synonym_of]->(:Term)
            WITH DISTINCT group_predicate, subj_rows
            WITH collect({ group_predicate: group_predicate, page_assoc_role: 'object' }) AS obj_rows, subj_rows
            UNWIND (subj_rows + obj_rows) AS row
            WITH row.group_predicate AS group_predicate, row.page_assoc_role AS page_assoc_role
            WHERE group_predicate IS NOT NULL
            RETURN group_predicate, page_assoc_role
          ))

          res["data"].collect { |d| { group_predicate: d[0]["data"].symbolize_keys, page_assoc_role: d[1] } }
        end
      end

      def key_data(page_id, limit)
        Rails.cache.fetch("trait_bank/key_data/#{page_id}/v5/limit_#{limit}", expires_in: 1.day) do
          # predicate.is_hidden_from_overview <> true seems wrong but I had weird errors with NOT "" on my machine -- mvitale
          q = %Q(
            OPTIONAL MATCH (page:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait),
            (trait)-[:predicate]->(predicate:Term)
            WHERE predicate.is_hidden_from_overview <> true AND (NOT (trait)-[:object_term]->(:Term) OR (trait)-[:object_term]->(:Term{ is_hidden_from_overview: false }))
            OPTIONAL MATCH #{EXEMPLAR_MATCH}
            WITH page, predicate, trait, exemplar_value
            ORDER BY predicate.uri ASC, #{EXEMPLAR_ORDER}
            WITH page, predicate, head(collect({ trait: trait, exemplar_value: exemplar_value })) AS trait_row
            WITH page, predicate, trait_row.trait AS trait, trait_row.exemplar_value AS exemplar_value
            OPTIONAL MATCH (trait)-[:object_page]->(object_page:Page)
            WITH collect({ page_assoc_role: 'subject', page: page, object_page: object_page, predicate: predicate, trait: trait, exemplar_value: exemplar_value }) AS subj_rows  
            OPTIONAL MATCH (page:Page)-[#{TRAIT_RELS}]->(trait:Trait)-[:object_page]->(object_page:Page { page_id: #{page_id} }),
            (trait)-[:predicate]->(predicate:Term)
            WHERE predicate.is_hidden_from_overview <> true
            OPTIONAL MATCH #{EXEMPLAR_MATCH}
            WITH page, predicate, trait, object_page, exemplar_value, subj_rows
            ORDER BY predicate.uri ASC, #{EXEMPLAR_ORDER}
            WITH page, object_page, predicate, subj_rows, head(collect({ trait: trait, exemplar_value: exemplar_value })) AS trait_row
            WITH page, object_page, predicate, subj_rows, trait_row.trait AS trait, trait_row.exemplar_value AS exemplar_value
            WITH collect({ page_assoc_role: 'object', page: page, object_page: object_page, predicate: predicate, trait: trait, exemplar_value: exemplar_value }) AS obj_rows, subj_rows
            UNWIND (subj_rows + obj_rows) AS row
            WITH row.page_assoc_role AS page_assoc_role, row.page AS page, row.object_page AS object_page, row.predicate AS predicate, row.trait AS trait, row.exemplar_value AS exemplar_value
            WHERE trait IS NOT NULL
            OPTIONAL MATCH (trait)-[:object_term]->(object_term:Term)
            OPTIONAL MATCH (trait)-[:sex_term]->(sex_term:Term)
            OPTIONAL MATCH (trait)-[:lifestage_term]->(lifestage_term:Term)
            OPTIONAL MATCH (trait)-[:statistical_method_term]->(statistical_method_term:Term)
            OPTIONAL MATCH (trait)-[:units_term]->(units:Term)
            RETURN page, trait, predicate, object_term, object_page, units, sex_term, lifestage_term, statistical_method_term, page_assoc_role
            ORDER BY #{EXEMPLAR_ORDER}
            LIMIT #{limit}
          )

          res = TraitBank::Connector.query(q)
          TraitBank::ResultHandling.build_trait_array(res)
        end
      end

      def create_page(id)
        if (page = page_exists?(id))
          return page
        end
        page = connection.create_node(page_id: id)
        connection.set_label(page, "Page")
        page
      end

      def count_pages
        q = "MATCH (page:Page) RETURN COUNT(page)"
        res = query(q)
        return [] if res["data"].empty?
        res["data"] ? res["data"].first.first : 0
      end

      def page_exists?(page_id)
        res = query("MATCH (page:Page { page_id: #{page_id} }) RETURN page")
        res["data"] && res["data"].first ? res["data"].first.first : false
      end

      def association_page_ids(page_id)
        Rails.cache.fetch("trait_bank/association_page_ids/#{page_id}", expires_in: 1.day) do
          q = %Q(
            OPTIONAL MATCH (:Page { page_id: #{page_id} })-[#{TRAIT_RELS}]->(trait:Trait), (trait)-[:object_page]->(obj_page:Page)
            WITH collect(DISTINCT obj_page.page_id) AS obj_page_ids
            OPTIONAL MATCH (subj_page:Page)-[#{TRAIT_RELS}]->(trait:Trait), (trait)-[:object_page]->(:Page { page_id: #{page_id} })
            WITH collect(DISTINCT subj_page.page_id) AS subj_page_ids, obj_page_ids
            UNWIND (obj_page_ids + subj_page_ids) AS page_id
            WITH page_id
            WHERE page_id IS NOT NULL
            RETURN DISTINCT page_id
          )
          result = TraitBank::Connector.query(q)
          result["data"].flatten
        end
      end

      def object_traits_by_page(page_id, page = 1, per = 2000)
        Rails.cache.fetch("trait_bank/object_traits_by_page/#{page_id}", expires_in: 1.day) do
          q = %Q(
            MATCH (object_page:Page{ page_id: #{page_id} })<-[:object_page]-(trait:Trait),
            (page:Page)-[#{TRAIT_RELS}]->(trait),
            (trait)-[:predicate]->(predicate:Term),
            (trait)-[:supplier]->(resource:Resource)
            WITH trait, page, object_page, predicate, resource
            #{TraitBank::Queries.limit_and_skip_clause(page, per)}
            OPTIONAL MATCH (trait)-[:sex_term]->(sex_term:Term)
            OPTIONAL MATCH (trait)-[:lifestage_term]->(lifestage_term:Term)
            OPTIONAL MATCH (trait)-[:statistical_method_term]->(statistical_method_term:Term)
            OPTIONAL MATCH (trait)-[:units_term]->(units:Term)
            RETURN trait, page, resource, predicate, object_page, units, sex_term, lifestage_term, statistical_method_term
          )

          res = TraitBank::Connector.query(q)
          TraitBank::ResultHandling.build_trait_array(res)
        end
      end
    end
  end
end
