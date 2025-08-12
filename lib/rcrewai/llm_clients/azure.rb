# frozen_string_literal: true

require_relative 'base'

module RCrewAI
  module LLMClients
    class Azure < Base
      def initialize(config = RCrewAI.configuration)
        super
        @base_url = config.base_url || build_azure_url
        @api_version = config.api_version || '2024-02-01'
        @deployment_name = config.deployment_name || config.model
      end

      def chat(messages:, **options)
        payload = {
          messages: format_messages(messages),
          temperature: options[:temperature] || config.temperature,
          max_tokens: options[:max_tokens] || config.max_tokens
        }

        # Add additional OpenAI-compatible options
        payload[:top_p] = options[:top_p] if options[:top_p]
        payload[:frequency_penalty] = options[:frequency_penalty] if options[:frequency_penalty]
        payload[:presence_penalty] = options[:presence_penalty] if options[:presence_penalty]
        payload[:stop] = options[:stop] if options[:stop]

        url = "#{@base_url}/openai/deployments/#{@deployment_name}/chat/completions?api-version=#{@api_version}"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers.merge(authorization_header))
        log_response(response)

        result = handle_response(response)
        format_response(result)
      end

      def complete(prompt:, **options)
        # For older models that use completions endpoint
        payload = {
          prompt: prompt,
          temperature: options[:temperature] || config.temperature,
          max_tokens: options[:max_tokens] || config.max_tokens
        }

        url = "#{@base_url}/openai/deployments/#{@deployment_name}/completions?api-version=#{@api_version}"
        log_request(:post, url, payload)

        response = http_client.post(url, payload, build_headers.merge(authorization_header))
        log_response(response)

        result = handle_response(response)
        format_completion_response(result)
      end

      def models
        # Azure OpenAI uses deployments instead of models
        url = "#{@base_url}/openai/deployments?api-version=#{@api_version}"
        response = http_client.get(url, {}, build_headers.merge(authorization_header))
        result = handle_response(response)
        
        if result['data']
          result['data'].map { |deployment| deployment['id'] }
        else
          [@deployment_name].compact
        end
      end

      private

      def authorization_header
        { 'api-key' => config.api_key }
      end

      def format_messages(messages)
        messages.map do |msg|
          if msg.is_a?(Hash)
            msg
          else
            { role: 'user', content: msg.to_s }
          end
        end
      end

      def format_response(response)
        choice = response.dig('choices', 0)
        return nil unless choice

        {
          content: choice.dig('message', 'content'),
          role: choice.dig('message', 'role'),
          finish_reason: choice['finish_reason'],
          usage: response['usage'],
          model: @deployment_name,
          provider: :azure
        }
      end

      def format_completion_response(response)
        choice = response.dig('choices', 0)
        return nil unless choice

        {
          content: choice['text'],
          finish_reason: choice['finish_reason'],
          usage: response['usage'],
          model: @deployment_name,
          provider: :azure
        }
      end

      def validate_config!
        super
        raise ConfigurationError, "Azure API key is required" unless config.azure_api_key || config.api_key
        raise ConfigurationError, "Azure base URL or endpoint is required" unless config.base_url || azure_endpoint
        raise ConfigurationError, "Azure deployment name is required" unless config.deployment_name || config.model
      end

      def build_azure_url
        endpoint = azure_endpoint
        return nil unless endpoint
        
        # Remove trailing slash and add proper path
        endpoint = endpoint.chomp('/')
        "#{endpoint}"
      end

      def azure_endpoint
        # Try multiple environment variable names
        ENV['AZURE_OPENAI_ENDPOINT'] || 
        ENV['AZURE_ENDPOINT'] || 
        config.instance_variable_get(:@azure_endpoint)
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 400
          error_details = response.body.dig('error', 'message') || response.body
          raise APIError, "Bad request: #{error_details}"
        when 401
          raise AuthenticationError, "Invalid API key or authentication failed"
        when 403
          raise AuthenticationError, "Access denied - check your API key and permissions"
        when 404
          raise ModelNotFoundError, "Deployment '#{@deployment_name}' not found"
        when 429
          raise RateLimitError, "Rate limit exceeded or quota exhausted"
        when 500..599
          raise APIError, "Azure OpenAI service error: #{response.status}"
        else
          raise APIError, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end