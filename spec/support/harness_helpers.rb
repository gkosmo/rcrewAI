# frozen_string_literal: true

# Records the keyword arguments of every call. Thread-safe because parallel tool
# calls share it.
class HarnessSpyTool < RCrewAI::Tools::Base
  tool_name 'spy_writer'
  description 'records what it was asked to write'
  param :path, type: :string, required: true
  param :body, type: :string

  def initialize
    super
    @calls = []
    @lock = Mutex.new
  end

  def calls
    @lock.synchronize { @calls.dup }
  end

  def execute(**kwargs)
    @lock.synchronize { @calls << kwargs }
    "wrote #{kwargs[:path]}"
  end
end

# Replays scripted turns and remembers the messages of each request, then
# answers FINAL_ANSWER[all done].
class HarnessLLM
  attr_reader :requests

  def initialize(native:, turns:)
    @native = native
    @turns = turns.dup
    @requests = []
    @lock = Mutex.new
  end

  def supports_native_tools?(**)
    @native
  end

  def chat(messages:, **)
    @lock.synchronize do
      @requests << messages.map(&:dup)
      @turns.shift || { content: 'FINAL_ANSWER[all done]', tool_calls: [], finish_reason: :stop, usage: {} }
    end
  end
end
