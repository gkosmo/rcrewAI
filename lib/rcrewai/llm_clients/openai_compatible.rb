# frozen_string_literal: true

require_relative 'openai'

module RCrewAI
  module LLMClients
    # Any endpoint speaking the OpenAI Chat Completions wire format: Together,
    # Groq, Fireworks, vLLM, LiteLLM, OpenRouter, a self-hosted gateway. Only
    # the base URL differs, so this is OpenAI with the endpoint made explicit
    # and required.
    class OpenAICompatible < OpenAI
      def initialize(config = RCrewAI.configuration, **hooks)
        super
        @base_url = config.base_url.chomp('/')
      end

      def provider_name
        :openai_compatible
      end

      private

      def validate_config!
        raise ConfigurationError, 'API key is required' unless config.api_key
        raise ConfigurationError, 'A base url is required for an OpenAI-compatible provider' unless config.base_url
        raise ConfigurationError, 'Model is required' unless config.model
      end

      def auth_header
        { 'Authorization' => "Bearer #{config.api_key}" }
      end
    end
  end
end
