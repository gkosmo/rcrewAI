# frozen_string_literal: true

require 'securerandom'
require_relative 'events'
require_relative 'provider_schema'

module RCrewAI
  class ToolRunner
    DEFAULT_MAX_ITERATIONS = 10
    DEFAULT_TOOL_CONCURRENCY = 8

    def initialize(agent:, llm:, tools:, **opts)
      @agent = agent
      @llm = llm
      @tools = tools
      @tools_by_name = tools.each_with_object({}) { |t, h| h[t.name] = t }
      @max_iterations = opts.fetch(:max_iterations, DEFAULT_MAX_ITERATIONS)
      @sink = opts[:event_sink] || ->(_) {}
      @parallel_tools = opts.fetch(:parallel_tools, true)
      @max_tool_concurrency = opts.fetch(:max_tool_concurrency, DEFAULT_TOOL_CONCURRENCY)
      @tool_usage_lock = Mutex.new
    end

    def run(messages:)
      Events.with_parent(@run_span_id ||= SecureRandom.uuid) { run_loop(messages: messages) }
    end

    private

    def run_loop(messages:)
      msgs = messages.dup
      history = []
      iter = 0
      total_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }

      while iter < @max_iterations
        iter += 1
        emit(Events::IterationStart, iteration: iter, iteration_index: iter)

        response = @llm.chat(
          messages: fit_context(msgs),
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

        run_tool_calls(response[:tool_calls], iter).each do |outcome|
          history << outcome[:history] if outcome[:history]
          msgs << outcome[:message]
        end

        emit(Events::IterationEnd, iteration: iter, finish_reason: :tool_calls)
      end

      finalize(content: nil, history: history, iter: iter,
               finish_reason: :max_iterations, usage: total_usage)
    end

    # Trims the message list to the model's context window when the agent
    # supports it; a no-op otherwise.
    def fit_context(messages)
      @agent.respond_to?(:fit_context) ? @agent.fit_context(messages) : messages
    end

    def tool_result_message(call_id, content)
      { role: 'tool', tool_call_id: call_id, content: content }
    end

    # Executes one turn's tool calls, concurrently when there is more than one.
    #
    # Models routinely request several independent tools in a single turn;
    # running them in sequence makes the turn cost the sum of their latencies
    # rather than the max. Results are collected by index, so the order the
    # model asked for is preserved no matter which finishes first -- the
    # message history must stay aligned with the tool_call ids.
    def run_tool_calls(tool_calls, iter)
      return tool_calls.map { |tc| execute_tool_call(tc, iter) } unless parallel?(tool_calls)

      # Events are emitted from worker threads, so carry the run span across
      # the boundary: Events.with_parent is thread-local by design.
      span = Events.current_parent
      tool_calls.each_slice(@max_tool_concurrency).flat_map do |slice|
        slice.map { |tc| Thread.new { Events.with_parent(span) { execute_tool_call(tc, iter) } } }
             .map(&:value)
      end
    end

    def parallel?(tool_calls)
      @parallel_tools && tool_calls.length > 1
    end

    # Runs one tool call and returns what the caller should record. Never
    # raises: a failing tool becomes an ERROR message fed back to the model,
    # exactly as it did when this ran inline.
    def execute_tool_call(call, iter)
      tool = @tools_by_name[call[:name]]
      emit(Events::ToolCallStart, iteration: iter,
                                  tool: call[:name], args: call[:arguments], call_id: call[:id])

      if tool.nil?
        err = "tool not found: #{call[:name]}"
        emit(Events::ToolCallError, iteration: iter,
                                    tool: call[:name], call_id: call[:id], error: err)
        return { message: tool_result_message(call[:id], "ERROR: #{err}") }
      end

      started = monotonic_ms
      begin
        result = tool.execute_with_validation(call[:arguments] || {})
        duration = monotonic_ms - started
        record_tool_usage(call, result)
        emit(Events::ToolCallResult, iteration: iter,
                                     tool: call[:name], call_id: call[:id], result: result,
                                     duration_ms: duration)
        {
          history: { tool: call[:name], args: call[:arguments], result: result, duration_ms: duration },
          message: tool_result_message(call[:id], result.to_s)
        }
      rescue StandardError => e
        emit(Events::ToolCallError, iteration: iter,
                                    tool: call[:name], call_id: call[:id], error: e.message)
        { message: tool_result_message(call[:id], "ERROR: #{e.message}") }
      end
    end

    # Agent memory is shared across the worker threads of one turn.
    def record_tool_usage(call, result)
      return unless @agent.respond_to?(:memory) && @agent.memory

      @tool_usage_lock.synchronize do
        @agent.memory.add_tool_usage(call[:name], call[:arguments], result)
      end
    end

    def emit(klass, iteration:, **attrs)
      type_sym = klass.name.split('::').last
                      .gsub(/([A-Z])/) { "_#{Regexp.last_match(1).downcase}" }
                      .sub(/^_/, '').to_sym
      Events.emit(@sink, klass.new(
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
      event.parent_id ||= Events.current_parent
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
