# frozen_string_literal: true

require_relative 'llm_clients/base'
require_relative 'llm_clients/openai'
require_relative 'llm_clients/anthropic'
require_relative 'llm_clients/google'
require_relative 'llm_clients/azure'
require_relative 'llm_clients/ollama'
require_relative 'llm_clients/openai_compatible'
require_relative 'llm_clients/bedrock'
require_relative 'llm_clients/snowflake_cortex'
require_relative 'llm_clients/openai_responses'

module RCrewAI
  class LLMClient
    PROVIDERS = {
      openai: LLMClients::OpenAI,
      anthropic: LLMClients::Anthropic,
      google: LLMClients::Google,
      azure: LLMClients::Azure,
      ollama: LLMClients::Ollama,
      openai_compatible: LLMClients::OpenAICompatible,
      bedrock: LLMClients::Bedrock,
      snowflake: LLMClients::SnowflakeCortex,
      openai_responses: LLMClients::OpenAIResponses
    }.freeze

    def self.for_provider(provider = nil, config = RCrewAI.configuration, **hooks)
      provider ||= config.llm_provider
      klass = PROVIDERS[provider.to_sym]
      raise ConfigurationError, "Unsupported provider: #{provider}" unless klass

      klass.new(config, **hooks)
    end

    # Resolves a per-agent / per-pass LLM spec into a client.
    #   nil            -> global provider
    #   Symbol/String  -> that provider, global model
    #   Hash           -> { provider:, model:, api_key:, temperature: } overrides
    #   client object  -> returned as-is (anything responding to #chat)
    def self.resolve(spec, config = RCrewAI.configuration)
      case spec
      when nil
        for_provider(nil, config)
      when Symbol, String
        overridden = config.with_overrides(provider: spec)
        for_provider(overridden.llm_provider, overridden)
      when Hash
        overridden = config.with_overrides(**spec)
        for_provider(overridden.llm_provider, overridden)
      else
        return spec if spec.respond_to?(:chat)

        raise ConfigurationError,
              "Invalid llm: expected a provider symbol, an options hash, or a client responding to #chat, got #{spec.class}"
      end
    end

    def self.chat(messages:, **options)
      client = for_provider
      client.chat(messages: messages, **options)
    end

    def self.complete(prompt:, **options)
      client = for_provider
      client.complete(prompt: prompt, **options)
    end
  end
end
