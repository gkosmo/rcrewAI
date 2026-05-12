# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'base'
require_relative '../events'
require_relative '../provider_schema'
require_relative '../pricing'

module RCrewAI
  module LLMClients
    class Ollama < Base
      DEFAULT_URL = 'http://localhost:11434'

      NATIVE_TOOL_MODELS = %w[
        llama3.1 llama3.1:8b llama3.1:70b llama3.1:405b
        llama3.2 llama3.2:1b llama3.2:3b
        qwen2.5 qwen2.5:7b qwen2.5:14b qwen2.5:32b qwen2.5:72b
        mistral-nemo mistral-large
        command-r command-r-plus
        firefunction-v2
      ].freeze

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = config.base_url || ollama_url || DEFAULT_URL
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        payload = {
          model: config.model,
          messages: format_messages(messages),
          options: {
            temperature: options[:temperature] || config.temperature,
            num_predict: options[:max_tokens] || config.max_tokens,
            top_p: options[:top_p],
            top_k: options[:top_k],
            repeat_penalty: options[:repeat_penalty]
          }.compact
        }
        payload[:options][:stop] = options[:stop] if options[:stop]

        if tools && !tools.empty?
          payload[:tools] = ProviderSchema.for_many(:ollama, tools)
        end

        url = "#{@base_url}/api/chat"
        if stream
          payload[:stream] = true
          stream_chat(url, payload, stream)
        else
          payload[:stream] = false
          plain_chat(url, payload)
        end
      end

      def supports_native_tools?(model: config.model)
        override = RCrewAI.configuration.respond_to?(:ollama_native_tools) ? RCrewAI.configuration.ollama_native_tools : nil
        return override unless override.nil?

        base = model.to_s.split(':').first
        NATIVE_TOOL_MODELS.any? { |m| m == model || m.split(':').first == base }
      end

      def models
        url = "#{@base_url}/api/tags"
        response = http_client.get(url, {}, build_headers)
        result = handle_response(response)
        Array(result['models']).map { |m| m['name'] }
      rescue StandardError => e
        logger.warn "Failed to fetch Ollama models: #{e.message}"
        []
      end

      def pull_model(model_name)
        url = "#{@base_url}/api/pull"
        response = http_client.post(url, { name: model_name }, build_headers)
        handle_response(response)
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
        prompt_tokens = nil
        completion_tokens = nil
        buffer = String.new(encoding: Encoding::UTF_8)

        process_line = lambda do |line|
          line = line.strip
          return if line.empty?

          data = JSON.parse(line)
          if (msg = data['message'])
            if msg['content']
              assembled_text << msg['content']
              sink.call(Events::TextDelta.new(type: :text_delta, timestamp: Time.now,
                                              agent: nil, iteration: nil,
                                              text: msg['content']))
            end
            Array(msg['tool_calls']).each do |tc|
              fn = tc['function'] || {}
              tool_calls << {
                id: tc['id'],
                name: fn['name'],
                arguments: fn['arguments'].is_a?(String) ? JSON.parse(fn['arguments']) : (fn['arguments'] || {})
              }
            end
          end
          if data['done']
            finish_reason = tool_calls.any? ? :tool_calls : :stop
            prompt_tokens = data['prompt_eval_count']
            completion_tokens = data['eval_count']
          end
        end

        streaming_post(url, payload) do |chunk|
          chunk = chunk.dup.force_encoding(Encoding::UTF_8) unless chunk.encoding == Encoding::UTF_8
          buffer << chunk
          while (idx = buffer.index("\n"))
            line = buffer.slice!(0, idx + 1)
            process_line.call(line)
          end
        end
        process_line.call(buffer) unless buffer.empty?

        if prompt_tokens || completion_tokens
          sink.call(Events::Usage.new(
                      type: :usage, timestamp: Time.now, agent: nil, iteration: nil,
                      prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
                      total_tokens: (prompt_tokens || 0) + (completion_tokens || 0),
                      cost_usd: nil
                    ))
        end

        {
          content: assembled_text.empty? ? nil : assembled_text,
          tool_calls: tool_calls,
          usage: {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: (prompt_tokens || 0) + (completion_tokens || 0)
          },
          finish_reason: finish_reason || :stop,
          model: config.model,
          provider: :ollama
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
        msg = body['message'] || {}
        text = msg['content']
        tool_calls = Array(msg['tool_calls']).map do |tc|
          fn = tc['function'] || {}
          args = fn['arguments']
          args = JSON.parse(args) if args.is_a?(String)
          { id: tc['id'], name: fn['name'], arguments: args || {} }
        end
        prompt_tokens = body['prompt_eval_count']
        completion_tokens = body['eval_count']

        {
          content: text && !text.empty? ? text : nil,
          tool_calls: tool_calls,
          usage: {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: (prompt_tokens || 0) + (completion_tokens || 0)
          },
          finish_reason: tool_calls.any? ? :tool_calls : :stop,
          model: body['model'] || config.model,
          provider: :ollama
        }
      end

      def format_messages(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            { role: msg[:role], content: msg[:content] }
          else
            { role: 'user', content: msg.to_s }
          end
        end
      end

      def ollama_url
        ENV['OLLAMA_HOST'] || ENV['OLLAMA_URL']
      end

      def build_headers
        {
          'Content-Type' => 'application/json',
          'User-Agent' => "rcrewai/#{RCrewAI::VERSION}"
        }
      end

      def validate_config!
        raise ConfigurationError, 'Model is required' unless config.model
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          details = response.body.is_a?(Hash) ? response.body['error'] : response.body
          raise APIError, "Bad request: #{details}"
        when 404
          raise ModelNotFoundError, "Model '#{config.model}' not found. Try: ollama pull #{config.model}"
        when 500..599
          raise APIError, "Ollama server error: #{response.status}"
        else
          raise APIError, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end
