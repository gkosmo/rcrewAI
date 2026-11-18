# frozen_string_literal: true

module RCrewAI
  # What an agent with +require_approval_for_tools+ asks before a tool runs.
  #
  # A handler is anything with #call(request). It gets a Request and answers with
  # +true+, a Decision (ToolApproval.approve / ToolApproval.refuse(reason)) or a
  # hash with +approved:+ and +reason:+. Only an explicit yes counts: any other
  # value, an exception or running out of time is a refusal.
  #
  #   agent = RCrewAI::Agent.new(
  #     ...,
  #     require_approval_for_tools: true,
  #     approval_handler: lambda do |request|
  #       ApprovalRequest.ask(request.tool_name, request.arguments) # your own UI
  #     end
  #   )
  #
  # Calls to one agent's handler are made one at a time, including parallel tool
  # calls, so a handler needn't be thread-safe. It runs on its own thread, so it
  # shouldn't rely on thread-locals of the caller.
  module ToolApproval
    # +arguments+ has string keys on every runner and is frozen, because what was
    # approved is what runs.
    Request = Struct.new(:tool_name, :arguments, :agent, :call_id, :timeout, keyword_init: true)

    Decision = Struct.new(:approved, :reason, keyword_init: true) do
      def approved?
        approved == true
      end
    end

    # Raised instead of running a tool. Runners turn it into a tool result, so
    # the model finds out and the run carries on.
    class Refused < RCrewAI::Error
      attr_reader :tool_name, :reason

      def initialize(tool_name, reason)
        @tool_name = tool_name
        @reason = reason
        super("Tool '#{tool_name}' was not run because approval was refused: #{reason}")
      end
    end

    DEFAULT_TIMEOUT = 60

    def self.approve(reason = nil)
      Decision.new(approved: true, reason: reason || 'Approved')
    end

    def self.refuse(reason = nil)
      Decision.new(approved: false, reason: reason || 'Refused')
    end

    # Anything other than an explicit yes is a refusal, so "yes" and 1 are too.
    def self.decision_from(answer)
      case answer
      when Decision then answer.approved? ? answer : refuse(answer.reason)
      when true then approve
      when Hash
        reason = answer[:reason] || answer['reason']
        (answer[:approved] || answer['approved']) == true ? approve(reason) : refuse(reason)
      else refuse('The approval handler did not answer yes')
      end
    end

    # The default handler: asks at the terminal, or refuses if there isn't one.
    class TerminalHandler
      # Agents running side by side share one terminal.
      LOCK = Mutex.new

      # A little under the caller's limit, so this stops reading stdin before the
      # caller gives up on it and no stray reader is left behind.
      MARGIN = 0.5

      def initialize(agent)
        @agent = agent
      end

      def call(request)
        return ToolApproval.refuse('No approval handler is configured and there is no terminal to ask') unless $stdin.tty?

        LOCK.synchronize do
          answer = @agent.request_human_approval(
            "Agent #{request.agent} wants to use tool '#{request.tool_name}'",
            context: "Parameters: #{request.arguments.inspect}",
            consequences: "This will execute the #{request.tool_name} tool with the specified parameters.",
            timeout: [request.timeout - MARGIN, MARGIN].max
          )
          answer[:approved] == true ? ToolApproval.approve(answer[:reason]) : ToolApproval.refuse(answer[:reason])
        end
      end
    end
  end
end
