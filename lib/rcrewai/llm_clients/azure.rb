# frozen_string_literal: true

require_relative 'openai'

module RCrewAI
  module LLMClients
    # Azure OpenAI: same wire format as OpenAI but routes through a deployment
    # path with an api-version query param, and authenticates with an api-key
    # header instead of Authorization: Bearer.
    class Azure < OpenAI
      def initialize(config = RCrewAI.configuration)
        super
        @api_version = config.api_version || '2024-02-01'
        @deployment_name = config.deployment_name || config.model
        @base_url = build_endpoint_url
      end

      def models
        url = "#{@base_url}/openai/deployments?api-version=#{@api_version}"
        response = http_client.get(url, {}, build_headers.merge(auth_header))
        result = handle_response(response)
        Array(result['data']).map { |d| d['id'] }
      rescue StandardError
        [@deployment_name].compact
      end

      private

      def chat_url
        "#{@base_url}/openai/deployments/#{@deployment_name}/chat/completions?api-version=#{@api_version}"
      end

      def build_endpoint_url
        endpoint = config.base_url || ENV['AZURE_OPENAI_ENDPOINT'] || ENV['AZURE_ENDPOINT']
        endpoint&.chomp('/')
      end

      def provider_name
        :azure
      end

      def auth_header
        { 'api-key' => config.azure_api_key || config.api_key }
      end

      def validate_config!
        raise ConfigurationError, 'Azure API key is required' unless config.azure_api_key || config.api_key
        raise ConfigurationError, 'Azure endpoint is required' unless config.base_url || ENV['AZURE_OPENAI_ENDPOINT'] || ENV['AZURE_ENDPOINT']
        raise ConfigurationError, 'Azure deployment name is required' unless config.deployment_name || config.model
      end
    end
  end
end
