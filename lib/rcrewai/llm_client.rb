# frozen_string_literal: true

require_relative 'llm_clients/base'
require_relative 'llm_clients/openai'
require_relative 'llm_clients/anthropic'
require_relative 'llm_clients/google'
require_relative 'llm_clients/azure'
require_relative 'llm_clients/ollama'

module RCrewAI
  class LLMClient
    def self.for_provider(provider = nil, config = RCrewAI.configuration)
      provider ||= config.llm_provider

      case provider.to_sym
      when :openai
        LLMClients::OpenAI.new(config)
      when :anthropic
        LLMClients::Anthropic.new(config)
      when :google
        LLMClients::Google.new(config)
      when :azure
        LLMClients::Azure.new(config)
      when :ollama
        LLMClients::Ollama.new(config)
      else
        raise ConfigurationError, "Unsupported provider: #{provider}"
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