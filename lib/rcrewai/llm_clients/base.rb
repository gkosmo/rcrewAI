# frozen_string_literal: true

require 'faraday'
require 'json'
require 'logger'

module RCrewAI
  module LLMClients
    class Base
      attr_reader :config, :logger

      def initialize(config = RCrewAI.configuration, before_request: nil, after_response: nil)
        @config = config
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
        @before_request_hooks = Array(before_request)
        @after_response_hooks = Array(after_response)
        validate_config!
      end

      # Registers a hook run just before the request payload is sent.
      # Receives (payload, context) where context carries :provider and :model.
      # Returning a payload replaces it; returning nil keeps the original.
      def before_request(callable = nil, &block)
        @before_request_hooks << (callable || block)
        self
      end

      # Registers a hook run just after a response is normalized.
      # Receives (result, context) where context adds :duration_ms.
      # Returning a result replaces it; returning nil keeps the original.
      def after_response(callable = nil, &block)
        @after_response_hooks << (callable || block)
        self
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        raise NotImplementedError, 'Subclasses must implement #chat method'
      end

      def supports_native_tools?(model: config.model) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      def complete(prompt:, **options)
        chat(messages: [{ role: 'user', content: prompt }], **options)
      end

      protected

      # Threads the payload through every before_request hook. A hook that
      # raises is reported and skipped -- observability must never break a call.
      def apply_before_request(payload)
        return payload if @before_request_hooks.empty?

        ctx = hook_context
        @before_request_hooks.reduce(payload) do |acc, hook|
          hook.call(acc, ctx) || acc
        rescue StandardError => e
          Kernel.warn "[rcrewai] before_request hook raised: #{e.class}: #{e.message}"
          acc
        end
      end

      # Threads the normalized result through every after_response hook.
      def apply_after_response(result, started_at)
        return result if @after_response_hooks.empty?

        ctx = hook_context.merge(duration_ms: ((Time.now - started_at) * 1000).round(3))
        @after_response_hooks.reduce(result) do |acc, hook|
          hook.call(acc, ctx) || acc
        rescue StandardError => e
          Kernel.warn "[rcrewai] after_response hook raised: #{e.class}: #{e.message}"
          acc
        end
      end

      def hook_context
        { provider: provider_name, model: config.model }
      end

      # Providers override this; Base has no wire identity of its own.
      def provider_name
        nil
      end

      def validate_config!
        raise ConfigurationError, 'API key is required' unless config.api_key
        raise ConfigurationError, 'Model is required' unless config.model
      end

      def build_headers
        {
          'Content-Type' => 'application/json',
          'User-Agent' => "rcrewai/#{RCrewAI::VERSION}"
        }
      end

      def http_client
        @http_client ||= Faraday.new do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
          f.options.timeout = config.timeout
        end
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          raise APIError, "Bad request: #{response.body}"
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

      def log_request(method, url, payload = nil)
        logger.info "#{method.upcase} #{url}"
        logger.debug "Payload: #{payload}" if payload
      end

      def log_response(response)
        logger.debug "Response: #{response.status} - #{response.body}"
      end
    end

    class APIError < RCrewAI::Error; end
    class AuthenticationError < APIError; end
    class RateLimitError < APIError; end
    class ModelNotFoundError < APIError; end
  end
end
