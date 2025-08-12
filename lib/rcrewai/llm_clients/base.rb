# frozen_string_literal: true

require 'faraday'
require 'json'
require 'logger'

module RCrewAI
  module LLMClients
    class Base
      attr_reader :config, :logger

      def initialize(config = RCrewAI.configuration)
        @config = config
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
        validate_config!
      end

      def chat(messages:, **options)
        raise NotImplementedError, "Subclasses must implement #chat method"
      end

      def complete(prompt:, **options)
        chat(messages: [{ role: 'user', content: prompt }], **options)
      end

      protected

      def validate_config!
        raise ConfigurationError, "API key is required" unless config.api_key
        raise ConfigurationError, "Model is required" unless config.model
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
          raise AuthenticationError, "Invalid API key"
        when 429
          raise RateLimitError, "Rate limit exceeded"
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