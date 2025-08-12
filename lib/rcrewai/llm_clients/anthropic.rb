# frozen_string_literal: true

require_relative 'base'

module RCrewAI
  module LLMClients
    class Anthropic < Base
      BASE_URL = 'https://api.anthropic.com/v1'
      API_VERSION = '2023-06-01'

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = BASE_URL
      end

      def chat(messages:, **options)
        # Convert messages to Anthropic format
        system_message = extract_system_message(messages)
        formatted_messages = format_messages(messages.reject { |m| m.is_a?(Hash) && m[:role] == 'system' })

        payload = {
          model: config.model,
          messages: formatted_messages,
          max_tokens: options[:max_tokens] || config.max_tokens || 1000,
          temperature: options[:temperature] || config.temperature
        }

        payload[:system] = system_message if system_message

        # Add Anthropic-specific options
        payload[:top_p] = options[:top_p] if options[:top_p]
        payload[:top_k] = options[:top_k] if options[:top_k]
        payload[:stop_sequences] = options[:stop_sequences] if options[:stop_sequences]

        url = "#{@base_url}/messages"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers.merge(authorization_header))
        log_response(response)

        result = handle_response(response)
        format_response(result)
      end

      def models
        # Anthropic doesn't have a models endpoint, return known models
        [
          'claude-3-opus-20240229',
          'claude-3-sonnet-20240229',
          'claude-3-haiku-20240307',
          'claude-2.1',
          'claude-2.0',
          'claude-instant-1.2'
        ]
      end

      private

      def authorization_header
        {
          'Authorization' => "Bearer #{config.api_key}",
          'anthropic-version' => API_VERSION
        }
      end

      def extract_system_message(messages)
        return nil unless messages.is_a?(Array)
        system_msg = messages.find { |m| m.is_a?(Hash) && m[:role] == 'system' }
        system_msg&.dig(:content)
      end

      def format_messages(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            {
              role: msg[:role] == 'assistant' ? 'assistant' : 'user',
              content: msg[:content]
            }
          else
            { role: 'user', content: msg.to_s }
          end
        end
      end

      def format_response(response)
        content = response.dig('content', 0, 'text') if response['content']&.any?

        {
          content: content,
          role: 'assistant',
          finish_reason: response['stop_reason'],
          usage: {
            'prompt_tokens' => response.dig('usage', 'input_tokens'),
            'completion_tokens' => response.dig('usage', 'output_tokens'),
            'total_tokens' => (response.dig('usage', 'input_tokens') || 0) + 
                             (response.dig('usage', 'output_tokens') || 0)
          },
          model: response['model'],
          provider: :anthropic
        }
      end

      def validate_config!
        raise ConfigurationError, "Anthropic API key is required" unless config.anthropic_api_key || config.api_key
        raise ConfigurationError, "Model is required" unless config.model
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          error_details = response.body.dig('error', 'message') || response.body
          raise APIError, "Bad request: #{error_details}"
        when 401
          raise AuthenticationError, "Invalid API key"
        when 429
          raise RateLimitError, "Rate limit exceeded"
        when 500..599
          raise APIError, "Server error: #{response.status}"
        else
          raise APIError, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end