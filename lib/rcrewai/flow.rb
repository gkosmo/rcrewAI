# frozen_string_literal: true

require_relative 'flow/state'
require_relative 'flow/state_store'

module RCrewAI
  # Event-driven workflow engine — CrewAI's second pillar, in Ruby.
  #
  # Subclass Flow and declare methods with the class-level DSL:
  #
  #   class GuideFlow < RCrewAI::Flow
  #     start :pick_topic
  #     def pick_topic = state.topic = 'ruby'
  #
  #     listen :pick_topic
  #     def research(prev) = "researched #{prev}"
  #
  #     router :research
  #     def route(prev) = prev.include?('ruby') ? :publish : :revise
  #
  #     listen :publish
  #     def publish = state.done = true
  #   end
  #
  #   GuideFlow.new.kickoff
  #
  # Triggers combine with and_/or_. State is a schemaless object with a UUID and
  # can be persisted/restored via a state store.
  class Flow
    # --- Trigger descriptors -------------------------------------------------
    Trigger = Struct.new(:mode, :names) do
      def satisfied_by?(completed)
        case mode
        when :single, :or then names.any? { |n| completed.include?(n) }
        when :and then names.all? { |n| completed.include?(n) }
        end
      end
    end

    # --- Class-level DSL -----------------------------------------------------
    class << self
      def start_methods
        @start_methods ||= []
      end

      # name => Trigger. Populated when a listen/router declaration is bound to
      # the next defined method.
      def listeners
        @listeners ||= {}
      end

      def routers
        @routers ||= {}
      end

      def start(method_name)
        start_methods << method_name.to_sym
      end

      def listen(trigger)
        @pending = [:listen, normalize_trigger(trigger)]
      end

      def router(trigger)
        @pending = [:router, normalize_trigger(trigger)]
      end

      def or_(*names)
        Trigger.new(:or, names.map(&:to_sym))
      end

      def and_(*names)
        Trigger.new(:and, names.map(&:to_sym))
      end

      # Binds a pending listen/router declaration to the method just defined.
      def method_added(method_name)
        super
        return unless @pending

        kind, trigger = @pending
        @pending = nil
        case kind
        when :listen then listeners[method_name.to_sym] = trigger
        when :router then routers[method_name.to_sym] = trigger
        end
      end

      # Merge inherited declarations so subclasses of a Flow subclass compose.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@start_methods, start_methods.dup)
        subclass.instance_variable_set(:@listeners, listeners.dup)
        subclass.instance_variable_set(:@routers, routers.dup)
      end

      private

      def normalize_trigger(trigger)
        return trigger if trigger.is_a?(Trigger)

        Trigger.new(:single, [trigger.to_sym])
      end
    end

    # --- Instance ------------------------------------------------------------
    attr_reader :state

    def initialize(state_store: nil, feedback_handler: nil)
      @state = State.new
      @state_store = state_store
      @feedback_handler = feedback_handler
    end

    # A pause point for human feedback. Calls the configured feedback_handler
    # with the prompt and returns its response; without a handler, prompts on
    # the console. Mirrors CrewAI's @human_feedback.
    def human_feedback(prompt)
      return @feedback_handler.call(prompt) if @feedback_handler

      require_relative 'human_input'
      response = HumanInput.new.request_input(prompt)
      response.is_a?(Hash) ? response[:input] : response
    end

    # Runs the flow to completion. Optional inputs seed the state.
    def kickoff(inputs: {})
      inputs.each { |k, v| @state[k] = v }

      @completed = []       # method names that have finished
      @outputs = {}         # method name => return value
      @router_labels = []   # labels emitted by routers, act as pseudo-triggers

      self.class.start_methods.each { |m| run_method(m) }
      drain_listeners

      persist
      @state
    end

    # Restores state previously persisted under +id+.
    def restore(id)
      raise FlowError, 'no state store configured' unless @state_store

      hash = @state_store.load(id)
      raise FlowError, "no persisted state for id #{id}" unless hash

      @state = State.new(symbolize(hash))
      @state
    end

    private

    def run_method(method_name)
      trigger = self.class.listeners[method_name] || self.class.routers[method_name]
      arg = trigger ? @outputs[last_trigger_name(trigger)] : nil

      result = arity_for(method_name).zero? ? send(method_name) : send(method_name, arg)

      @completed << method_name
      @outputs[method_name] = result

      # A router's return value becomes a label that listeners can trigger on.
      @router_labels << result.to_sym if self.class.routers.key?(method_name) && result
    end

    # Repeatedly fire any listeners/routers whose triggers are now satisfied,
    # until no new method runs (fixed point).
    def drain_listeners
      reactive = self.class.listeners.merge(self.class.routers)
      loop do
        ran = false
        reactive.each do |method_name, trigger|
          next if fired_enough?(method_name, trigger)

          if trigger.satisfied_by?(satisfied_set)
            run_listener(method_name, trigger)
            ran = true
          end
        end
        break unless ran
      end
    end

    # For :single/:or triggers we fire once per completed trigger name; for :and
    # we fire once. Track how many times each listener has fired.
    def run_listener(method_name, trigger)
      @fired ||= Hash.new { |h, k| h[k] = [] }

      case trigger.mode
      when :and
        @fired[method_name] << :once
        invoke_listener(method_name, @outputs[trigger.names.last])
      else
        pending = trigger.names.select { |n| satisfied_set.include?(n) } - @fired[method_name]
        pending.each do |name|
          @fired[method_name] << name
          invoke_listener(method_name, @outputs[name])
        end
      end
    end

    def invoke_listener(method_name, arg)
      result = arity_for(method_name).zero? ? send(method_name) : send(method_name, arg)
      @completed << method_name
      @outputs[method_name] = result
      @router_labels << result.to_sym if self.class.routers.key?(method_name) && result
    end

    def fired_enough?(method_name, trigger)
      @fired ||= Hash.new { |h, k| h[k] = [] }
      case trigger.mode
      when :and then @fired[method_name].any?
      else (trigger.names & satisfied_set).all? { |n| @fired[method_name].include?(n) }
      end
    end

    # Names available to satisfy triggers: completed methods + router labels.
    def satisfied_set
      @completed + @router_labels
    end

    def last_trigger_name(trigger)
      (trigger.names & @completed).last || trigger.names.last
    end

    def arity_for(method_name)
      method(method_name).arity
    end

    def persist
      return unless @state_store

      @state_store.save(@state.id, @state.to_h)
    end

    def symbolize(hash)
      hash.transform_keys(&:to_sym)
    end
  end

  class FlowError < Error; end
end
