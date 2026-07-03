# frozen_string_literal: true

require_relative 'events'

module RCrewAI
  # Behavior-preserving extraction of the prompt-parsed `USE_TOOL[]` /
  # `FINAL_ANSWER[]` loop that lived in Agent. Used as a fallback when an
  # agent's tools have no DSL schemas declared OR the configured LLM does
  # not support native function calling.
  class LegacyReactRunner
    DEFAULT_MAX_ITERATIONS = 10

    def initialize(agent:, llm:, tools:, max_iterations: DEFAULT_MAX_ITERATIONS, event_sink: nil)
      @agent = agent
      @llm = llm
      @tools = tools
      @max_iterations = max_iterations
      @sink = event_sink || ->(_) {}
    end

    def run(messages:)
      msgs = messages.dup
      history = []
      iter = 0
      total_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      last_reasoning = nil
      last_action_result = nil

      while iter < @max_iterations
        iter += 1
        emit(Events::IterationStart, iteration: iter, iteration_index: iter)

        response = @llm.chat(messages: fit_context(msgs))
        accumulate_usage(total_usage, response[:usage])
        reasoning = response[:content] || ''
        last_reasoning = reasoning

        action_result, iteration_history = parse_and_execute_actions(reasoning, iter)
        history.concat(iteration_history)
        last_action_result = action_result

        msgs << { role: 'assistant', content: reasoning }
        msgs << { role: 'user', content: action_result } if action_result && !action_result.empty?

        finish_reason = response[:finish_reason]
        emit(Events::IterationEnd, iteration: iter, finish_reason: finish_reason)

        next unless task_complete?(reasoning, action_result) || finish_reason == :stop

        final = extract_final_result(reasoning, action_result)
        return finalize(content: final, history: history, iter: iter,
                        finish_reason: finish_reason || :stop, usage: total_usage)
      end

      final = extract_final_result(last_reasoning || '', last_action_result) ||
              'Task execution reached limits without clear completion'
      finalize(content: final, history: history, iter: iter,
               finish_reason: :max_iterations, usage: total_usage)
    end

    private

    # Trims the message list to the model's context window when the agent
    # supports it; a no-op otherwise.
    def fit_context(messages)
      @agent.respond_to?(:fit_context) ? @agent.fit_context(messages) : messages
    end

    def parse_and_execute_actions(reasoning, iter)
      results = []
      iteration_history = []
      reasoning.scan(/USE_TOOL\[(\w+)\]\(([^)]*)\)/).each do |tool_name, params_str|
        params = parse_tool_params(params_str)
        tool = find_tool(tool_name)

        emit(Events::ToolCallStart, iteration: iter, tool: tool_name,
                                    args: params, call_id: nil)

        if tool.nil?
          err = "tool not found: #{tool_name}"
          emit(Events::ToolCallError, iteration: iter, tool: tool_name, call_id: nil, error: err)
          results << "Tool #{tool_name} failed: #{err}"
          next
        end

        started = monotonic_ms
        begin
          result = tool.execute(**params)
          duration = monotonic_ms - started
          @agent.memory.add_tool_usage(tool_name, params, result) if @agent.respond_to?(:memory) && @agent.memory
          emit(Events::ToolCallResult, iteration: iter, tool: tool_name,
                                       call_id: nil, result: result, duration_ms: duration)
          iteration_history << { tool: tool_name, args: params, result: result, duration_ms: duration }
          results << "Tool #{tool_name} result: #{result}"
        rescue StandardError => e
          emit(Events::ToolCallError, iteration: iter, tool: tool_name,
                                      call_id: nil, error: e.message)
          results << "Tool #{tool_name} failed: #{e.message}"
        end
      end

      [results.join("\n"), iteration_history]
    end

    def parse_tool_params(params_str)
      params = {}
      return params if params_str.strip.empty?

      params_str.split(',').map(&:strip).each do |pair|
        key, value = pair.split('=', 2).map(&:strip)
        next unless key && value

        value = value.gsub(/^["']|["']$/, '')
        params[key.to_sym] = value
      end
      params
    end

    def find_tool(name)
      @tools.find do |t|
        t.name == name || t.class.name.split('::').last.downcase == name.downcase
      end
    end

    def task_complete?(reasoning, _action_result)
      reasoning.include?('FINAL_ANSWER[') ||
        reasoning.downcase.include?('task complete') ||
        reasoning.downcase.include?('finished')
    end

    def extract_final_result(reasoning, action_result)
      if (match = reasoning.match(/FINAL_ANSWER\[(.*?)\]$/m))
        return match[1].strip
      end

      lines = reasoning.split("\n").map(&:strip).reject(&:empty?)
      final_lines = lines.last(3).join(' ')
      return final_lines if final_lines.length > 20

      action_result
    end

    def emit(klass, iteration:, **attrs)
      type_sym = klass.name.split('::').last
                      .gsub(/([A-Z])/) { "_#{Regexp.last_match(1).downcase}" }
                      .sub(/^_/, '').to_sym
      @sink.call(klass.new(
                   type: type_sym,
                   timestamp: Time.now,
                   agent: @agent.respond_to?(:name) ? @agent.name : nil,
                   iteration: iteration,
                   **attrs
                 ))
    end

    def accumulate_usage(total, partial)
      return unless partial.is_a?(Hash)

      total[:prompt_tokens]     += partial[:prompt_tokens]     || 0
      total[:completion_tokens] += partial[:completion_tokens] || 0
      total[:total_tokens]      += partial[:total_tokens]      || 0
    end

    def finalize(content:, history:, iter:, finish_reason:, usage:)
      {
        content: content,
        tool_calls_history: history,
        usage: usage,
        iterations: iter,
        finish_reason: finish_reason
      }
    end

    def monotonic_ms
      (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) * 1000).to_i
    end
  end
end
