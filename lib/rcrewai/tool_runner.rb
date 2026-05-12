# frozen_string_literal: true

require_relative 'events'
require_relative 'provider_schema'

module RCrewAI
  class ToolRunner
    DEFAULT_MAX_ITERATIONS = 10

    def initialize(agent:, llm:, tools:, max_iterations: DEFAULT_MAX_ITERATIONS, event_sink: nil)
      @agent = agent
      @llm = llm
      @tools = tools
      @tools_by_name = tools.each_with_object({}) { |t, h| h[t.name] = t }
      @max_iterations = max_iterations
      @sink = event_sink || ->(_) {}
    end

    def run(messages:)
      msgs = messages.dup
      history = []
      iter = 0
      total_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }

      while iter < @max_iterations
        iter += 1
        emit(Events::IterationStart, iteration: iter, iteration_index: iter)

        response = @llm.chat(
          messages: msgs,
          tools: @tools.map(&:json_schema),
          stream: ->(e) { @sink.call(retag(e, iter)) }
        )
        accumulate_usage(total_usage, response[:usage])

        if response[:tool_calls].nil? || response[:tool_calls].empty?
          emit(Events::IterationEnd, iteration: iter, finish_reason: response[:finish_reason])
          return finalize(content: response[:content], history: history, iter: iter,
                          finish_reason: response[:finish_reason], usage: total_usage)
        end

        msgs << { role: 'assistant', content: response[:content], tool_calls: response[:tool_calls] }

        response[:tool_calls].each do |tc|
          tool = @tools_by_name[tc[:name]]
          emit(Events::ToolCallStart, iteration: iter,
                                      tool: tc[:name], args: tc[:arguments], call_id: tc[:id])

          if tool.nil?
            err = "tool not found: #{tc[:name]}"
            emit(Events::ToolCallError, iteration: iter,
                                        tool: tc[:name], call_id: tc[:id], error: err)
            msgs << tool_result_message(tc[:id], "ERROR: #{err}")
            next
          end

          started = monotonic_ms
          begin
            result = tool.execute_with_validation(tc[:arguments] || {})
            duration = monotonic_ms - started
            if @agent.respond_to?(:memory) && @agent.memory
              @agent.memory.add_tool_usage(tc[:name], tc[:arguments], result)
            end
            emit(Events::ToolCallResult, iteration: iter,
                                         tool: tc[:name], call_id: tc[:id], result: result,
                                         duration_ms: duration)
            history << { tool: tc[:name], args: tc[:arguments], result: result, duration_ms: duration }
            msgs << tool_result_message(tc[:id], result.to_s)
          rescue StandardError => e
            emit(Events::ToolCallError, iteration: iter,
                                        tool: tc[:name], call_id: tc[:id], error: e.message)
            msgs << tool_result_message(tc[:id], "ERROR: #{e.message}")
          end
        end

        emit(Events::IterationEnd, iteration: iter, finish_reason: :tool_calls)
      end

      finalize(content: nil, history: history, iter: iter,
               finish_reason: :max_iterations, usage: total_usage)
    end

    private

    def tool_result_message(call_id, content)
      { role: 'tool', tool_call_id: call_id, content: content }
    end

    def emit(klass, iteration:, **attrs)
      type_sym = klass.name.split('::').last
                      .gsub(/([A-Z])/) { "_#{Regexp.last_match(1).downcase}" }
                      .sub(/^_/, '').to_sym
      @sink.call(klass.new(
                   type: type_sym,
                   timestamp: Time.now,
                   agent: agent_name,
                   iteration: iteration,
                   **attrs
                 ))
    end

    def agent_name
      @agent.respond_to?(:name) ? @agent.name : nil
    end

    def retag(event, iter)
      event.agent = agent_name if event.respond_to?(:agent=) && event.agent.nil?
      event.iteration = iter if event.respond_to?(:iteration=) && event.iteration.nil?
      event
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
