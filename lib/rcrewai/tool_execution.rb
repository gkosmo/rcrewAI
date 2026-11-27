# frozen_string_literal: true

require_relative 'events'
require_relative 'tool_approval'
require_relative 'harness'
require_relative 'tools/base'

module RCrewAI
  # The one place a tool runs. Every path goes through #call, so none of them can
  # skip the approval check or the agent's harness; spec/integration/
  # tool_approval_spec.rb fails if lib/ gains another call to a tool's #execute.
  class ToolExecution
    def initialize(agent:, event_sink: nil)
      @agent = agent
      @sink = event_sink
    end

    # Runs the tool and returns its result, or raises ToolApproval::Refused
    # (Harness::Blocked for a call the harness stopped) without running it.
    # +coerce: false+ passes arguments through unchecked, for callers that don't
    # go through the tool's parameter schema. Agents with a harness ignore it:
    # see #call_with_harness.
    def call(tool, arguments, call_id: nil, iteration: nil, coerce: true)
      arguments ||= {}
      harness = @agent.harness if @agent.respond_to?(:harness)
      return call_with_harness(harness, tool, arguments, call_id, iteration) if harness

      authorize!(tool, arguments, call_id, iteration) if approval_required?
      coerce ? tool.execute_with_validation(arguments) : tool.execute(**arguments)
    end

    private

    # Prepares the arguments once and freezes a copy of them. The rules, the
    # approval handler and the tool all get that copy, so what was checked is
    # what runs. A tool that overrides execute_with_validation (or has none)
    # isn't prepared: it gets its arguments exactly as supplied.
    def call_with_harness(harness, tool, arguments, call_id, iteration)
      prepared = prepared?(tool)
      checked = checked_copy(arguments)
      checked = checked_copy(tool.prepare_arguments(checked, reject_undeclared: true)) if prepared
      details = { call_id: call_id, iteration: iteration }

      outcome, reason = decide(harness, tool, checked)
      block!(tool, checked, reason, **details) unless %i[allow ask].include?(outcome)
      authorize!(tool, checked, call_id, iteration) if outcome == :ask || approval_required?

      run(tool, prepared, thawed(checked))
    end

    def approval_required?
      @agent.respond_to?(:require_approval_for_tools?) && @agent.require_approval_for_tools?
    end

    # Only the base execute_with_validation is known to be prepare_arguments
    # followed by execute. Object#method is bound directly because a tool may
    # define a #method of its own.
    def prepared?(tool)
      tool.is_a?(Tools::Base) &&
        Object.instance_method(:method).bind_call(tool, :execute_with_validation).owner == Tools::Base
    end

    # Anything that goes wrong while checking is a block.
    def decide(harness, tool, checked)
      decision = harness.decide(tool.name, checked)
      [decision.outcome, decision.reason || 'Blocked by the harness']
    rescue StandardError, ScriptError, SystemStackError => e
      [:block, "The harness failed (#{e.class}), so the call was not checked"]
    end

    def block!(tool, checked, reason, call_id:, iteration:)
      emit(Events::ToolBlocked, :tool_blocked, iteration: iteration,
                                               tool: tool.name, args: checked, call_id: call_id, reason: reason,
                                               source: :rule)
      raise Harness::Blocked.new(tool.name, reason)
    end

    def run(tool, prepared, arguments)
      if prepared || !tool.respond_to?(:execute_with_validation)
        tool.execute(**arguments.transform_keys(&:to_sym))
      else
        tool.execute_with_validation(arguments)
      end
    end

    def authorize!(tool, arguments, call_id, iteration)
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

    # A frozen, string-keyed deep copy. Two keys with the same name (:path and
    # 'path') are an error rather than one silently replacing the other.
    def checked_copy(arguments)
      raise Tools::ToolError, "arguments must be an object, got #{arguments.class}" unless arguments.is_a?(Hash)

      frozen_copy(arguments, distinct: true)
    rescue SystemStackError
      raise Tools::ToolError, 'the arguments are nested too deeply (or refer to themselves) to be checked'
    end

    def frozen_copy(value, distinct: false)
      case value
      when Hash then frozen_hash(value, distinct)
      when Array then value.map { |v| frozen_copy(v, distinct: distinct) }.freeze
      when String then value.dup.freeze
      else value
      end
    end

    def frozen_hash(hash, distinct)
      return hash.to_h { |k, v| [k.to_s.freeze, frozen_copy(v)] }.freeze unless distinct

      hash.each_with_object({}) do |(key, value), copy|
        name = key.to_s.dup.freeze
        raise Tools::ToolError, "two arguments are named #{name}" if copy.key?(name)

        copy[name] = frozen_copy(value, distinct: true)
      end.freeze
    end

    # A fresh unfrozen copy for the tool, so nothing it does reaches the checked
    # one.
    def thawed(value)
      case value
      when Hash then value.transform_values { |v| thawed(v) }
      when Array then value.map { |v| thawed(v) }
      when String then value.dup
      else value
      end
    end

    def emit(klass, type, iteration:, **attrs)
      Events.emit(@sink, klass.new(type: type, timestamp: Time.now, agent: @agent.name, iteration: iteration, **attrs))
    end
  end
end
