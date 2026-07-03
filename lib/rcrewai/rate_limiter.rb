# frozen_string_literal: true

module RCrewAI
  # Thread-safe requests-per-minute throttle. Records call timestamps in a
  # rolling 60-second window; `acquire` blocks (sleeps) until a slot is free.
  #
  # The clock and sleeper are injectable so tests can drive time deterministically
  # without touching the wall clock. `max_rpm` of nil or 0 means unlimited.
  class RateLimiter
    WINDOW = 60.0

    def initialize(max_rpm:, clock: nil, sleeper: nil)
      @max_rpm = max_rpm
      @clock = clock || -> { current_time }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @calls = []
      @mutex = Mutex.new
    end

    # Blocks until making a call would keep us within max_rpm, then records it.
    def acquire
      return record_unlimited if unlimited?

      loop do
        wait = @mutex.synchronize do
          prune(@clock.call)
          if @calls.length < @max_rpm
            @calls << @clock.call
            return
          end
          # Time until the oldest in-window call ages out.
          (@calls.first + WINDOW) - @clock.call
        end

        @sleeper.call(wait) if wait.positive?
      end
    end

    # Number of calls currently inside the window (useful for tests/metrics).
    def recent_count
      @mutex.synchronize do
        prune(@clock.call)
        @calls.length
      end
    end

    private

    def unlimited?
      @max_rpm.nil? || @max_rpm.zero?
    end

    def record_unlimited
      @mutex.synchronize { @calls << @clock.call }
      nil
    end

    def prune(now)
      cutoff = now - WINDOW
      @calls.reject! { |t| t <= cutoff }
    end

    def current_time
      # Fully-qualified: bare `Process` would resolve to RCrewAI::Process here.
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    # Wraps an LLM client so every #chat acquires a rate-limiter slot first.
    # All other messages delegate to the wrapped client unchanged.
    class ThrottledClient
      def initialize(client, limiter)
        @client = client
        @limiter = limiter
      end

      def chat(**kwargs, &block)
        @limiter.acquire
        @client.chat(**kwargs, &block)
      end

      def respond_to_missing?(name, include_private = false)
        @client.respond_to?(name, include_private)
      end

      def method_missing(name, *args, **kwargs, &block)
        if @client.respond_to?(name)
          @client.public_send(name, *args, **kwargs, &block)
        else
          super
        end
      end
    end
  end
end
