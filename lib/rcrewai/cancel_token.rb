# frozen_string_literal: true

module RCrewAI
  # Raised inside a streaming call when its CancelToken is triggered.
  class StreamCancelled < Error; end

  # Cooperative cancellation for a streaming LLM call. Pass it as
  # `cancel:` to a client's #chat; calling #cancel! (from the stream sink,
  # another thread, or another fiber) aborts the stream at the next chunk,
  # closes the connection and raises StreamCancelled in the caller.
  #
  # Under an Async reactor, stopping the calling task has the same effect.
  class CancelToken
    def initialize
      @cancelled = false
    end

    def cancel!
      @cancelled = true
    end

    def cancelled?
      @cancelled
    end
  end
end
