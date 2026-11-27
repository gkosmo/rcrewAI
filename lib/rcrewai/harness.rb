# frozen_string_literal: true

require_relative 'tool_approval'
require_relative 'harness/rule'
require_relative 'harness/hooks'

module RCrewAI
  # Rules for an agent's tool calls.
  #
  #   harness = RCrewAI::Harness.new(default: :ask) do
  #     allow :file_reader, :file_writer
  #     block :file_writer, matching: { file_path: /\.env\z/ }, reason: 'Secrets are read-only.'
  #     before(:file_writer) { |call| call.args['content'].include?('AKIA') ? 'Looks like a key.' : true }
  #     after(:file_writer)  { |call| Lint.run(call.args['file_path']) }
  #   end
  #
  # Among the rules that apply to a call the strictest wins: block, then ask, then
  # allow. The order they're declared in doesn't change the outcome. With no
  # applicable rule the outcome is +default+.
  #
  # Before hooks run, in declaration order, for calls the rules didn't block,
  # and before anyone is asked for approval. Only true or nil let the call run.
  # After hooks run once the tool has, and can only add notes for the model.
  #
  # Rules see only a tool's name and arguments. They aren't a sandbox.
  class Harness
    OUTCOMES = %i[allow ask block].freeze

    Decision = Struct.new(:outcome, :reason, keyword_init: true)

    # Raised instead of running a call the harness stopped. A Refused, so every
    # runner already turns it into a tool result and the run carries on.
    class Blocked < ToolApproval::Refused
      def initialize(tool_name, reason)
        super(tool_name, reason, "Tool '#{tool_name}' was not run: #{reason}")
      end

      def model_message
        "REFUSED: #{message}"
      end
    end

    attr_reader :default, :hook_timeout

    def initialize(default: :ask, hook_timeout: 60, &definition)
      raise ArgumentError, "default: must be :allow, :ask or :block, got #{default.inspect}" unless OUTCOMES.include?(default)
      # Without a limit a hook that hangs would hang the run.
      raise ArgumentError, "hook_timeout: must be a positive number of seconds, got #{hook_timeout.inspect}" unless hook_timeout.is_a?(Numeric) && hook_timeout.real? && hook_timeout.positive?

      @default = default
      @hook_timeout = hook_timeout
      @rules = []
      @hooks = Hooks.new(timeout: hook_timeout)
      instance_eval(&definition) if definition
    end

    # if: is the public keyword, and Ruby reserves the word, hence
    # local_variable_get.
    # rubocop:disable Naming/MethodParameterName
    def allow(*tools, matching: nil, if: nil, &ignored)
      add_rule(:allow, tools, ignored, matching: matching, condition: binding.local_variable_get(:if))
    end

    def ask(*tools, matching: nil, if: nil, &ignored)
      add_rule(:ask, tools, ignored, matching: matching, condition: binding.local_variable_get(:if))
    end

    def block(*tools, matching: nil, if: nil, reason: nil, &ignored)
      add_rule(:block, tools, ignored, matching: matching, condition: binding.local_variable_get(:if),
                                       reason: reason || 'Blocked by the harness')
    end
    # rubocop:enable Naming/MethodParameterName

    # Runs the block before each call to the named tools (every tool when none
    # is named) that the rules let through. It gets a Harness::Call and lets
    # the call run only by returning true or nil. A String refuses the call
    # with that reason; any other value, an exception or a timeout refuses it
    # too. Hooks on one harness run one at a time.
    def before(*tools, &hook)
      @hooks.add(:before, tools, hook)
      self
    end

    # Runs the block after each call to the named tools (every tool when none
    # is named) that ran, whether the tool returned or raised. It gets a
    # Harness::Call with +result+ or +error+ set. A String it returns is
    # appended to what the model reads, after the result or error; other
    # values are ignored. A hook that raises or times out can't undo the call:
    # the result stands and the model is told the hook failed. Before and
    # after hooks on one harness run one at a time, and a hook can't make tool
    # calls through its own harness (they're refused).
    def after(*tools, &hook)
      @hooks.add(:after, tools, hook)
      self
    end

    # Returns a Hooks::Refusal from the first before hook that refuses +call+,
    # or nil when they all pass.
    def check_before(call)
      @hooks.check_before(call)
    end

    # Runs the after hooks for +call+ and returns their Hooks::Notes, in
    # declaration order.
    def run_after(call)
      @hooks.run_after(call)
    end

    # Rules and their conditions get a frozen, string-keyed copy of +args+, so
    # they can't change what later rules see. Anything that stops a rule from
    # being checked blocks the call.
    def decide(tool_name, args)
      checked = snapshot(args.nil? ? {} : args.to_hash)
      applicable = @rules.select { |rule| rule.applies?(tool_name.to_s, checked) }
      strictest(applicable)
    # SystemStackError isn't a StandardError: a condition that recurses too deep
    # still blocks rather than escaping the check.
    rescue StandardError, ScriptError, SystemStackError => e
      Decision.new(outcome: :block, reason: "A rule condition failed (#{e.class}), so the call was not checked")
    end

    # Checks the rules and hooks against the tools an agent has. Returns a
    # warning for each name that matches none of them. Raises ArgumentError
    # when +matching:+ names an argument a tool doesn't declare, since that
    # rule could never match.
    def validate_tools(tools)
      by_name = tools.group_by { |tool| tool.name.to_s }
      @rules.each { |rule| check_arguments!(rule, by_name) }

      named = { 'a rule' => @rules.flat_map(&:tool_names).uniq, 'a before hook' => @hooks.tool_names(:before),
                'an after hook' => @hooks.tool_names(:after) }
      named.flat_map do |what, names|
        (names - by_name.keys).map do |name|
          "The harness has #{what} for '#{name}', but the agent has no tool with that name " \
            "(its tools: #{by_name.keys.join(', ')})"
        end
      end
    end

    private

    def add_rule(effect, tools, ignored_block, **options)
      raise ArgumentError, "#{effect} doesn't take a block; pass a condition as if: ->(args) { ... }" if ignored_block

      @rules << Rule.new(effect, tools, **options)
      self
    end

    def strictest(rules)
      return Decision.new(outcome: @default, reason: default_reason) if rules.empty?

      blocking = rules.find { |rule| rule.effect == :block }
      return Decision.new(outcome: :block, reason: blocking.reason) if blocking

      Decision.new(outcome: rules.any? { |rule| rule.effect == :ask } ? :ask : :allow, reason: nil)
    end

    def default_reason
      'No rule allows this tool' if @default == :block
    end

    def snapshot(value)
      case value
      when Hash then snapshot_hash(value)
      when Array then value.map { |item| snapshot(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end

    def snapshot_hash(hash)
      hash.each_with_object({}) do |(key, value), copy|
        name = key.to_s.dup.freeze
        # Keeping either value would leave the other one unchecked.
        raise ArgumentError, "two arguments are named #{name}" if copy.key?(name)

        copy[name] = snapshot(value)
      end.freeze
    end

    def check_arguments!(rule, by_name)
      rule.tool_names.each do |name|
        by_name.fetch(name, []).each do |tool|
          declared = declared_params(tool)
          next if declared.empty?

          unknown = rule.matched_arguments - declared
          next if unknown.empty?

          raise ArgumentError, "matching: names '#{unknown.join("', '")}', which the tool '#{name}' doesn't " \
                               "declare (it declares: #{declared.join(', ')})"
        end
      end
    end

    def declared_params(tool)
      return [] unless tool.class.respond_to?(:params)

      tool.class.params.map { |param| param[:name].to_s }
    end
  end
end
