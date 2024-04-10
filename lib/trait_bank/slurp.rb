require 'set'
require 'csv'

# NOTE: Publishing will call .load_resource_from_repo q.v..
class TraitBank::Slurp
  MAX_CSV_SIZE = 128_000
  MAX_SKIP_PKS = 1_000

  delegate :query, to: TraitBank

  def initialize(resource, logger = nil)
    @resource = resource
    logger ||= Publishing::PubLog.new(@resource, use_existing_log: true)
    @logger = logger
  end

  # TraitBank::Slurp.new(res).load_resource_from_repo # ...and wait.
  # NOTE: this is the method called by Publishing::Fast
  def load_resource_from_repo
    @diff_metadata = @resource.repo.trait_diff_metadata

    ResourceNode.create_if_missing(
      @resource.id,
      @resource.name,
      @resource.description,
      @resource.repository_id
    )

    remove_traits
    add_traits
    add_metadata

    @resource.touch
    @resource.update!(last_published_at: Time.now)

    @logger.info('Removing trait and metadata files')
    @resource.remove_traits_files
  end

  # TraitBank::Slurp.new(res).load_resource_metadata_from_repo # ...and wait.
  #def load_resource_metadata_from_repo
  #  @resource.repo.copy_file(@resource.meta_traits_file, 'metadata.tsv')
  #  config = load_csv_config
  #  metadata = config.keys.last
  #  load_csv(metadata, config[metadata])
  #  # "Touch" the resource so that it looks like it's been changed (it has):
  #  @resource.touch
  #  @resource.remove_traits_files
  #end

  def heal_traits
    @resource.repo.copy_file(@resource.traits_file, 'traits.tsv')
    @resource.repo.copy_file(@resource.meta_traits_file, 'metadata.tsv')
    heal_traits_by_type("traits_#{@resource.id}.csv", :Trait)
    heal_traits_by_type("meta_traits_#{@resource.id}.csv", :MetaTrait)
    post_load_cleanup
    @resource.remove_traits_files
  end

  def load_csvs
    config = load_csv_config
    config.each { |filename, file_config| load_csv(filename, file_config) }
    post_load_cleanup
    # "Touch" the resource so that it looks like it's been changed (it has):
    @resource.touch
  end

  def post_load_cleanup
    page_ids = read_field_from_traits_file('page_id')&.sort&.uniq&.compact
    return nil if page_ids.blank?
    fix_new_page_attributes(page_ids)
  end

  def read_field_from_traits_file(field)
    filename = "traits_#{@resource.id}.csv"
    file = Rails.public_path.join('data', filename)
    # read the traits file and pluck out the requested field...
    require 'csv'
    data = CSV.read(file)
    headers = data.shift
    return nil unless headers # Nothing in the file.
    return nil if headers.first == 'false' # The only thing in the file, when it's empty.
    position = headers.find_index(field)
    raise "Could not find #{field} field in #{filename}" if position.nil?
    values = {}
    data.each do |row|
      values[row[position]] = true
    end
    values.keys
  end

  def fix_new_page_attributes(page_ids)
    TraitBank::Denormalizer.update_attributes_by_page_id(page_ids)
  end

  class NodeConfig
    Attribute = Struct.new(:key, :val)

    attr_reader :label, :name, :pk_attr, :other_attrs

    def initialize(options)
      @label = options[:label]
      @name = options[:name] || @label.downcase
      build_attributes(options[:attributes])
    end

    private
    def build_attributes(attr_configs)
      attr_configs_copy = attr_configs.dup
      @pk_attr = build_attribute(attr_configs_copy.shift)
      @other_attrs = attr_configs_copy.map { |config| build_attribute(config) }
    end

    def build_attribute(attr_config)
      if attr_config.is_a?(Hash) # e.g., { page_id: 'row.object_page_id' }
        key = attr_config.keys.first
        val = attr_config[key]
      else # assume it's a String/Symbol
        key = attr_config
        val = "row.#{key}"
      end

      Attribute.new(key, val)
    end
  end

  # TODO: (eventually) target_scientific_name: row.target_scientific_name
  def load_csv_config
    { :traits =>
      {
        checks: { # NOTE: Only supported for traits file!
          "1=1" => {
            matches: [
              '(page:Page { page_id: toInteger(row.page_id) })',
              '(predicate:Term { uri: row.predicate })-[:exclusive_to_clade]->(clade:Page)'
            ],
            fail_condition: '(page)-[:parent]->(:Page) AND NOT (page)-[:parent*0..]->(clade)',
            returns: ['row.page_id AS page_id', 'row.eol_pk AS eol_pk', 'row.predicate AS term_uri'],
            message: 'exclusive_to_clade check failed!'
          },
          is_not_blank("row.value_uri") => {
            matches: [
              '(object_term:Term { uri: row.value_uri })',
              '(page:Page { page_id: toInteger(row.page_id) })',
              '(object_term)-[:incompatible_with_clade]->(clade:Page)'
            ],
            fail_condition: '(clade)<-[:parent*0..]-(page)',
            returns: ['page.page_id AS page_id', 'row.eol_pk AS eol_pk', 'row.value_uri AS term_uri'],
            message: 'incompatible_with_clade check failed for the following [page_id, object_term_uri, clade_id]s:'
          }
        },
        nodes: [
          NodeConfig.new(label: 'Page', attributes: [:page_id]),
          NodeConfig.new(label: 'Trait', attributes: %i[
              eol_pk resource_pk source literal measurement scientific_name normal_measurement sample_size citation remarks method
            ]
          )
        ],
        wheres: {
          # This will be applied to ALL rows:
          "1=1" => {
            matches: {
              predicate: 'Term { uri: row.predicate }',
              resource: "Resource { resource_id: #{@resource.id} }"
            },
            # NOTE: merges are expressed as a triple, e.g.: [source variable, relationship name, target variable]
            merges: [
              [:page, :trait, :trait],
              [:trait, :predicate, :predicate],
              [:trait, :supplier, :resource]
            ],
          },
          "#{is_not_blank('row.sex')}" =>
          {
            matches: { sex: 'Term { uri: row.sex }' },
            merges: [ [:trait, :sex_term, :sex] ]
          },
          "#{is_not_blank('row.lifestage')}" =>
          {
            matches: { lifestage: 'Term { uri: row.lifestage }' },
            merges: [ [:trait, :lifestage_term, :lifestage] ]
          },
          "#{is_not_blank('row.statistical_method')}" =>
          {
            matches: { statistical_method: 'Term { uri: row.statistical_method }' },
            merges: [ [:trait, :statistical_method_term, :statistical_method] ]
          },
          "#{is_blank('row.value_uri')} AND #{is_not_blank('row.units')}" =>
          {
            matches: { units: 'Term { uri: row.units }' },
            merges: [ [:trait, :units_term, :units] ]
          },
          "#{is_not_blank('row.normal_units_uri')}" =>
          {
            matches: { normal_units: 'Term { uri: row.normal_units_uri }' },
            merges: [ [:trait, :normal_units_term, :normal_units] ]
          },
          "#{is_not_blank('row.value_uri')} AND #{is_blank('row.units')}" =>
          {
            matches: { object_term: 'Term { uri: row.value_uri }' },
            merges: [ [:trait, :object_term, :object_term] ]
          },
          is_not_blank('row.object_page_id') =>
          {
            nodes: [
              NodeConfig.new(label: 'Page', name: 'object_page', attributes: [{
                  page_id: 'row.object_page_id'
                }]
              )
            ],
            merges: [ [:trait, :object_page, :object_page ] ]
          },
          is_not_blank('row.contributor_uri') =>
          {
            matches: { contributor: 'Term { uri: row.contributor_uri }' },
            merges: [ [:trait, :contributor, :contributor] ]
          },
          is_not_blank('row.compiler_uri') =>
          {
            matches: { compiler: 'Term { uri: row.compiler_uri }' },
            merges: [ [:trait, :compiler, :compiler] ]
          },
          is_not_blank('row.determined_by_uri') =>
          {
            matches: { determined_by: 'Term { uri: row.determined_by_uri }' },
            merges: [ [:trait, :determined_by, :determined_by] ]
          }
        }
      },
      :metadata =>
      {
        nodes: [
          NodeConfig.new(label: 'MetaData', attributes: %i[eol_pk source literal measurement])
        ],
        wheres: {
          "1=1" => { # ALL ROWS
            matches: {
              trait: 'Trait { eol_pk: row.trait_eol_pk }',
              predicate: 'Term { uri: row.predicate }'
            },
            merges: [
              [:trait, :metadata, :metadata],
              [:metadata, :predicate, :predicate]
            ],
          },
          "#{is_not_blank('row.sex')}" =>
          {
            matches: { sex: 'Term { uri: row.sex }' },
            merges: [ [:metadata, :sex_term, :sex] ]
          },
          "#{is_not_blank('row.lifestage')}" =>
          {
            matches: { lifestage: 'Term { uri: row.lifestage }' },
            merges: [ [:metadata, :lifestage_term, :lifestage] ]
          },
          "#{is_not_blank('row.statistical_method')}" =>
          {
            matches: { statistical_method: 'Term { uri: row.statistical_method }' },
            merges: [ [:metadata, :statistical_method_term, :statistical_method] ]
          },
          "#{is_blank('row.value_uri')} AND #{is_not_blank('row.units')}" =>
          {
            matches: { units: 'Term { uri: row.units }' },
            merges: [ [:metadata, :units_term, :units] ]
          },
          "#{is_not_blank('row.value_uri')} AND #{is_blank('row.units')}" =>
          {
            matches: { object_term: 'Term { uri: row.value_uri }' },
            merges: [ [:metadata, :object_term, :object_term] ]
          },
          is_true('row.is_external') => {
            matches: { resource: "Resource { resource_id: #{@resource.id} }" },
            merges: [ [:metadata, :supplier, :resource] ]
          }
        }
      }
    }
  end

  def load_csv(filename, config, params = {})
    checks = config[:checks]
    wheres = config[:wheres]
    nodes = config[:nodes]

    break_up_large_files(filename) do |sub_filename|
      # check trait validity
      skip_pks = Set.new

      # XXX: Disabled due to small resources timing out. This may be worth revisiting in the future.
      # - mvitale
      #if checks
      #  @logger.info("Running validity checks for #{sub_filename}")

      #  checks.each do |where_clause, check|
      #    skip_pks.merge(run_check(sub_filename, where_clause, check))
      #  end

      #  if skip_pks.length > MAX_SKIP_PKS
      #    @logger.warn("WARNING: Too many invalid rows (#{skip_pks.length})! Not skipping any. This may result in bad data!")
      #    skip_pks = Set.new
      #  end
      #end

      @logger.info("Importing #{MAX_CSV_SIZE} rows from #{sub_filename}")

      # build nodes required by all rows
      nodes.each do |node|
        try_again = true
        begin
          where = skip_pks.any? ?
            "NOT row.eol_pk IN [#{skip_pks.map { |pk| "'#{pk}'" }.join(', ')}]" :
            nil

          build_nodes(node, csv_query_head(sub_filename, where))
        rescue => e
          if try_again
            try_again = false
            @logger.warn(e.message)
            @logger.warn("FAILED on build_nodes query (#{node.label}), will "\
                         "re-try once...")
            retry
          end
        end
      end

      wheres.each do |clause, where_config|
        load_csv_where(clause, filename: sub_filename, nodes: nodes, config: where_config)
      end
    end
  end

  def break_up_large_files(filename)
    line_count = size_of_file(filename)
    if line_count < MAX_CSV_SIZE
      yield filename
    else
      num_chunks = (line_count / MAX_CSV_SIZE.to_f).ceil
      @logger.warn("Found #{line_count} rows, will break up into #{MAX_CSV_SIZE}")
      break_up_large_file(filename, line_count) do |sub_filename, chunk|
        yield sub_filename
      end
    end
  end

  def break_up_large_file(filename, line_count)
    basename = File.basename(filename, '.*') # It's .csv, but I want to be safe...
    lines_without_header = line_count - 1
    # NOTE: without #ceil and #to_f, this yields a floor. We will run an *additional* "chunk" after going through this
    # number of chunks.
    chunks = lines_without_header / MAX_CSV_SIZE
    tail = lines_without_header % MAX_CSV_SIZE
    # NOTE: Each one of these head/tail commands can take a few seconds.
    (1..chunks).each do |chunk|
      if chunk > 1
        # TODO: it would, of course, be best if we had some way to *check* whether the DB is ready... consider.
        wait_time = chunk * 2.minutes
        wait_time = 30.minutes if wait_time > 30.minutes
        @logger.info("Waiting #{wait_time / 60} minutes for the last 'chunk' to be added to neo4j...")
        sleep(wait_time)
      end
      sub_file = sub_file_name(basename, chunk)
      copy_head(filename, sub_file)
      `head -n #{MAX_CSV_SIZE * chunk + 1} #{resource_file_dir}/#{filename} | tail -n #{MAX_CSV_SIZE} >> #{resource_file_dir}/#{sub_file}`
      yield(sub_file, chunk)
      File.unlink("#{resource_file_dir}/#{sub_file}")
    end
    unless tail.zero?
      sub_file = sub_file_name(basename, chunks + 1)
      copy_head(filename, sub_file)
      `tail -n #{tail} #{resource_file_dir}/#{filename} >> #{resource_file_dir}/#{sub_file}`
      yield(sub_file, chunks + 1)
      File.unlink("#{resource_file_dir}/#{sub_file}")
    end
  end

  def size_of_file(filename)
    # NOTE: Just this word-count can take a few seconds on a large file!
    `wc -l #{resource_file_dir}/#{filename}`.strip.split(' ').first.to_i
  end

  def copy_head(filename, sub_file)
    `head -n 1 #{resource_file_dir}/#{filename} > #{resource_file_dir}/#{sub_file}`
  end

  def sub_file_name(basename, chunk)
    "#{basename}_chunk_#{chunk}.csv"
  end

  # TODO: this is really all wrong. We should be passing around the path, but when I looked into doing that, it became
  # obvious that this shouldn't be done with class methods, but an instance that can store at least the resource, if
  # not also the path being used. So, for now, I am just hacking it. Sigh.
  def resource_file_dir
    @resource.file_dir
  end

  def heal_traits_by_type(filename, label)
    file = filename =~ /\// ? filename : "#{Rails.public_path}/#{filename}"
    position = nil
    correct_pks = Set.new
    CSV.foreach(file) do |row|
      if position.nil?
        position = row.index { |c| c.downcase.gsub(/^\s+/, '').gsub(/\s+$/, '') == 'eol_pk' }
        raise("CANNOT FIND eol_pk COLUMN IN #{file}!") unless position
      else
        correct_pks << row[position]
      end
    end
    data = query("MATCH (:Resource { resource_id: #{@resource.id} })<-[:supplier]-(n:#{label}) "\
      "RETURN n.eol_pk")
    traitbank_pks = Set.new
    data['data'].each { |row| traitbank_pks << row.first }
    extra_pks = traitbank_pks - correct_pks
    raise "Ooops! This resource has been copmpletely reharvested; you need to re-publish it entirely." if
      extra_pks.size == traitbank_pks.size
    return 0 if extra_pks.size.zero?
    extra_pks.to_a.in_groups_of(1000) do |pks|
      TraitBank::Admin.remove_with_query(
        name: node,
        q: "(node:#{label}) WHERE node.eol_pk IN ['#{pks.join("','")}']"
      )
    end
    extra_pks.size
  end

  def load_csv_where(clause, options = {})
    filename = options[:filename]
    config = options[:config]
    global_nodes = options[:nodes] # NOTE: this is neo4j "nodes", not EOL "Node"; unfortunate collision.
    where_nodes = config[:nodes] || []
    merges = Array(config[:merges])
    matches = config[:matches]
    head = csv_query_head(filename, clause)

    # First, build all of the nodes specific to this where clause
    where_nodes.each do |node_config|
      build_nodes(node_config, head)
    end

    # Then the merges, one at a time:
    merges.each { |triple| merge_triple(triple: triple, head: head, nodes: global_nodes + where_nodes, matches: matches) }
  end

  def csv_query_file_location(filename)
    filename =~ /^http/ ?
      filename :
      Rails.configuration.eol_web_url +
        "/#{@resource.file_dir.relative_path_from(Rails.root.join('public'))}" +
        "/#{filename}"
  end

  def csv_query_head(filename, where_clause = nil)
    where_clause ||= '1=1'
    file = csv_query_file_location(filename)
    "USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM '#{file}' AS row WITH row WHERE #{where_clause} "
  end

  def csv_check_head(filename, where_clause)
    file = csv_query_file_location(filename)
    "LOAD CSV WITH HEADERS FROM '#{file}' AS row WITH row WHERE #{where_clause}"
  end

  # TODO: extract the file-writing to a method that takes a block.
  def build_ancestry
    require 'csv'
    old_version = get_old_ancestry_version
    new_version = old_version + 1
    # NOTE: batch size of 10_000 was a bit too slow, and imagine it'll get worse with more pages.
    Page
      .includes(native_node: :parent)
      .joins(native_node: :parent)
      .where("nodes.resource_id = #{Resource.native.id}")
      .find_in_batches(batch_size: 5_000) do |group|
      CSV.open(ancestry_file_path, 'w') do |csv|
        csv << ['page_id', 'parent_id']
        group.each do |page|
          next if page.native_node.parent.page_id.nil?
          csv << [page.id, page.native_node.parent.page_id]
        end
      end
      rebuild_ancestry_group('ancestry.csv', new_version)
    end
    remove_ancestry(old_version) # You can't run this twice on the same resource without downtime.
  end

  def get_old_ancestry_version
    r = query("MATCH (p:Page)-[rel:parent]->(:Page) RETURN MAX(rel.ancestry_version)")
    return 0 unless r&.is_a?(Hash)
    r['data'].first.first.to_i
  end

  def remove_ancestry(old_version)
    # I am worried this will timeout when we have enough of them. Already takes 24s with a 10th of what we'll have...
    TraitBank::Admin.remove_with_query(
      name: :rel,
      q: "MATCH (p:Page)-[rel:parent {ancestry_version: #{old_version}}]->(:Page) DELETE rel"
    )
  end

  def ancestry_file_path
    @ancestry_file_path ||= Rails.public_path.join('data', 'ancestry.csv')
  end

  def rebuild_ancestry_group(file, version)
    # Nuke it from orbit:
    execute_clauses([csv_query_head(file), 'MERGE (:Page { page_id: toInteger(row.page_id) })'])
    execute_clauses([csv_query_head(file), 'MERGE (:Page { page_id: toInteger(row.parent_id) })'])
    execute_clauses([csv_query_head(file),
                    'MATCH (page:Page { page_id: toInteger(row.page_id) })',
                    'MATCH (parent:Page { page_id: toInteger(row.parent_id) })',
                    "MERGE (page)-[:parent { ancestry_version: #{version} }]->(parent)"])
  end

  def execute_clauses(clauses)
    autocommit_query(clauses.join("\n"))
  end

  def build_nodes(config, head)
    pk_attr = config.pk_attr
    q = "#{head}MERGE (#{config.name}:#{config.label} { #{pk_attr.key}: #{autocast_val(pk_attr)} })"
    config.other_attrs.each do |attr|
      q << set_attribute(config.name, attr, 'CREATE')
      q << set_attribute(config.name, attr, 'MATCH')
    end
    autocommit_query(q)
  end

  def merge_triple(options)
    triple = options[:triple]
    head = options[:head]
    nodes = options[:nodes] || []
    matches = options[:matches] || []
    # merges: [ [:trait, :units_term, :units] ]
    # NOTE: #to_s to make matching simpler.
    subj = triple[0].to_s
    pred = triple[1].to_s
    obj  = triple[2].to_s
    q = head

    nodes.each do |node|
      next unless subj == node.name || obj == node.name
      q += "\nMATCH (#{node.name}:#{node.label} { #{node.pk_attr.key}: #{autocast_val(node.pk_attr)} })"
    end

    # MATCH any ... uhhh... matches required:
    matches.each do |name, match|
      # matches: { object_term: ':Term { uri: row.value_uri }' },
      name = name.to_s
      next unless subj == name || obj == name
      q += "\nMATCH (#{name}:#{match})"
    end

    # Then merge the triple:
    query = "#{q}\nMERGE (#{subj})-[:#{pred}]->(#{obj})"
    begin
      autocommit_query(query)
    rescue => e
      @logger.warn("Exception (#{e.class}) FROM: #merge_triple QUERY: {#{q}}")
      raise
    end
  end

  def set_attribute(name, attribute, on_set)
    "\nON #{on_set} SET #{name}.#{attribute.key} = #{autocast_val(attribute)}"
  end

  # NOTE: This code automatically makes integers out of any attribute ending in "_id" or "_num". BE AWARE!
  def autocast_val(attr)
    # NOTE: This code automatically makes integers out of any attribute ending in "_id" or "_num". BE AWARE!
    return "toInteger(#{attr.val})" if attr.key =~ /_(num|id)$/
    attr.val
  end

  def is_not_blank(field)
    "(#{field} IS NOT NULL AND TRIM(#{field}) <> '')"
  end

  def is_blank(field)
    "(#{field} IS NULL OR TRIM(#{field}) = '')"
  end

  def is_true(field)
    "(#{field} = 'true')"
  end

  def autocommit_query(q) # for use with WITH PERIODIC COMMIT queries (CSV loading)
    #@logger&.info("Executing PERIODIC COMMIT query:\n#{q}")

    begin
      ActiveGraph::Base.session do |session|
        session.run(q)
      end
    rescue => e
      @logger.warn("Exception (#{e.class}) QUERY: {#{q}} MESSAGE: #{e.message}")
      raise
    end
  end

  def add_traits
    if @diff_metadata.new_traits_file.nil?
      @logger.info('no traits to add')
      return
    end

    @logger.info('adding new traits')
    load_csv(@diff_metadata.new_traits_file, load_csv_config[:traits])
  end

  def add_metadata
    if @diff_metadata.new_metadata_file.nil?
      @logger.info('no metadata to add')
      return
    end

    @logger.info('adding new metadata')
    load_csv(@diff_metadata.new_metadata_file, load_csv_config[:metadata])
  end

  def remove_traits
    if @diff_metadata.removed_traits_file.present?
      @logger.info('removing traits specified in diff file')

      count = 0
      CSV.foreach(resource_file_dir.join(@diff_metadata.removed_traits_file), headers: true) do |row|
        if row['eol_pk']
          TraitBank::Admin.remove_trait_and_metadata(row['eol_pk'])
        end

        count += 1
      end

      @logger.info("removed #{count} traits")
    else
      @logger.info('not removing any traits')
    end
  end

  #def run_check(filename, row_where_clause, check)
  #  head = csv_check_head(filename, row_where_clause)
  #  query = <<~CYPHER
  #    #{head}
  #    MATCH #{check[:matches].join(", ")}
  #    #{check[:optional_matches]&.any? ? "OPTIONAL MATCH #{check[:optional_matches].join(", ")}" : ''}
  #    WHERE #{check[:fail_condition]}
  #    RETURN DISTINCT #{check[:returns].join(", ")}
  #  CYPHER

  #  result = ActiveGraph::Base.query(query).to_a

  #  skip_pks = []

  #  if result.any?
  #    @logger.error(check[:message])

  #    values_to_log = []
  #    result.each do |row|
  #      skip_pks << row[:eol_pk]
  #      values_to_log << [row[:page_id], row[:term_uri]]
  #    end

  #    @logger.error('[page_id, term_uri] pairs logged above')
  #    @logger.error("Too many rows to log! This is just a sample.") if values_to_log.length > MAX_SKIP_PKS
  #    @logger.error(values_to_log[0..MAX_SKIP_PKS].map { |v| "[#{v.join(', ')}]" }.join(', '))
  #  end

  #  skip_pks
  #end
end
