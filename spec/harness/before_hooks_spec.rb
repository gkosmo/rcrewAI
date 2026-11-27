# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/harness_helpers'

# Before hooks run after the rules and before approval. Whatever goes wrong in
# one, the call must not run.
RSpec.describe 'harness before hooks' do
  let(:spy) { HarnessSpyTool.new }
  let(:task) { RCrewAI::Task.new(name: 't', description: 'do it', expected_output: 'x') }
  let(:events) { [] }

  around do |example|
    original = $stdin
    $stdin = StringIO.new # not a terminal: nobody can answer
    example.run
    $stdin = original
  end

  def native_turn(*calls, name: 'spy_writer')
    { content: nil,
      tool_calls: calls.each_with_index.map { |args, i| { id: "call_#{i}", name: name, arguments: args } },
      finish_reason: :tool_calls, usage: {} }
  end

  def legacy_turn(args)
    params = args.map { |key, value| "#{key}=#{value}" }.join(', ')
    { content: "USE_TOOL[spy_writer](#{params})", tool_calls: [], finish_reason: :length, usage: {} }
  end

  # Runs one agent turn with the given calls and returns what the model was
  # sent next.
  def run_calls(harness, *calls, native: true, tools: [spy], **options)
    turn = native ? native_turn(*calls) : legacy_turn(calls.first)
    llm = HarnessLLM.new(native: native, turns: [turn])
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: tools, llm: llm, harness: harness, **options)
    agent.execute_task(task, stream: ->(e) { events << e })
    llm.requests.last.map { |m| m[:content].to_s }.join("\n")
  end

  def allowing(**options, &hooks)
    RCrewAI::Harness.new(default: :allow, **options, &hooks)
  end

  def refused(sent)
    sent[/REFUSED: Tool 'spy_writer' was not run: .*/]
  end

  describe 'return values' do
    [true, nil].each do |value|
      it "runs the call when the hook returns #{value.inspect}" do
        run_calls(allowing { before(:spy_writer) { value } }, { 'path' => 'a.txt' })

        expect(spy.calls).to eq([{ path: 'a.txt' }])
      end
    end

    { 'native' => true, 'legacy' => false }.each do |runner, native|
      it "refuses with the returned string as the reason on the #{runner} runner" do
        sent = run_calls(allowing { before(:spy_writer) { 'Looks like a key.' } }, { 'path' => 'a.txt' },
                         native: native)

        expect(spy.calls).to be_empty
        expect(sent).to include("REFUSED: Tool 'spy_writer' was not run: Looks like a key.")
        blocked = events.grep(RCrewAI::Events::ToolBlocked)
        expect(blocked.map(&:to_h)).to contain_exactly(include(source: :hook, reason: 'Looks like a key.',
                                                               tool: 'spy_writer'))
        expect(events.grep(RCrewAI::Events::ToolHookFailed)).to be_empty
      end
    end

    { false => 'FalseClass', ok: 'Symbol' }.each do |value, class_name|
      it "refuses, naming the hook and what it returned, when it returns #{value.inspect}" do
        sent = run_calls(allowing { before(:spy_writer) { value } }, { 'path' => 'a.txt' })

        expect(spy.calls).to be_empty
        expect(refused(sent)).to include('before(spy_writer) #1', 'returned', class_name)
      end
    end

    # Review focus 4: a logging hook whose last expression is `seen << call`.
    it 'refuses, naming the hook and what it returned, when it returns an Array' do
      seen = []
      sent = run_calls(allowing { before(:spy_writer) { |call| seen << call } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
      expect(refused(sent)).to include('before(spy_writer) #1', 'returned', 'Array')
    end

    it 'refuses when the hook returns an object that claims to be nil or true' do
      impostor = Class.new(BasicObject) do
        def nil?
          true
        end

        def ==(_other)
          true
        end
      end.new
      sent = run_calls(allowing { before { impostor } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
      expect(refused(sent)).to include('before(*) #1', 'returned')
    end

    it 'gives a reason when the hook returns an empty string' do
      sent = run_calls(allowing { before(:spy_writer) { '' } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
      expect(refused(sent)).to include('before(spy_writer) #1')
    end
  end

  describe 'failures' do
    it 'refuses when the hook raises, naming the hook and the error class' do
      sent = run_calls(allowing { before(:spy_writer) { raise 'secret detail' } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
      expect(refused(sent)).to include('before(spy_writer) #1', 'RuntimeError')
      failed = events.grep(RCrewAI::Events::ToolHookFailed)
      expect(failed.length).to eq(1)
      expect(failed.first.to_h).to include(type: :tool_hook_failed, tool: 'spy_writer', call_id: 'call_0',
                                           hook: 'before(spy_writer) #1', phase: :before)
      expect(failed.first.error).to include('RuntimeError', 'secret detail')
      expect(events.grep(RCrewAI::Events::ToolBlocked).map(&:source)).to eq([:hook])
    end

    it 'refuses when the hook hangs past hook_timeout' do
      sent = run_calls(allowing(hook_timeout: 0.05) { before(:spy_writer) { sleep } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
      expect(refused(sent)).to include('before(spy_writer) #1', 'timed out')
      expect(events.grep(RCrewAI::Events::ToolHookFailed).map(&:phase)).to eq([:before])
    end

    it 'refuses when the hook raises something that is not a StandardError' do
      run_calls(allowing { before(:spy_writer) { raise NotImplementedError } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
    end

    {
      'calls exit' => -> { exit },
      'overflows the stack' => lambda do
        recurse = ->(n) { recurse.call(n + 1) }
        recurse.call(0)
      end,
      'throws' => -> { throw :done, true },
      'kills its own thread' => -> { Thread.current.kill },
      'exits its own thread' => -> { Thread.exit }
    }.each do |what, body|
      it "refuses when the hook #{what}" do
        sent = run_calls(allowing { before(:spy_writer) { body.call } }, { 'path' => 'a.txt' })

        expect(spy.calls).to be_empty
        expect(refused(sent)).to include('before(spy_writer) #1')
        expect(events.grep(RCrewAI::Events::ToolHookFailed).length).to eq(1)
      end
    end

    # break and return in a block whose method has returned are LocalJumpErrors.
    it 'refuses when the hook uses break' do
      run_calls(allowing { before(:spy_writer) { break true } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
    end

    it 'lets next return the value of the hook' do
      run_calls(allowing { before(:spy_writer) { next false } }, { 'path' => 'a.txt' })
      expect(spy.calls).to be_empty

      run_calls(allowing { before(:spy_writer) { next true } }, { 'path' => 'b.txt' })
      expect(spy.calls).to eq([{ path: 'b.txt' }])
    end

    it 'refuses when describing what a hook raised raises too' do
      nasty = Class.new(StandardError) do
        def message
          raise 'no message for you'
        end
      end
      run_calls(allowing { before(:spy_writer) { raise nasty } }, { 'path' => 'a.txt' })

      expect(spy.calls).to be_empty
    end

    # A hook that calls a tool on its own harness would wait for the lock its
    # caller holds. The inner call is refused at once rather than deadlocking.
    it 'refuses a tool call made from inside a hook on the same harness, without waiting for the timeout' do
      other = HarnessSpyTool.new
      inner = nil
      harness = allowing(hook_timeout: 30) do
        same_harness = Struct.new(:name, :harness).new('a', self)
        before(:spy_writer) do
          inner = RCrewAI::ToolExecution.new(agent: same_harness).call(other, { 'path' => 'x' })
          true
        rescue RCrewAI::ToolApproval::Refused => e
          inner = e
          true
        end
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_calls(harness, { 'path' => 'a.txt' })

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10
      expect(other.calls).to be_empty
      expect(inner).to be_a(RCrewAI::Harness::Blocked)
      expect(inner.message).to include("can't make tool calls")
      expect(spy.calls).to eq([{ path: 'a.txt' }])
    end
  end

  describe 'which hooks run' do
    it 'runs hooks in declaration order and stops at the first refusal' do
      ran = []
      harness = allowing do
        before(:spy_writer) { ran << 1 and nil }
        before { ran << 2 and 'Second says no.' }
        before(:spy_writer) { ran << 3 and nil }
      end
      sent = run_calls(harness, { 'path' => 'a.txt' })

      expect(ran).to eq([1, 2])
      expect(refused(sent)).to include('Second says no.')
      expect(spy.calls).to be_empty
    end

    it 'runs only the hooks for the tool being called, and nameless hooks for every tool' do
      ran = []
      harness = allowing do
        before(:other_tool) { ran << :other and 'No.' }
        before { |call| ran << call.tool_name and nil }
      end
      run_calls(harness, { 'path' => 'a.txt' })

      expect(ran).to eq(['spy_writer'])
      expect(spy.calls).to eq([{ path: 'a.txt' }])
    end

    it 'runs no hooks for a call a rule blocks' do
      ran = []
      harness = allowing do
        block :spy_writer
        before { ran << :hook and nil }
      end
      run_calls(harness, { 'path' => 'a.txt' })

      expect(ran).to be_empty
      expect(events.grep(RCrewAI::Events::ToolBlocked).map(&:source)).to eq([:rule])
    end

    it 'never asks the approval handler about a call a hook refused' do
      asked = []
      harness = RCrewAI::Harness.new(default: :ask) { before { 'No.' } }
      run_calls(harness, { 'path' => 'a.txt' }, approval_handler: ->(request) { asked << request })

      expect(asked).to be_empty
      expect(spy.calls).to be_empty
    end

    it 'asks the approval handler after the hooks pass' do
      order = []
      harness = RCrewAI::Harness.new(default: :ask) { before { order << :hook and nil } }
      run_calls(harness, { 'path' => 'a.txt' }, approval_handler: ->(_request) { order << :asked and true })

      expect(order).to eq(%i[hook asked])
      expect(spy.calls).to eq([{ path: 'a.txt' }])
    end
  end

  describe 'what a hook sees' do
    it 'gets frozen, string-keyed, coerced arguments' do
      seen = nil
      run_calls(allowing { before { |call| (seen = call) and nil } }, { path: 7, 'body' => 'hi' })

      expect(seen.tool_name).to eq('spy_writer')
      expect(seen.call_id).to eq('call_0')
      expect(seen.agent).to eq('a')
      expect(seen.args).to eq('path' => '7', 'body' => 'hi')
      expect(seen.args).to be_frozen
      expect(seen.args.keys).to all(be_frozen)
      expect(seen.args.values).to all(be_frozen)
      expect(seen).to be_frozen
    end
  end

  # Review focus 5: calls queued behind a slow hook. Each hook takes well under
  # the timeout, but all three together take longer than it, so a timer that
  # counted the wait for the lock would time the last one out.
  it 'runs hooks of parallel calls one at a time, without counting the wait against the timeout' do
    active = 0
    overlapped = false
    lock = Mutex.new
    harness = allowing(hook_timeout: 0.7) do
      before do
        lock.synchronize do
          active += 1
          overlapped ||= active > 1
        end
        sleep 0.3
        lock.synchronize { active -= 1 }
        nil
      end
    end
    run_calls(harness, { 'path' => 'a' }, { 'path' => 'b' }, { 'path' => 'c' })

    expect(spy.calls.map { |c| c[:path] }).to contain_exactly('a', 'b', 'c')
    expect(overlapped).to be(false)
  end

  describe 'declaring hooks' do
    it 'needs a block' do
      expect { RCrewAI::Harness.new { before(:spy_writer) } }.to raise_error(ArgumentError, /block/)
    end

    it 'rejects a tool name that is not a Symbol or String' do
      expect { RCrewAI::Harness.new { before(5) { true } } }.to raise_error(ArgumentError, /tool name/)
    end

    it 'rejects a hook_timeout that is not a positive number' do
      [nil, 0, -1, '5'].each do |timeout|
        expect { RCrewAI::Harness.new(hook_timeout: timeout) }.to raise_error(ArgumentError, /hook_timeout/)
      end
    end

    it 'warns about hooks for tools the agent does not have (not run through an agent)' do
      harness = RCrewAI::Harness.new do
        before(:spy_writr) { true }
        before { true }
      end
      warnings = harness.validate_tools([spy])

      expect(warnings.length).to eq(1)
      expect(warnings.first).to include('before', 'spy_writr')
    end
  end

  it 'checks hooks directly with check_before (not run through an agent)' do
    harness = RCrewAI::Harness.new { before(:w) { |call| call.args['x'] == 1 ? 'No ones.' : nil } }
    call = ->(args) { RCrewAI::Harness::Call.new(tool_name: 'w', args: args, agent: 'a', call_id: nil) }

    expect(harness.check_before(call.call({ 'x' => 2 }))).to be_nil
    refusal = harness.check_before(call.call({ 'x' => 1 }))
    expect(refusal.to_h).to eq(reason: 'No ones.', hook: 'before(w) #1', error: nil)
  end
end

# A killed thread still runs its ensure blocks, so a timed-out hook can keep
# running after the kill. These are checked directly, not through an agent.
RSpec.describe 'a harness before hook that keeps running after it timed out' do
  def w_call(args)
    RCrewAI::Harness::Call.new(tool_name: 'w', args: args, agent: 'a', call_id: nil)
  end

  let(:tracker) do
    Struct.new(:active, :overlapped, :entered, :lock) do
      def enter
        lock.synchronize do
          self.active += 1
          self.entered += 1
          self.overlapped ||= active > 1
        end
      end

      def leave
        lock.synchronize { self.active -= 1 }
      end
    end.new(0, false, 0, Mutex.new)
  end

  it 'waits for its cleanup before the next hook runs' do
    seen = tracker
    harness = RCrewAI::Harness.new(hook_timeout: 0.5) do
      before(:w) do |call|
        seen.enter
        sleep if call.args['hang']
        nil
      ensure
        sleep 0.1 if call.args['hang'] # cleanup, well within another timeout
        seen.leave
      end
    end

    expect(harness.check_before(w_call({ 'hang' => true })).reason).to include('timed out')
    expect(harness.check_before(w_call({}))).to be_nil
    expect(seen.overlapped).to be(false)
  end

  it 'refuses calls that need hooks, without running them, until it stops' do
    seen = tracker
    release = Queue.new
    stuck = nil
    harness = RCrewAI::Harness.new(hook_timeout: 0.2) do
      before(:w) do |call|
        seen.enter
        if call.args['hang']
          stuck = Thread.current
          sleep
        end
        nil
      ensure
        release.pop if call.args['hang'] # cleanup that outlives any bound
        seen.leave
      end
    end

    expect(harness.check_before(w_call({ 'hang' => true })).reason).to include('timed out')
    refusal = harness.check_before(w_call({}))
    expect(refusal.reason).to include('before(w) #1', 'still running')
    expect(seen.entered).to eq(1)
    expect(harness.check_before(RCrewAI::Harness::Call.new(tool_name: 'other', args: {}))).to be_nil

    release << :go
    stuck.join(10)
    expect(harness.check_before(w_call({}))).to be_nil
    expect(seen.entered).to eq(2)
    expect(seen.overlapped).to be(false)
  end
end
