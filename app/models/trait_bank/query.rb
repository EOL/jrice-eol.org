class TraitBank
  class Query
    include ActiveModel::Model

    NUM_PAIRS = 4

    attr_accessor :pairs

    def pairs_attributes=(attributes)
      @pairs ||= []

      attributes.each do |i, pair_params|
        @pairs.push(Pair.new(pair_params)) if pair_params[:predicate] && !pair_params[:predicate].blank?
      end
    end

    def fill_out_pairs!
      @pairs ||= []

      @pairs.push(Pair.new) while @pairs.length < NUM_PAIRS
    end

    class Pair
      include ActiveModel::Model

      attr_accessor :predicate
      attr_accessor :object
    end
  end
end
