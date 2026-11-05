# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'base'
require_relative '../events'
require_relative '../sse_parser'
require_relative '../provider_schema'
require_relative '../pricing'
require_relative '../cancel_token'
require_relative '../persistent_http'

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

      def initialize(config = RCrewAI.configuration, **hooks)
        super(config, **hooks)
        @base_url = config.base_url || BASE_URL
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        system_message = extract_system_message(messages)
        non_system = messages.reject { |m| m.is_a?(Hash) && m[:role] == 'system' }

        payload = {
          model: options[:model] || config.model,
          messages: format_messages(non_system).map { |m| m.except(:tool_results) },
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
          stream_chat(payload, stream, cancel: options[:cancel])
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

      def provider_name
        :anthropic
      end

      private

      def plain_chat(payload)
        url = "#{@base_url}/messages"
        payload = apply_before_request(payload)
        started_at = Time.now
        log_request(:post, url, payload)
        response = http_client.post(url, payload, build_headers.merge(auth_header))
        log_response(response)
        body = handle_response(response)
        apply_after_response(normalize_non_streaming(body), started_at)
      end

      def stream_chat(payload, sink, cancel: nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
        url = "#{@base_url}/messages"
        payload = apply_before_request(payload)
        started_at = Time.now
        log_request(:post, url, payload)

        assembled_text = +''
        # tool_use blocks keyed by content-block index
        blocks = {}
        # Every content block as the API sent it, for replay in a tool loop
        raw_blocks = {}
        finish_reason = nil
        prompt_tokens = nil
        cached_tokens = nil
        completion_tokens = nil

        parser = SSEParser.new do |sse|
          data = JSON.parse(sse[:data])
          case data['type']
          when 'message_start'
            prompt_tokens = data.dig('message', 'usage', 'input_tokens')
            cached_tokens = data.dig('message', 'usage', 'cache_read_input_tokens')
          when 'content_block_start'
            cb = data['content_block'] || {}
            raw_blocks[data['index']] = cb.dup
            blocks[data['index']] = { id: cb['id'], name: cb['name'], arguments: +'' } if cb['type'] == 'tool_use'
          when 'content_block_delta'
            delta = data['delta'] || {}
            merge_raw_delta(raw_blocks[data['index']], delta)
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

        streaming_post(payload, cancel: cancel) { |chunk| parser.feed(chunk) }

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
          total_tokens: (prompt_tokens || 0) + (completion_tokens || 0),
          cached_tokens: cached_tokens
        }

        if prompt_tokens || completion_tokens
          sink.call(Events::Usage.new(
                      type: :usage, timestamp: Time.now, agent: nil, iteration: nil,
                      prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
                      total_tokens: usage[:total_tokens], cached_tokens: cached_tokens,
                      cost_usd: Pricing.cost_for(payload[:model],
                                                 prompt_tokens: prompt_tokens || 0,
                                                 completion_tokens: completion_tokens || 0)
                    ))
        end

        result = {
          content: assembled_text.empty? ? nil : assembled_text,
          tool_calls: tool_calls,
          raw_content: assemble_raw_blocks(raw_blocks, tool_calls),
          usage: usage,
          finish_reason: finish_reason || :stop,
          model: payload[:model],
          provider: :anthropic
        }
        apply_after_response(result, started_at)
      end

      # Streams over one kept-alive connection per client (see PersistentHTTP).
      def merge_raw_delta(block, delta)
        return unless block

        case delta['type']
        when 'text_delta' then block['text'] = "#{block['text']}#{delta['text']}"
        when 'thinking_delta' then block['thinking'] = "#{block['thinking']}#{delta['thinking']}"
        when 'signature_delta' then block['signature'] = "#{block['signature']}#{delta['signature']}"
        end
      end

      # Tool arguments arrive as JSON fragments, already parsed into tool_calls.
      def assemble_raw_blocks(raw_blocks, tool_calls)
        raw_blocks.sort.map do |_index, block|
          next block unless block['type'] == 'tool_use'

          call = tool_calls.find { |c| c[:id] == block['id'] }
          block.merge('input' => call ? call[:arguments] : {})
        end
      end

      def streaming_post(payload, cancel: nil, &on_chunk)
        uri = URI("#{@base_url}/messages")
        response = streaming_connection.post_stream(
          uri.request_uri, headers: build_headers.merge(auth_header), body: payload.to_json, cancel: cancel, &on_chunk
        )
        return response if response.is_a?(Net::HTTPSuccess)

        handle_response(Struct.new(:status, :body).new(response.code.to_i, response.body))
      end

      def streaming_connection
        @streaming_connection ||= PersistentHTTP.new(@base_url, timeout: config.timeout)
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
          raw_content: content_blocks,
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
        messages.each_with_object([]) do |msg, out|
          next out << { role: 'user', content: msg.to_s } unless msg.is_a?(Hash)

          case msg[:role].to_s
          when 'assistant' then out << { role: 'assistant', content: assistant_content(msg) }
          when 'tool' then append_tool_result(out, msg)
          else out << { role: 'user', content: msg[:content] }
          end
        end
      end

      # A tool loop must replay the model's blocks unchanged, including thinking.
      def assistant_content(msg)
        return msg[:raw_content] if msg[:raw_content]
        return msg[:content] if msg[:tool_calls].nil? || msg[:tool_calls].empty?

        text = msg[:content].to_s.empty? ? [] : [{ type: 'text', text: msg[:content] }]
        text + msg[:tool_calls].map do |call|
          { type: 'tool_use', id: call[:id], name: call[:name], input: call[:arguments] || {} }
        end
      end

      # Results from one turn belong together in a single user message.
      def append_tool_result(out, msg)
        block = { type: 'tool_result', tool_use_id: msg[:tool_call_id], content: msg[:content] }
        last = out.last
        if last && last[:tool_results]
          last[:content] << block
        else
          out << { role: 'user', content: [block], tool_results: true }
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
