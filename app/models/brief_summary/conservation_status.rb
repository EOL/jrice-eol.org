class BriefSummary
  class ConservationStatus
    IUCN_OBJS = Set[
      TermNode.safe_find_by_alias('iucn_en'),
      TermNode.safe_find_by_alias('iucn_cr'),
      TermNode.safe_find_by_alias('iucn_ew'),
      TermNode.safe_find_by_alias('iucn_nt'),
      TermNode.safe_find_by_alias('iucn_vu')
    ]

    def initialize(page)
      @page = page
    end

    def by_provider
      if @by_provider
        return @by_provider
      end

      @by_provider = {}
      traits = @page.traits_for_predicate(TermNode.safe_find_by_alias('conservation_status'))

      multiples_warned = Set.new

      traits.each do |trait|
        resource_id = trait.resource&.id

        next if resource_id.nil? || trait.object_term.nil? || trait.object_term.is_hidden_from_overview

        provider = case resource_id
                   when Resource.iucn&.id
                     :iucn
                   when Resource.cosewic&.id
                     :cosewic
                   when Resource.cites&.id
                     :cites
                   #when Resource.usfw&.id
                   #  :usfw
                   else
                     Rails.logger.warn("Unable to classify conservation status uri by resource id: #{resource_id}")
                     nil
                   end

        if provider
          if @by_provider.include?(provider) && !multiples_warned.include?(provider)
            Rails.logger.warn("Found multiple conservation status traits for page #{@page.id}/provider #{provider}")
            multiples_warned.add(provider)
          else
            if provider != :iucn || IUCN_OBJS.include?(trait.object_term)
              @by_provider[provider] = trait
            end
          end
        end
      end

      @by_provider
    end
  end
end
