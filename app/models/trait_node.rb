# Yes, if you are investigating the data, you want to use this. e.g.:
# bad_trait = TraitNode.find("R520-PK96770863")
# bad_trait.metadata # etc, etc.
class TraitNode
  include ActiveGraph::Node

  self.mapped_label_name = 'Trait'

  id_property :eol_pk
  property :measurement
  property :normal_measurement
  property :sample_size
  property :citation
  property :source
  property :remarks
  property :method
  property :literal
  property :scientific_name

  has_one :out, :predicate, type: :predicate, model_class: :TermNode
  has_one :out, :object_term, type: :object_term, model_class: :TermNode
  has_one :out, :units_term, type: :units_term, model_class: :TermNode
  has_one :out, :lifestage_term, type: :lifestage_term, model_class: :TermNode
  has_one :out, :statistical_method_term, type: :statistical_method_term, model_class: :TermNode
  has_one :out, :sex_term, type: :sex_term, model_class: :TermNode
  has_one :out, :object_page, type: :object_page, model_class: :PageNode
  has_one :in, :page, type: :trait, model_class: :PageNode
  has_many :in, :inferred_pages, type: :inferred_trait, model_class: :PageNode
  has_one :out, :resource, type: :supplier, model_class: :ResourceNode
  has_many :out, :metadata, type: :metadata, model_class: :MetadataNode
  has_one :out, :contributor, type: :contributor, model_class: :TermNode
  has_one :out, :compiler, type: :compiler, model_class: :TermNode
  has_one :out, :determined_by, type: :determined_by, model_class: :TermNode

  alias :measurement_method :method # 'method' is a keyword, and thus can't be called with Trait#send(:method)

  PROP_METADATA_KEYS = %w(
    citation
    measurement_method
    remarks
    sample_size
    scientific_name
    source
  )

  REL_METADATA_KEYS = %w(
    contributor
    compiler
    determined_by
  )

  def grouped_metadata
    if !@grouped_metadata
      combined_metadata = {}
      regular_metadata = []

      metadata.each do |m|
        if (
          m.predicate &&
          TraitBank::Constants::GROUP_META_VALUE_URIS.include?(m.predicate.uri)
        )
          if combined_metadata.include?(m.predicate.uri)
            combined_metadata[m.predicate.uri].add(m)
          else
            combined_metadata[m.predicate.uri] = MetadataGroup.new(m)
          end
        else
          regular_metadata << MetadataGroup.new(m)
        end
      end

      @grouped_metadata = regular_metadata + combined_metadata.values
    end

    @grouped_metadata
  end

  def all_metadata_sorted
    (grouped_metadata + property_metadata + relationship_metadata).sort do |a, b|
      a.predicate.i18n_name <=> b.predicate.i18n_name
    end
  end

  def property_metadata
    PROP_METADATA_KEYS.map do |key|
      value = self.send(key)

      if value.present?
        GenericMetadatum.new(key, value, nil)
      else
        nil
      end
    end.compact
  end

  def relationship_metadata
    REL_METADATA_KEYS.map do |key|
      term = self.send(key)

      if term.present?
        GenericMetadatum.new(key, nil, term)
      else
        nil
      end
    end.compact
  end

  private
  class GenericMetadatum
    attr_reader :predicate, :object_term, :object_page, :measurement, :literal, :units_term

    def initialize(
      pred_alias,
      measurement,
      object_term
    )
      @predicate = TermNode.safe_find_by_alias(pred_alias)

      raise TypeError, "invalid Term alias" if @predicate.nil?

      @measurement = measurement
      @object_term = object_term
    end
  end

  class MetadataGroup
    attr_accessor :first
    delegate_missing_to :first

    def initialize(meta)
      @first = meta
      @measurements = []
      add(@first)
    end

    def add(meta)
      @measurements << meta.measurement if meta.measurement
    end

    def measurement
      @measurements.join(', ')
    end
  end
end
