class ApiReconciliationController < ApplicationController
  skip_before_action :verify_authenticity_token

  DATA_DIR = Rails.application.root.join('config', 'api_reconciliation')
  QUERY_SCHEMA_PATH = DATA_DIR.join('query_schema.json')
  QUERY_SCHEMA = JSONSchemer.schema(QUERY_SCHEMA_PATH)

  def index
    if params[:queries]
      reconcile(JSON.parse(params[:queries]))
    elsif params[:extend]
      get_properties(JSON.parse(params[:extend]))
    else
      manifest
    end
  end

  def suggest_properties
    prefix = (params[:prefix] || '').downcase
    cursor = params[:cursor] || 0

    matches = Reconciliation::PropertyType::ALL.select do |prop|
      prop.id.starts_with?(prefix) || prop.name.starts_with?(prefix)
    end

    @result = matches[cursor..] || []
    render formats: :json
  end

  def test
    @sample_query = {
      q1: {
        query: 'northern raccoon',
        properties: [
          {
            pid: 'ancestor',
            v: [
              { id: "pages/1642", name: "Mammalia" },  
              "carnivores"
            ]
          },
          {
            pid: 'rank',
            v: 'species'
          }
        ]
      }
    }
  end

  def test_extend
    @sample_query = {
      ids: ['pages/328598'],
      properties: [
        { id: 'rank' },
        { id: 'ancestor' }
      ]
    }
  end

  private
  # GET "/" -- service manifest 
  def manifest
    @types = Reconciliation::Result::MANIFEST_TYPES
    render :index, formats: :json
  end

  # GET "/?queries=...", POST "/" 
  def reconcile(qs)
    unless QUERY_SCHEMA.valid?(qs)
      first_error = QUERY_SCHEMA.validate(qs).next
      return bad_request("Invalid attribute or value: #{first_error["pointer"]}")
    end

    render json: Reconciliation::Result.new(qs).to_h
  end

  def bad_request(msg)
    render json: { error: msg }, status: :bad_request
  end

  def get_properties(json)
    query = nil

    begin
      query = Reconciliation::DataExtensionQuery.new(json)
      meta = query.properties.map(&:to_h)
      rows = Reconciliation::DataExtensionResult.new(query).to_h

      render json: {
        meta: meta,
        rows: rows
      }
    rescue ArgumentError, TypeError => e
      return bad_request(e.message)
    end
  end
end

