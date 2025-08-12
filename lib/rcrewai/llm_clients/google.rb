# frozen_string_literal: true

require_relative 'base'

module RCrewAI
  module LLMClients
    class Google < Base
      BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = BASE_URL
      end

      def chat(messages:, **options)
        # Convert messages to Gemini format
        formatted_contents = format_messages(messages)
        
        payload = {
          contents: formatted_contents,
          generationConfig: {
            temperature: options[:temperature] || config.temperature,
            maxOutputTokens: options[:max_tokens] || config.max_tokens || 2048,
            topP: options[:top_p] || 0.8,
            topK: options[:top_k] || 10
          }
        }

        # Add safety settings if provided
        if options[:safety_settings]
          payload[:safetySettings] = options[:safety_settings]
        end

        # Add stop sequences if provided
        if options[:stop_sequences]
          payload[:generationConfig][:stopSequences] = options[:stop_sequences]
        end

        url = "#{@base_url}/models/#{config.model}:generateContent?key=#{config.api_key}"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers)
        log_response(response)

        result = handle_response(response)
        format_response(result)
      end

      def models
        # Google AI Studio doesn't provide a models list endpoint with API key auth
        # Return known Gemini models
        [
          'gemini-pro',
          'gemini-pro-vision',
          'gemini-1.5-pro',
          'gemini-1.5-flash',
          'text-bison-001',
          'chat-bison-001'
        ]
      end

      private

      def format_messages(messages)
        contents = []
        
        messages.each do |msg|
          role = case msg[:role]
                when 'user'
                  'user'
                when 'assistant'
                  'model'
                when 'system'
                  # Gemini doesn't have system role, prepend to first user message
                  next
                else
                  'user'
                end

          content = if msg.is_a?(Hash)
                     msg[:content]
                   else
                     msg.to_s
                   end

          contents << {
            role: role,
            parts: [{ text: content }]
          }
        end

        # Handle system message by prepending to first user message
        system_msg = messages.find { |m| m[:role] == 'system' }
        if system_msg && contents.any?
          first_user_content = contents.find { |c| c[:role] == 'user' }
          if first_user_content
            original_text = first_user_content[:parts].first[:text]
            first_user_content[:parts].first[:text] = "#{system_msg[:content]}\n\n#{original_text}"
          end
        end

        contents
      end

      def format_response(response)
        candidate = response.dig('candidates', 0)
        return nil unless candidate

        content = candidate.dig('content', 'parts', 0, 'text')
        finish_reason = candidate['finishReason']

        # Extract usage information if available
        usage_metadata = response['usageMetadata']
        usage = if usage_metadata
                  {
                    'prompt_tokens' => usage_metadata['promptTokenCount'],
                    'completion_tokens' => usage_metadata['candidatesTokenCount'],
                    'total_tokens' => usage_metadata['totalTokenCount']
                  }
                end

        {
          content: content,
          role: 'assistant',
          finish_reason: finish_reason,
          usage: usage,
          model: config.model,
          provider: :google
        }
      end

      def validate_config!
        super
        raise ConfigurationError, "Google API key is required" unless config.google_api_key || config.api_key
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
        when 403
          raise AuthenticationError, "API key does not have permission"
        when 429
          raise RateLimitError, "Rate limit exceeded or quota exhausted"
        when 500..599
          raise APIError, "Server error: #{response.status}"
        else
          raise APIError, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end