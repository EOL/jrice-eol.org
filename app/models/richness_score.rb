class RichnessScore
  def self.calculate(page)
    self.new(page).calculate
  end

  def self.explain(page)
    self.new(page).explain
  end

  def initialize(page)
    @page = page
    @section_count = Section.count
    @section_count = 1 if @section_count.nil? || @section_count <= 0
    @glossary_count = TraitBank.glossary_count
    @weights = {
      media: 0.34,
      media_diversity: 0.03,
      map: 0.1,
      section_diversity: 0.25,
      data_diversity: 0.25,
      references: 0.03
    }
    @scores = {}
  end

  def calculate
    score_media
    score_media_diversity
    score_map
    score_section_diversity
    score_data_diversity
    score_references
    @scores.values.inject(0, &:+ ).round(2)
  end

  def score_media
    @scores[:media] = weighted_score(@page.media_count) * @weights[:media]
  end

  def score_media_diversity
    @scores[:media_diversity] = media_diversity_score ? @weights[:media_diversity] : 0
  end

  def score_map
    @scores[:map] = @page.map? ? @weights[:map] : 0
  end

  def score_section_diversity
    @scores[:section_diversity] = section_diversity_score * @weights[:section_diversity]
  end

  # NOTE: no one will *ever* have all of the predicates! :|
  def score_data_diversity
    @scores[:data_diversity] = data_diversity_score * @weights[:data_diversity]
  end

  def score_references
    @scores[:references] = weighted_score(@page.literature_and_references_count) * @weights[:references]
  end

  def explain
    total = calculate
    "Media: #{@page.media_count} -> #{weighted_score(@page.media_count)} * #{@weights[:media]} = #{@scores[:media]}\n"\
    "Media Diversity: #{content_types_count} -> #{media_diversity_score} * #{@weights[:media_diversity]} = #{@scores[:media_diversity]}\n"\
    "Map: #{@page.map?} -> #{@weights[:map]} = #{@scores[:map]}\n"\
    "Section Diversity: #{@page.sections.size} / #{@section_count} -> #{section_diversity_score} * #{@weights[:section_diversity]} = #{@scores[:section_diversity]}\n"\
    "Data Diversity: #{@page.glossary.size} / #{@glossary_count} -> #{data_diversity_score} * #{@weights[:data_diversity]} = #{@scores[:data_diversity]}\n"\
    "References: #{@page.literature_and_references_count} -> #{weighted_score(@page.literature_and_references_count)} * #{@weights[:references]} = #{@scores[:references]}\n"\
    "TOTAL: #{total}"
  end

  # Scores about 0.2 for the first instance, less for each subsequent instance,
  # up to a ceiling of 10,000 instances, which will return 1.
  def weighted_score(n)
    # 1 million =~ 13.8
    return 0 if n <= 0
    return 1 if n >= 10_000 # That's enough!
    # NOTE: 0.19 is there to "boost" the value of the first image; the 5 is hard
    # coded as a value N where Math.log10(10_000.1) / N = 0.81 (or so). As our
    # content folks said when confronted with this, "a couple of constants are
    # to be expected in a custom curve."
    return (Math.log10(n + 0.1) / 5 + 0.19).round(2)
  end

  def media_diversity_score
    content_types_count > 1 ? 1 : 0
  end

  def content_types_count
    @page.page_contents.map(&:content_type).uniq.size
  end

  def section_diversity_score
    (@page.sections.size.to_f / @section_count)
  end

  def data_diversity_score
    (@page.glossary.size.to_f / @glossary_count)
  end
end
