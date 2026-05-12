# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'base'
require_relative '../events'
require_relative '../sse_parser'
require_relative '../provider_schema'
require_relative '../pricing'

module RCrewAI
  module LLMClients
    class Google < Base
      BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'

      FINISH_REASON_MAP = {
        'STOP' => :stop,
        'MAX_TOKENS' => :length,
        'SAFETY' => :stop,
        'RECITATION' => :stop
      }.freeze

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = BASE_URL
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        contents = format_messages(messages)
        payload = {
          contents: contents,
          generationConfig: {
            temperature: options[:temperature] || config.temperature,
            maxOutputTokens: options[:max_tokens] || config.max_tokens || 2048
          }.compact
        }
        payload[:generationConfig][:topP] = options[:top_p] if options[:top_p]
        payload[:generationConfig][:topK] = options[:top_k] if options[:top_k]
        payload[:generationConfig][:stopSequences] = options[:stop_sequences] if options[:stop_sequences]
        payload[:safetySettings] = options[:safety_settings] if options[:safety_settings]

        if tools && !tools.empty?
          payload[:tools] = [ProviderSchema.for_many(:google, tools)]
          # tool_choice: Google has toolConfig; left as default unless explicitly set
        end

        api_key = config.google_api_key || config.api_key
        if stream
          url = "#{@base_url}/models/#{config.model}:streamGenerateContent?alt=sse&key=#{api_key}"
          stream_chat(url, payload, stream)
        else
          url = "#{@base_url}/models/#{config.model}:generateContent?key=#{api_key}"
          plain_chat(url, payload)
        end
      end

      def supports_native_tools?(model: config.model) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      def models
        %w[gemini-pro gemini-1.5-pro gemini-1.5-flash gemini-pro-vision]
      end

      private

      def plain_chat(url, payload)
        log_request(:post, url, payload)
        response = http_client.post(url, payload, build_headers)
        log_response(response)
        body = handle_response(response)
        normalize_non_streaming(body)
      end

      def stream_chat(url, payload, sink)
        log_request(:post, url, payload)

        assembled_text = +''
        tool_calls = []
        finish_reason = nil
        usage = nil

        parser = SSEParser.new do |sse|
          data = JSON.parse(sse[:data])
          candidate = data.dig('candidates', 0) || {}
          parts = candidate.dig('content', 'parts') || []

          parts.each do |part|
            if part['text']
              text = part['text']
              assembled_text << text
              sink.call(Events::TextDelta.new(type: :text_delta, timestamp: Time.now,
                                              agent: nil, iteration: nil, text: text))
            elsif part['functionCall']
              fc = part['functionCall']
              tool_calls << { id: nil, name: fc['name'], arguments: fc['args'] || {} }
            end
          end

          finish_reason ||= FINISH_REASON_MAP[candidate['finishReason']]
          if data['usageMetadata']
            usage = {
              prompt_tokens: data.dig('usageMetadata', 'promptTokenCount'),
              completion_tokens: data.dig('usageMetadata', 'candidatesTokenCount'),
              total_tokens: data.dig('usageMetadata', 'totalTokenCount')
            }
          end
        end

        streaming_post(url, payload) { |chunk| parser.feed(chunk) }

        if usage
          sink.call(Events::Usage.new(
                      type: :usage, timestamp: Time.now, agent: nil, iteration: nil,
                      prompt_tokens: usage[:prompt_tokens],
                      completion_tokens: usage[:completion_tokens],
                      total_tokens: usage[:total_tokens],
                      cost_usd: Pricing.cost_for(config.model,
                                                 prompt_tokens: usage[:prompt_tokens] || 0,
                                                 completion_tokens: usage[:completion_tokens] || 0)
                    ))
        end

        finish_reason = :tool_calls if tool_calls.any?

        {
          content: assembled_text.empty? ? nil : assembled_text,
          tool_calls: tool_calls,
          usage: usage || {},
          finish_reason: finish_reason || :stop,
          model: config.model,
          provider: :google
        }
      end

      def streaming_post(url, payload, &on_chunk)
        conn = Faraday.new do |f|
          f.request :json
          f.options.timeout = config.timeout
          f.adapter Faraday.default_adapter
        end
        conn.post(url) do |req|
          req.headers = build_headers
          req.body = payload.to_json
          req.options.on_data = proc { |chunk, _| on_chunk.call(chunk) }
        end
      end

      def normalize_non_streaming(body)
        candidate = body.dig('candidates', 0) || {}
        parts = candidate.dig('content', 'parts') || []
        text = parts.select { |p| p['text'] }.map { |p| p['text'] }.join
        tool_calls = parts.select { |p| p['functionCall'] }.map do |p|
          { id: nil, name: p.dig('functionCall', 'name'), arguments: p.dig('functionCall', 'args') || {} }
        end
        usage_md = body['usageMetadata'] || {}
        finish_reason = tool_calls.any? ? :tool_calls : (FINISH_REASON_MAP[candidate['finishReason']] || :stop)

        {
          content: text.empty? ? nil : text,
          tool_calls: tool_calls,
          usage: {
            prompt_tokens: usage_md['promptTokenCount'],
            completion_tokens: usage_md['candidatesTokenCount'],
            total_tokens: usage_md['totalTokenCount']
          },
          finish_reason: finish_reason,
          model: config.model,
          provider: :google
        }
      end

      def format_messages(messages)
        contents = []
        system_msg = nil

        messages.each do |msg|
          case msg[:role]
          when 'system'
            system_msg = msg[:content]
            next
          when 'assistant'
            contents << { role: 'model', parts: [{ text: msg[:content].to_s }] }
          else
            contents << { role: 'user', parts: [{ text: msg[:content].to_s }] }
          end
        end

        if system_msg && (first_user = contents.find { |c| c[:role] == 'user' })
          first_user[:parts].first[:text] = "#{system_msg}\n\n#{first_user[:parts].first[:text]}"
        end

        contents
      end

      def validate_config!
        raise ConfigurationError, 'Google API key is required' unless config.google_api_key || config.api_key
        raise ConfigurationError, 'Model is required' unless config.model
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          details = response.body.is_a?(Hash) ? response.body.dig('error', 'message') : response.body
          raise APIError, "Bad request: #{details}"
        when 401
          raise AuthenticationError, 'Invalid API key'
        when 403
          raise AuthenticationError, 'API key does not have permission'
        when 429
          raise RateLimitError, 'Rate limit exceeded'
        when 500..599
          raise APIError, "Server error: #{response.status}"
        else
          raise APIError, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end
