# frozen_string_literal: true

require 'securerandom'

module RCrewAI
  module Events
    # Every event carries its own :id and, when emitted inside a
    # +with_parent+ scope, the :parent_id of the enclosing span. Together these
    # turn a flat event stream into a tree that a subscriber can reassemble --
    # which is what tracing exporters need.
    BASE_ATTRS = %i[type timestamp agent iteration id parent_id].freeze

    Event           = Struct.new(*BASE_ATTRS, keyword_init: true)
    TextDelta       = Struct.new(*BASE_ATTRS, :text,                                  keyword_init: true)
    TextDone        = Struct.new(*BASE_ATTRS, :text,                                  keyword_init: true)
    ToolCallStart   = Struct.new(*BASE_ATTRS, :tool, :args, :call_id,                 keyword_init: true)
    ToolCallResult  = Struct.new(*BASE_ATTRS, :tool, :call_id, :result, :duration_ms, keyword_init: true)
    ToolCallError   = Struct.new(*BASE_ATTRS, :tool, :call_id, :error,                keyword_init: true)
    Thinking        = Struct.new(*BASE_ATTRS, :text,                                  keyword_init: true)
    Usage           = Struct.new(*BASE_ATTRS, :prompt_tokens, :completion_tokens, :total_tokens, :cost_usd, keyword_init: true)
    IterationStart  = Struct.new(*BASE_ATTRS, :iteration_index,                       keyword_init: true)
    IterationEnd    = Struct.new(*BASE_ATTRS, :finish_reason,                         keyword_init: true)
    Error           = Struct.new(*BASE_ATTRS, :error,                                 keyword_init: true)

    # Auto-assign an :id to any event that did not supply one. Struct's
    # keyword_init initializer is wrapped rather than replaced so every event
    # type gets this without restating the attribute list.
    [Event, TextDelta, TextDone, ToolCallStart, ToolCallResult, ToolCallError,
     Thinking, Usage, IterationStart, IterationEnd, Error].each do |klass|
      klass.prepend(Module.new do
        def initialize(**kwargs)
          kwargs[:id] ||= SecureRandom.uuid
          super(**kwargs)
        end
      end)
    end

    PARENT_KEY = :rcrewai_event_parent

    # Runs the block with +id+ as the parent span for any event emitted through
    # +emit+ on this thread. Scopes nest and are restored on exit, including
    # when the block raises. Thread-local: a child thread starts with no parent
    # rather than inheriting one, since it is a separate branch of work.
    def self.with_parent(id)
      previous = Thread.current[PARENT_KEY]
      Thread.current[PARENT_KEY] = id
      yield
    ensure
      Thread.current[PARENT_KEY] = previous
    end

    def self.current_parent
      Thread.current[PARENT_KEY]
    end

    # Stamps the enclosing parent span onto the event (unless it already names
    # one) and hands it to the sink.
    def self.emit(sink, event)
      return event if sink.nil?

      event.parent_id ||= current_parent
      sink.call(event)
      event
    end

    # Wraps one or more sinks in a single callable.
    #
    # Delivery is serialized: sinks are invoked under a mutex, so a sink shared
    # by concurrently executing agents is never entered from two threads at
    # once and does not need locking of its own. The lock is reentrant, so a
    # sink that emits back through the same fan-out does not deadlock.
    #
    # A sink that raises is reported and skipped -- one bad subscriber must not
    # take down the run or starve the others.
    def self.fan_out(sinks)
      sinks = Array(sinks).compact
      mutex = Mutex.new
      lambda do |event|
        if mutex.owned?
          deliver(sinks, event)
        else
          mutex.synchronize { deliver(sinks, event) }
        end
      end
    end

    def self.deliver(sinks, event)
      sinks.each do |s|
        s.call(event)
      rescue StandardError => e
        Kernel.warn "[rcrewai] event sink raised: #{e.class}: #{e.message}"
      end
    end
    private_class_method :deliver
  end
end
