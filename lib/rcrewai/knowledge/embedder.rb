# frozen_string_literal: true

require 'json'
require 'faraday'

module RCrewAI
  module Knowledge
    # Turns text into embedding vectors. Defaults to OpenAI's embeddings API;
    # #embed takes an array of strings and returns an array of vectors. Any
    # object responding to #embed can be substituted (see specs).
    class Embedder
      DEFAULT_MODEL = 'text-embedding-3-small'
      OPENAI_URL = 'https://api.openai.com/v1/embeddings'

      def initialize(model: DEFAULT_MODEL, api_key: nil, config: RCrewAI.configuration)
        @model = model
        @api_key = api_key || config.openai_api_key || config.api_key
      end

      def embed(texts)
        texts = Array(texts)
        return [] if texts.empty?

        response = connection.post(OPENAI_URL) do |req|
          req.headers['Authorization'] = "Bearer #{@api_key}"
          req.headers['Content-Type'] = 'application/json'
          req.body = JSON.generate(model: @model, input: texts)
        end

        raise EmbeddingError, "embedding request failed: #{response.status}" unless response.success?

        body = response.body
        body = JSON.parse(body) if body.is_a?(String)
        body['data'].map { |d| d['embedding'] }
      end

      private

      def connection
        @connection ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
        end
      end
    end

    class EmbeddingError < RCrewAI::Error; end
  end
end
