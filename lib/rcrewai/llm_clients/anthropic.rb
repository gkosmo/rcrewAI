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
    class Anthropic < Base
      BASE_URL = 'https://api.anthropic.com/v1'
      API_VERSION = '2023-06-01'

      STOP_REASON_MAP = {
        'tool_use' => :tool_calls,
        'end_turn' => :stop,
        'stop_sequence' => :stop,
        'max_tokens' => :length
      }.freeze

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = BASE_URL
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        system_message = extract_system_message(messages)
        non_system = messages.reject { |m| m.is_a?(Hash) && m[:role] == 'system' }

        payload = {
          model: config.model,
          messages: format_messages(non_system),
          max_tokens: options[:max_tokens] || config.max_tokens || 1000,
          temperature: options[:temperature] || config.temperature
        }.compact

        if system_message
          payload[:system] = if options[:cache_system]
                               [{ type: 'text', text: system_message,
                                  cache_control: { type: 'ephemeral' } }]
                             else
                               system_message
                             end
        end

        if tools && !tools.empty?
          payload[:tools] = ProviderSchema.for_many(:anthropic, tools)
          payload[:tool_choice] = { type: tool_choice.to_s } if tool_choice != :auto && tool_choice.is_a?(Symbol)
        end

        payload[:top_p] = options[:top_p] if options[:top_p]
        payload[:top_k] = options[:top_k] if options[:top_k]
        payload[:stop_sequences] = options[:stop_sequences] if options[:stop_sequences]

        if stream
          payload[:stream] = true
          stream_chat(payload, stream)
        else
          plain_chat(payload)
        end
      end

      def supports_native_tools?(model: config.model) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      def models
        %w[
          claude-opus-4-7 claude-sonnet-4-6 claude-haiku-4-5
          claude-3-5-sonnet-20241022 claude-3-haiku-20240307
        ]
      end

      private

      def plain_chat(payload)
        url = "#{@base_url}/messages"
        log_request(:post, url, payload)
        response = http_client.post(url, payload, build_headers.merge(auth_header))
        log_response(response)
        body = handle_response(response)
        normalize_non_streaming(body)
      end

      def stream_chat(payload, sink)
        url = "#{@base_url}/messages"
        log_request(:post, url, payload)

        assembled_text = +''
        # tool_use blocks keyed by content-block index
        blocks = {}
        finish_reason = nil
        prompt_tokens = nil
        completion_tokens = nil

        parser = SSEParser.new do |sse|
          data = JSON.parse(sse[:data])
          case data['type']
          when 'message_start'
            prompt_tokens = data.dig('message', 'usage', 'input_tokens')
          when 'content_block_start'
            cb = data['content_block'] || {}
            if cb['type'] == 'tool_use'
              blocks[data['index']] = { id: cb['id'], name: cb['name'], arguments: +'' }
            end
          when 'content_block_delta'
            delta = data['delta'] || {}
            case delta['type']
            when 'text_delta'
              text = delta['text'].to_s
              assembled_text << text
              sink.call(Events::TextDelta.new(type: :text_delta, timestamp: Time.now,
                                              agent: nil, iteration: nil, text: text))
            when 'input_json_delta'
              block = blocks[data['index']]
              block[:arguments] << delta['partial_json'].to_s if block
            end
          when 'message_delta'
            finish_reason ||= STOP_REASON_MAP[data.dig('delta', 'stop_reason')] ||
                              data.dig('delta', 'stop_reason')&.to_sym
            completion_tokens = data.dig('usage', 'output_tokens') || completion_tokens
          end
        end

        streaming_post(url, payload) { |chunk| parser.feed(chunk) }

        tool_calls = blocks.values.map do |b|
          {
            id: b[:id],
            name: b[:name],
            arguments: b[:arguments].empty? ? {} : JSON.parse(b[:arguments])
          }
        end

        usage = {
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: (prompt_tokens || 0) + (completion_tokens || 0)
        }

        if prompt_tokens || completion_tokens
          sink.call(Events::Usage.new(
                      type: :usage, timestamp: Time.now, agent: nil, iteration: nil,
                      prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
                      total_tokens: usage[:total_tokens],
                      cost_usd: Pricing.cost_for(config.model,
                                                 prompt_tokens: prompt_tokens || 0,
                                                 completion_tokens: completion_tokens || 0)
                    ))
        end

        {
          content: assembled_text.empty? ? nil : assembled_text,
          tool_calls: tool_calls,
          usage: usage,
          finish_reason: finish_reason || :stop,
          model: config.model,
          provider: :anthropic
        }
      end

      def streaming_post(url, payload, &on_chunk)
        conn = Faraday.new do |f|
          f.request :json
          f.options.timeout = config.timeout
          f.adapter Faraday.default_adapter
        end
        conn.post(url) do |req|
          req.headers = build_headers.merge(auth_header)
          req.body = payload.to_json
          req.options.on_data = proc { |chunk, _| on_chunk.call(chunk) }
        end
      end

      def normalize_non_streaming(body)
        content_blocks = Array(body['content'])
        text = content_blocks.select { |b| b['type'] == 'text' }.map { |b| b['text'] }.join
        tool_calls = content_blocks.select { |b| b['type'] == 'tool_use' }.map do |b|
          { id: b['id'], name: b['name'], arguments: b['input'] || {} }
        end
        prompt_tokens = body.dig('usage', 'input_tokens')
        completion_tokens = body.dig('usage', 'output_tokens')

        {
          content: text.empty? ? nil : text,
          tool_calls: tool_calls,
          usage: {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: (prompt_tokens || 0) + (completion_tokens || 0)
          },
          finish_reason: STOP_REASON_MAP[body['stop_reason']] || body['stop_reason']&.to_sym || :stop,
          model: body['model'] || config.model,
          provider: :anthropic
        }
      end

      def auth_header
        {
          'x-api-key' => config.anthropic_api_key || config.api_key,
          'anthropic-version' => API_VERSION
        }
      end

      def extract_system_message(messages)
        return nil unless messages.is_a?(Array)

        msg = messages.find { |m| m.is_a?(Hash) && m[:role] == 'system' }
        msg&.dig(:content)
      end

      def format_messages(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            { role: msg[:role] == 'assistant' ? 'assistant' : 'user', content: msg[:content] }
          else
            { role: 'user', content: msg.to_s }
          end
        end
      end

      def validate_config!
        raise ConfigurationError, 'Anthropic API key is required' unless config.anthropic_api_key || config.api_key
        raise ConfigurationError, 'Model is required' unless config.model
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          error_details = response.body.is_a?(Hash) ? response.body.dig('error', 'message') : response.body
          raise APIError, "Bad request: #{error_details}"
        when 401
          raise AuthenticationError, 'Invalid API key'
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
