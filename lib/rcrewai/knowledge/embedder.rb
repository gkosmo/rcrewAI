# frozen_string_literal: true

require 'json'
require 'faraday'

module RCrewAI
  module Knowledge
    # Turns text into embedding vectors. Supports multiple providers
    # (OpenAI [default], Azure OpenAI, Google Gemini, Ollama); Anthropic has no
    # first-party embeddings API and raises a clear error. `#embed` takes an
    # array of strings and returns an array of vectors. Any object responding to
    # `#embed` can be substituted.
    class Embedder
      DEFAULT_MODELS = {
        openai: 'text-embedding-3-small',
        azure: 'text-embedding-3-small',
        google: 'text-embedding-004',
        ollama: 'nomic-embed-text'
      }.freeze

      OPENAI_URL = 'https://api.openai.com/v1/embeddings'
      GOOGLE_BASE = 'https://generativelanguage.googleapis.com/v1beta'
      OLLAMA_DEFAULT_URL = 'http://localhost:11434'

      attr_reader :provider, :model

      def initialize(provider: :openai, model: nil, api_key: nil, config: RCrewAI.configuration)
        @provider = provider.to_sym
        if @provider == :anthropic
          raise EmbeddingError,
                'anthropic does not provide an embeddings API; use :openai, :azure, :google, or :ollama'
        end

        @config = config
        @model = model || DEFAULT_MODELS[@provider] || DEFAULT_MODELS[:openai]
        @api_key = api_key
      end

      def embed(texts)
        texts = Array(texts)
        return [] if texts.empty?

        send("embed_#{@provider}", texts)
      end

      private

      def embed_openai(texts)
        body = post_json(OPENAI_URL, { model: @model, input: texts },
                         'Authorization' => "Bearer #{api_key_for(:openai)}")
        body['data'].map { |d| d['embedding'] }
      end

      def embed_azure(texts)
        base = @config.base_url
        version = @config.api_version || '2024-02-01'
        deployment = @config.deployment_name || @model
        url = "#{base}/openai/deployments/#{deployment}/embeddings?api-version=#{version}"
        body = post_json(url, { input: texts }, 'api-key' => api_key_for(:azure))
        body['data'].map { |d| d['embedding'] }
      end

      def embed_google(texts)
        key = api_key_for(:google)
        texts.map do |text|
          url = "#{GOOGLE_BASE}/models/#{@model}:embedContent?key=#{key}"
          payload = { model: "models/#{@model}", content: { parts: [{ text: text }] } }
          body = post_json(url, payload)
          body.dig('embedding', 'values')
        end
      end

      def embed_ollama(texts)
        base = @config.base_url || OLLAMA_DEFAULT_URL
        texts.map do |text|
          body = post_json("#{base}/api/embeddings", { model: @model, prompt: text })
          body['embedding']
        end
      end

      def post_json(url, payload, headers = {})
        response = connection.post(url) do |req|
          req.headers['Content-Type'] = 'application/json'
          headers.each { |k, v| req.headers[k] = v }
          req.body = JSON.generate(payload)
        end
        raise EmbeddingError, "embedding request failed: #{response.status}" unless response.success?

        body = response.body
        body.is_a?(String) ? JSON.parse(body) : body
      end

      def api_key_for(provider)
        return @api_key if @api_key

        case provider
        when :openai then @config.openai_api_key || @config.api_key
        when :azure  then @config.azure_api_key || @config.api_key
        when :google then @config.google_api_key || @config.api_key
        end
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
        end
      end
    end

    class EmbeddingError < RCrewAI::Error; end
  end
end
