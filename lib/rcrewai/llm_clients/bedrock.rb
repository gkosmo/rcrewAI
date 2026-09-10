# frozen_string_literal: true

require 'cgi'
require 'faraday'
require 'json'
require_relative 'base'
require_relative '../events'
require_relative '../pricing'

module RCrewAI
  module LLMClients
    # AWS Bedrock via the Converse API (v4). Converse gives every Bedrock model
    # one request/response shape regardless of the underlying vendor, so this
    # client speaks Converse rather than each model's native format.
    #
    # Authentication: the configured api_key is sent as a bearer token, which
    # covers Bedrock API keys and any gateway fronting Bedrock. Full SigV4
    # request signing is not implemented -- it needs the aws-sigv4 gem, and
    # adding a hard AWS dependency for one provider is not worth it. Users
    # needing SigV4 can sign via a before_request hook.
    class Bedrock < Base
      STOP_REASONS = {
        'end_turn' => :stop,
        'stop_sequence' => :stop,
        'max_tokens' => :length,
        'tool_use' => :tool_calls,
        'content_filtered' => :content_filter
      }.freeze

      def initialize(config = RCrewAI.configuration, **hooks)
        super
        @region = config.aws_region
      end

      def provider_name
        :bedrock
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options) # rubocop:disable Lint/UnusedMethodArgument
        system_text = extract_system(messages)
        payload = {
          messages: format_messages(messages),
          inferenceConfig: {
            temperature: options[:temperature] || config.temperature,
            maxTokens: options[:max_tokens] || config.max_tokens
          }.compact
        }
        payload[:system] = [{ text: system_text }] if system_text
        payload[:toolConfig] = { tools: format_tools(tools) } if tools && !tools.empty?

        plain_chat(payload)
      end

      # Converse exposes tool use uniformly, but streaming uses a separate
      # endpoint and event-stream framing that this client does not implement.
      def supports_native_tools?(model: config.model) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      private

      def plain_chat(payload)
        url = converse_url
        payload = apply_before_request(payload)
        started_at = Time.now
        log_request(:post, url, payload)
        response = http_client.post(url, payload, build_headers.merge(auth_header))
        log_response(response)
        body = handle_response(response)
        apply_after_response(normalize(body), started_at)
      end

      def converse_url
        "https://bedrock-runtime.#{@region}.amazonaws.com/model/#{CGI.escape(config.model)}/converse"
      end

      # Converse carries the system prompt at the top level, not in messages.
      def extract_system(messages)
        systems = messages.select { |m| m.is_a?(Hash) && m[:role].to_s == 'system' }
        return nil if systems.empty?

        systems.map { |m| m[:content] }.join("\n\n")
      end

      # Every message content is a list of typed blocks.
      def format_messages(messages)
        messages.reject { |m| m.is_a?(Hash) && m[:role].to_s == 'system' }.map do |m|
          { role: m[:role].to_s, content: [{ text: m[:content].to_s }] }
        end
      end

      def format_tools(tools)
        tools.map do |t|
          { toolSpec: { name: t[:name], description: t[:description],
                        inputSchema: { json: t[:parameters] } } }
        end
      end

      def normalize(body)
        blocks = body.dig('output', 'message', 'content') || []
        text = blocks.filter_map { |b| b['text'] }.join
        tool_calls = blocks.filter_map do |b|
          use = b['toolUse']
          next unless use

          { id: use['toolUseId'], name: use['name'], arguments: use['input'] || {} }
        end

        {
          content: text.empty? ? nil : text,
          tool_calls: tool_calls,
          usage: {
            prompt_tokens: body.dig('usage', 'inputTokens'),
            completion_tokens: body.dig('usage', 'outputTokens'),
            total_tokens: body.dig('usage', 'totalTokens')
          },
          finish_reason: STOP_REASONS.fetch(body['stopReason'], :stop),
          model: config.model,
          provider: provider_name
        }
      end

      def auth_header
        { 'Authorization' => "Bearer #{config.api_key}" }
      end

      def validate_config!
        raise ConfigurationError, 'Bedrock API key is required' unless config.api_key
        raise ConfigurationError, 'An AWS region is required for Bedrock' unless config.aws_region
        raise ConfigurationError, 'Model is required' unless config.model
      end
    end
  end
end
