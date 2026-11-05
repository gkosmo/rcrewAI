# frozen_string_literal: true

require_relative 'openai'

module RCrewAI
  module LLMClients
    # OpenAI's Responses API. Same host and auth as Chat Completions, but a
    # different request and response shape:
    #
    #   - messages go under :input, and the system prompt under :instructions
    #   - :max_tokens becomes :max_output_tokens
    #   - the reply is an :output array of typed items (message, function_call,
    #     reasoning, ...) rather than a single choice
    #   - usage is input_tokens / output_tokens
    #
    # Only the non-streaming path is implemented; Responses streams a distinct
    # set of semantic events that the SSE assembly here does not model.
    class OpenAIResponses < OpenAI
      def provider_name
        :openai_responses
      end

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options) # rubocop:disable Lint/UnusedMethodArgument
        payload = {
          model: config.model,
          input: format_input(messages),
          temperature: options[:temperature] || config.temperature,
          max_output_tokens: options[:max_tokens] || config.max_tokens
        }.compact

        instructions = extract_instructions(messages)
        payload[:instructions] = instructions if instructions

        if tools && !tools.empty?
          payload[:tools] = format_tools(tools)
          payload[:tool_choice] = tool_choice if tool_choice != :auto
        end

        plain_chat(payload)
      end

      private

      def chat_url
        "#{@base_url}/responses"
      end

      # Responses carries the system prompt out-of-band as :instructions.
      def extract_instructions(messages)
        systems = messages.select { |m| m.is_a?(Hash) && m[:role].to_s == 'system' }
        return nil if systems.empty?

        systems.map { |m| m[:content] }.join("\n\n")
      end

      def format_input(messages)
        messages.reject { |m| m.is_a?(Hash) && m[:role].to_s == 'system' }.flat_map do |m|
          case m[:role].to_s
          when 'assistant' then assistant_items(m)
          when 'tool' then [{ type: 'function_call_output', call_id: m[:tool_call_id], output: m[:content] }]
          else [{ role: m[:role].to_s, content: m[:content] }]
          end
        end
      end

      # Output items are replayed as received, because reasoning models need
      # their reasoning items alongside the function calls.
      def assistant_items(msg)
        return msg[:raw_content] if msg[:raw_content]
        return [{ role: 'assistant', content: msg[:content] }] if msg[:tool_calls].nil? || msg[:tool_calls].empty?

        text = msg[:content].to_s.empty? ? [] : [{ role: 'assistant', content: msg[:content] }]
        text + msg[:tool_calls].map do |call|
          { type: 'function_call', call_id: call[:id], name: call[:name],
            arguments: JSON.generate(call[:arguments] || {}) }
        end
      end

      # Responses flattens the function definition instead of nesting it under
      # a :function key the way Chat Completions does.
      def format_tools(tools)
        tools.map do |t|
          { type: 'function', name: t[:name], description: t[:description],
            parameters: t[:parameters] }
        end
      end

      def normalize_non_streaming(body)
        output = Array(body['output'])
        text = extract_text(output)
        tool_calls = extract_tool_calls(output)

        {
          content: text.empty? ? nil : text,
          tool_calls: tool_calls,
          raw_content: output,
          usage: {
            prompt_tokens: body.dig('usage', 'input_tokens'),
            completion_tokens: body.dig('usage', 'output_tokens'),
            total_tokens: body.dig('usage', 'total_tokens')
          },
          finish_reason: finish_reason_for(body, tool_calls),
          model: body['model'] || config.model,
          provider: provider_name
        }
      end

      def extract_text(output)
        output.select { |item| item['type'] == 'message' }
              .flat_map { |item| Array(item['content']) }
              .select { |part| part['type'] == 'output_text' }
              .map { |part| part['text'] }
              .join
      end

      def extract_tool_calls(output)
        output.select { |item| item['type'] == 'function_call' }.map do |item|
          {
            id: item['call_id'] || item['id'],
            name: item['name'],
            arguments: parse_arguments(item['arguments'])
          }
        end
      end

      def parse_arguments(raw)
        return {} if raw.nil? || raw.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def finish_reason_for(body, tool_calls)
        return :tool_calls if tool_calls.any?

        if body['status'] == 'incomplete'
          reason = body.dig('incomplete_details', 'reason')
          return reason == 'max_output_tokens' ? :length : :incomplete
        end

        :stop
      end
    end
  end
end
