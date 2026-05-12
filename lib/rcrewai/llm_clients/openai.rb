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
    class OpenAI < Base
      BASE_URL = 'https://api.openai.com/v1'

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = BASE_URL
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        payload = {
          model: config.model,
          messages: messages,
          temperature: options[:temperature] || config.temperature,
          max_tokens: options[:max_tokens] || config.max_tokens
        }.compact

        payload[:top_p] = options[:top_p] if options[:top_p]
        payload[:frequency_penalty] = options[:frequency_penalty] if options[:frequency_penalty]
        payload[:presence_penalty] = options[:presence_penalty] if options[:presence_penalty]
        payload[:stop] = options[:stop] if options[:stop]

        if tools && !tools.empty?
          payload[:tools] = ProviderSchema.for_many(:openai, tools)
          payload[:tool_choice] = tool_choice if tool_choice != :auto
        end

        if stream
          payload[:stream] = true
          payload[:stream_options] = { include_usage: true }
          stream_chat(payload, stream)
        else
          plain_chat(payload)
        end
      end

      def supports_native_tools?(model: config.model) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      def models
        url = "#{@base_url}/models"
        response = http_client.get(url, {}, build_headers.merge(auth_header))
        result = handle_response(response)
        result['data'].map { |model| model['id'] }
      end

      private

      def chat_url
        "#{@base_url}/chat/completions"
      end

      def plain_chat(payload)
        url = chat_url
        log_request(:post, url, payload)
        response = http_client.post(url, payload, build_headers.merge(auth_header))
        log_response(response)
        body = handle_response(response)
        normalize_non_streaming(body)
      end

      def stream_chat(payload, sink)
        url = chat_url
        log_request(:post, url, payload)

        assembled_text = +''
        tool_calls_by_index = {}
        final_usage = nil
        finish_reason = nil

        parser = SSEParser.new do |sse|
          data_str = sse[:data]
          next if data_str == '[DONE]'

          data = JSON.parse(data_str)
          choice = data.dig('choices', 0) || {}
          delta = choice['delta'] || {}

          if delta['content']
            assembled_text << delta['content']
            sink.call(Events::TextDelta.new(
                        type: :text_delta, timestamp: Time.now, agent: nil, iteration: nil,
                        text: delta['content']
                      ))
          end

          Array(delta['tool_calls']).each do |tc|
            idx = tc['index']
            tool_calls_by_index[idx] ||= { id: nil, name: nil, arguments: +'' }
            tool_calls_by_index[idx][:id]   ||= tc['id']
            tool_calls_by_index[idx][:name] ||= tc.dig('function', 'name')
            tool_calls_by_index[idx][:arguments] << (tc.dig('function', 'arguments') || '')
          end

          finish_reason ||= choice['finish_reason']&.to_sym

          if data['usage']
            final_usage = {
              prompt_tokens: data['usage']['prompt_tokens'],
              completion_tokens: data['usage']['completion_tokens'],
              total_tokens: data['usage']['total_tokens']
            }
          end
        end

        streaming_post(url, payload) { |chunk| parser.feed(chunk) }

        tool_calls = tool_calls_by_index.values.map do |tc|
          {
            id: tc[:id],
            name: tc[:name],
            arguments: tc[:arguments].empty? ? {} : JSON.parse(tc[:arguments])
          }
        end

        if final_usage
          sink.call(Events::Usage.new(
                      type: :usage, timestamp: Time.now, agent: nil, iteration: nil,
                      prompt_tokens: final_usage[:prompt_tokens],
                      completion_tokens: final_usage[:completion_tokens],
                      total_tokens: final_usage[:total_tokens],
                      cost_usd: Pricing.cost_for(config.model,
                                                 prompt_tokens: final_usage[:prompt_tokens],
                                                 completion_tokens: final_usage[:completion_tokens])
                    ))
        end

        {
          content: assembled_text.empty? ? nil : assembled_text,
          tool_calls: tool_calls,
          usage: final_usage || {},
          finish_reason: finish_reason || :stop,
          model: config.model,
          provider: provider_name
        }
      end

      def provider_name
        :openai
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
        choice = body.dig('choices', 0) || {}
        msg = choice['message'] || {}
        tool_calls = Array(msg['tool_calls']).map do |tc|
          {
            id: tc['id'],
            name: tc.dig('function', 'name'),
            arguments: JSON.parse(tc.dig('function', 'arguments') || '{}')
          }
        end
        {
          content: msg['content'],
          tool_calls: tool_calls,
          usage: {
            prompt_tokens: body.dig('usage', 'prompt_tokens'),
            completion_tokens: body.dig('usage', 'completion_tokens'),
            total_tokens: body.dig('usage', 'total_tokens')
          },
          finish_reason: (choice['finish_reason'] || 'stop').to_sym,
          model: body['model'] || config.model,
          provider: provider_name
        }
      end

      def auth_header
        { 'Authorization' => "Bearer #{config.openai_api_key || config.api_key}" }
      end

      def validate_config!
        raise ConfigurationError, 'OpenAI API key is required' unless config.openai_api_key || config.api_key
        raise ConfigurationError, 'Model is required' unless config.model
      end
    end
  end
end
