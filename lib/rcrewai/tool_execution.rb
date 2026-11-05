# frozen_string_literal: true

require_relative 'events'
require_relative 'tool_approval'

module RCrewAI
  # The one place a tool runs. Every path goes through #call, so none of them can
  # skip the approval check; spec/integration/tool_approval_spec.rb fails if lib/
  # gains another call to a tool's #execute.
  class ToolExecution
    def initialize(agent:, event_sink: nil)
      @agent = agent
      @sink = event_sink
    end

    # Runs the tool and returns its result, or raises ToolApproval::Refused
    # without running it. +coerce: false+ passes arguments through unchecked, for
    # callers that don't go through the tool's parameter schema.
    def call(tool, arguments, call_id: nil, iteration: nil, coerce: true)
      arguments ||= {}
      authorize!(tool, arguments, call_id, iteration)
      coerce ? tool.execute_with_validation(arguments) : tool.execute(**arguments)
    end

    private

    def authorize!(tool, arguments, call_id, iteration)
      return unless @agent.respond_to?(:require_approval_for_tools?) && @agent.require_approval_for_tools?

      details = { tool: tool.name, args: arguments, call_id: call_id, iteration: iteration }
      emit(Events::ToolApprovalRequested, :tool_approval_requested, **details)
      decision = @agent.decide_tool_approval(
        ToolApproval::Request.new(tool_name: tool.name, arguments: frozen_copy(arguments), agent: @agent.name,
                                  call_id: call_id)
      )
      emit(Events::ToolApprovalDecided, :tool_approval_decided,
           approved: decision.approved?, reason: decision.reason, **details)
      raise ToolApproval::Refused.new(tool.name, decision.reason) unless decision.approved?
    end

    def frozen_copy(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s.freeze, frozen_copy(v)] }.freeze
      when Array then value.map { |v| frozen_copy(v) }.freeze
      when String then value.dup.freeze
      else value
      end
    end

    def emit(klass, type, iteration:, **attrs)
      Events.emit(@sink, klass.new(type: type, timestamp: Time.now, agent: @agent.name, iteration: iteration, **attrs))
    end
  end
end
