# frozen_string_literal: true

require_relative 'base'

module RCrewAI
  module LLMClients
    class Ollama < Base
      DEFAULT_URL = 'http://localhost:11434'

      def initialize(config = RCrewAI.configuration)
        super
        @base_url = config.base_url || ollama_url || DEFAULT_URL
      end

      def chat(messages:, **options)
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

        # Add stop sequences if provided
        payload[:options][:stop] = options[:stop] if options[:stop]

        url = "#{@base_url}/api/chat"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers)
        log_response(response)

        result = handle_response(response)
        format_response(result)
      end

      def complete(prompt:, **options)
        payload = {
          model: config.model,
          prompt: prompt,
          options: {
            temperature: options[:temperature] || config.temperature,
            num_predict: options[:max_tokens] || config.max_tokens,
            top_p: options[:top_p],
            top_k: options[:top_k],
            repeat_penalty: options[:repeat_penalty]
          }.compact
        }

        payload[:options][:stop] = options[:stop] if options[:stop]

        url = "#{@base_url}/api/generate"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers)
        log_response(response)

        result = handle_response(response)
        format_completion_response(result)
      end

      def models
        url = "#{@base_url}/api/tags"
        response = http_client.get(url, {}, build_headers)
        result = handle_response(response)
        
        if result['models']
          result['models'].map { |model| model['name'] }
        else
          []
        end
      rescue => e
        logger.warn "Failed to fetch Ollama models: #{e.message}"
        []
      end

      def pull_model(model_name)
        payload = { name: model_name }
        url = "#{@base_url}/api/pull"
        
        response = http_client.post(url, payload, build_headers)
        handle_response(response)
      end

      def model_info(model_name = nil)
        model_name ||= config.model
        payload = { name: model_name }
        url = "#{@base_url}/api/show"
        
        response = http_client.post(url, payload, build_headers)
        handle_response(response)
      rescue => e
        logger.warn "Failed to get model info for #{model_name}: #{e.message}"
        nil
      end

      private

      def format_messages(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            {
              role: msg[:role],
              content: msg[:content]
            }
          else
            { role: 'user', content: msg.to_s }
          end
        end
      end

      def format_response(response)
        message = response['message']
        return nil unless message

        # Ollama doesn't provide detailed usage stats by default
        usage = {
          'prompt_tokens' => response['prompt_eval_count'],
          'completion_tokens' => response['eval_count'],
          'total_tokens' => (response['prompt_eval_count'] || 0) + (response['eval_count'] || 0)
        }.compact

        {
          content: message['content'],
          role: message['role'] || 'assistant',
          finish_reason: response['done'] ? 'stop' : nil,
          usage: usage,
          model: response['model'] || config.model,
          provider: :ollama
        }
      end

      def format_completion_response(response)
        {
          content: response['response'],
          finish_reason: response['done'] ? 'stop' : nil,
          usage: {
            'prompt_tokens' => response['prompt_eval_count'],
            'completion_tokens' => response['eval_count'],
            'total_tokens' => (response['prompt_eval_count'] || 0) + (response['eval_count'] || 0)
          }.compact,
          model: response['model'] || config.model,
          provider: :ollama
        }
      end

      def validate_config!
        # Ollama doesn't require an API key
        raise ConfigurationError, "Model is required" unless config.model
        
        # Test connection to Ollama server
        test_connection
      end

      def test_connection
        url = "#{@base_url}/api/tags"
        response = http_client.get(url, {}, build_headers)
        
        unless (200..299).include?(response.status)
          raise ConfigurationError, "Cannot connect to Ollama server at #{@base_url}"
        end
      rescue Faraday::ConnectionFailed
        raise ConfigurationError, "Cannot connect to Ollama server at #{@base_url}. Is Ollama running?"
      end

      def ollama_url
        ENV['OLLAMA_HOST'] || ENV['OLLAMA_URL']
      end

      def build_headers
        # Ollama doesn't require special headers
        {
          'Content-Type' => 'application/json',
          'User-Agent' => "rcrewai/#{RCrewAI::VERSION}"
        }
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          error_details = response.body['error'] || response.body
          raise APIError, "Bad request: #{error_details}"
        when 404
          raise ModelNotFoundError, "Model '#{config.model}' not found. Try running: ollama pull #{config.model}"
        when 500..599
          raise APIError, "Ollama server error: #{response.status}"
        else
          raise APIError, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end