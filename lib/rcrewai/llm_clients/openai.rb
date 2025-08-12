# frozen_string_literal: true

require_relative 'base'

module RCrewAI
  module LLMClients
    class OpenAI < Base
      BASE_URL = 'https://api.openai.com/v1'

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = BASE_URL
      end

      def chat(messages:, **options)
        payload = {
          model: config.model,
          messages: format_messages(messages),
          temperature: options[:temperature] || config.temperature,
          max_tokens: options[:max_tokens] || config.max_tokens
        }

        # Add additional OpenAI-specific options
        payload[:top_p] = options[:top_p] if options[:top_p]
        payload[:frequency_penalty] = options[:frequency_penalty] if options[:frequency_penalty]
        payload[:presence_penalty] = options[:presence_penalty] if options[:presence_penalty]
        payload[:stop] = options[:stop] if options[:stop]

        url = "#{@base_url}/chat/completions"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers.merge(authorization_header))
        log_response(response)

        result = handle_response(response)
        format_response(result)
      end

      def complete(prompt:, **options)
        # For older models that use completions endpoint
        if config.model.include?('davinci') || config.model.include?('curie') || 
           config.model.include?('babbage') || config.model.include?('ada')
          completion_request(prompt, **options)
        else
          # Use chat endpoint for newer models
          super
        end
      end

      def models
        url = "#{@base_url}/models"
        response = http_client.get(url, {}, build_headers.merge(authorization_header))
        result = handle_response(response)
        result['data'].map { |model| model['id'] }
      end

      private

      def authorization_header
        { 'Authorization' => "Bearer #{config.api_key}" }
      end

      def completion_request(prompt, **options)
        payload = {
          model: config.model,
          prompt: prompt,
          temperature: options[:temperature] || config.temperature,
          max_tokens: options[:max_tokens] || config.max_tokens
        }

        url = "#{@base_url}/completions"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers.merge(authorization_header))
        log_response(response)

        result = handle_response(response)
        format_completion_response(result)
      end

      def format_messages(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            msg
          else
            { role: 'user', content: msg.to_s }
          end
        end
      end

      def format_response(response)
        choice = response.dig('choices', 0)
        return nil unless choice

        {
          content: choice.dig('message', 'content'),
          role: choice.dig('message', 'role'),
          finish_reason: choice['finish_reason'],
          usage: response['usage'],
          model: response['model'],
          provider: :openai
        }
      end

      def format_completion_response(response)
        choice = response.dig('choices', 0)
        return nil unless choice

        {
          content: choice['text'],
          finish_reason: choice['finish_reason'],
          usage: response['usage'],
          model: response['model'],
          provider: :openai
        }
      end

      def validate_config!
        raise ConfigurationError, "OpenAI API key is required" unless config.openai_api_key || config.api_key
        raise ConfigurationError, "Model is required" unless config.model
      end
    end
  end
end