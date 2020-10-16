class TermsController < ApplicationController
  before_action :require_admin, only: [:update]

  SCHEMA_URI_FORMAT = "http://eol.org/schema/terms/%s"
  META_OBJECT_URIS = {
    sex: [
      "http://purl.obolibrary.org/obo/PATO_0000383",
      "http://purl.obolibrary.org/obo/PATO_0000384",
      "http://purl.obolibrary.org/obo/PATO_0001340"
    ],
    lifestage: [
      "http://www.ebi.ac.uk/efo/EFO_0001272",
      "http://purl.obolibrary.org/obo/PATO_0001501",
      "http://purl.obolibrary.org/obo/PO_0007134",
      "http://purl.obolibrary.org/obo/PO_0025340"
    ],
    stat_meth: [
      "http://eol.org/schema/terms/average",
      "http://semanticscience.org/resource/SIO_001113",
      "http://semanticscience.org/resource/SIO_001114",
      "http://www.ebi.ac.uk/efo/EFO_0001444"
    ]
  }

  def index
    @uri = params[:uri]
    glossary_for_letter(params[:letter])
  end

#  def show
#    redirect_to_glossary_entry(params[:uri])
#  end

  def schema_redirect
    redirect_to_glossary_entry(SCHEMA_URI_FORMAT % params[:uri_part])
  end

  def edit
    @term = TraitBank::Term.term_as_hash(params[:uri])
  end

  def update
    term = params[:term].merge(uri: params[:uri])
    TraitBank::Term.update(term)
    redirect_to(term_path(term[:uri]))
  end

  def predicate_glossary
    glossary(params[:action], count_method: :predicate_glossary_count)
  end

  # We ultimately don't want to just pass a "URI" to the term search; we need to
  # separate object terms and predicates. We handle that here, since there are
  # two places where it matters.
  def add_uri_to_options(options)
    if @object
      options[:predicate] = @and_predicate && @and_predicate[:uri]
      options[:object_term] = @and_object ?
        [@term[:uri], @and_object[:uri]] :
        @term[:uri]
    else
      options[:predicate] = @and_predicate ?
        [@term[:uri], @and_predicate[:uri]] :
        @term[:uri]
      options[:object_term] = @and_object && @and_object[:uri]
    end
  end

  def object_terms_for_pred
    pred = params[:pred_uri]
    q = params[:query]
    res = TraitBank::Term.obj_terms_for_pred(pred, q) # NOTE: this is already cached by the class. ...is that wise?
    render :json => res
  end

  def meta_object_terms
    pred = params[:pred]
    uris = META_OBJECT_URIS[pred.to_sym] || []
    res = uris.map do |uri|
      {
        name: TraitBank::Term.name_for_uri(uri),
        uri: uri
      }
    end
    render json: res
  end

  def object_term_glossary
    glossary(params[:action], count_method: :object_term_glossary_count)
  end

  def units_glossary
    glossary(params[:action], count_method: :units_glossary_count)
  end

  def pred_autocomplete
    q = params[:query]
    res = Rails.cache.fetch("pred_autocomplete/#{q}") { TraitBank::Term.predicate_glossary(nil, nil, qterm: q) }
    render :json => res
  end

  def trait_search_predicates
    @query = params[:query]

    if @query.blank?
      render json: TraitBank::Term.top_level(:predicate)
    else
      glossary(:predicate_glossary, count_method: :predicate_glossary_count)
    end
  end


private

  def terms_to_array(terms)
    terms.collect do |term|
      [term[:name], term[:uri]]
    end
  end

  def glossary(which, options = nil)
    @count = TraitBank::Term.send(options[:count_method] || :count)

    respond_to do |fmt|
      fmt.html do
        @glossary = glossary_helper(which, @count, true)
      end
      fmt.json do
        render json: glossary_helper(which, @count, false)
      end
    end
  end

  def glossary_helper(which, count, paginate)
    @per_page = params[:per_page] || Rails.configuration.data_glossary_page_size
    @page = params[:page] || 1
    query = params[:query]
    @per_page = 10 if !paginate
    if params[:reindex] && is_admin?
      TraitBank::Admin.clear_caches
      expire_trait_fragments
    end
    result = TraitBank::Term.send(which, @page, @per_page, qterm: query, for_select: !paginate)
    Rails.logger.warn "GLOSSARY RESULTS: (for select: #{!paginate}) #{result.map { |r| r[:name] }.join(', ')}"
    paginate ? Kaminari.paginate_array(result, total_count: count).page(@page).per(@per_page) : result[0..@per_page+1]
  end

  def glossary_for_letter(letter)
    @letter = letter
    @letters = TraitBank::Term.letters_for_glossary
    @glossary = @letter ?
      TraitBank::Term.glossary_for_letter(@letter) :
      []
  end

  def expire_trait_fragments
    (0..100).each do |index|
      expire_fragment("term/glossary/#{index}")
    end
  end

  def redirect_to_glossary_entry(uri)
    term = TraitBank::Term.term_as_hash(uri)
    raise ActionController.RoutingError.new("Not Found") if !term
    first_letter = TraitBank::Term.letter_for_term(term)
    redirect_to terms_path(letter: first_letter, uri: term[:uri]), status: 302
  end
end
