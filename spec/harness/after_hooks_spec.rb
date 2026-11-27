# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/harness_helpers'

# After hooks run once the tool has. Whatever goes wrong in one, the call must
# not look failed (the model would repeat it) and its result must not be lost.
RSpec.describe 'harness after hooks' do
  let(:spy) { HarnessSpyTool.new }
  let(:task) { RCrewAI::Task.new(name: 't', description: 'do it', expected_output: 'x') }
  let(:events) { [] }
  let(:failing_tool) do
    Class.new(RCrewAI::Tools::Base) do
      tool_name 'spy_writer'
      description 'fails'
      param :path, type: :string, required: true

      def execute(**)
        raise RCrewAI::Tools::ToolError, 'disk full'
      end
    end.new
  end

  around do |example|
    original = $stdin
    $stdin = StringIO.new # not a terminal: nobody can answer
    example.run
    $stdin = original
  end

  def native_turn(*calls)
    { content: nil,
      tool_calls: calls.each_with_index.map { |args, i| { id: "call_#{i}", name: 'spy_writer', arguments: args } },
      finish_reason: :tool_calls, usage: {} }
  end

  def legacy_turn(args, content: nil, finish_reason: :length)
    params = args.map { |key, value| "#{key}=#{value}" }.join(', ')
    { content: content || "USE_TOOL[spy_writer](#{params})", tool_calls: [], finish_reason: finish_reason, usage: {} }
  end

  def build_agent(harness, llm, tools: [spy], **options)
    RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: tools, llm: llm, harness: harness, **options)
  end

  # Runs one agent turn with the given calls and returns what the model was
  # sent next. The task result is left in @result.
  def run_calls(harness, *calls, native: true, tools: [spy], **options)
    turn = native ? native_turn(*calls) : legacy_turn(calls.first)
    llm = HarnessLLM.new(native: native, turns: [turn])
    @result = build_agent(harness, llm, tools: tools, **options).execute_task(task, stream: ->(e) { events << e })
    llm.requests.last.map { |m| m[:content].to_s }.join("\n")
  end

  def allowing(**options, &hooks)
    RCrewAI::Harness.new(default: :allow, **options, &hooks)
  end

  def failed_note(label, what)
    "Note: the after hook #{label} failed (#{what}). The tool call itself was not undone."
  end

  { 'native' => true, 'legacy' => false }.each do |runner, native|
    context "on the #{runner} runner" do
      let(:shown) { native ? 'wrote a.rb' : 'Tool spy_writer result: wrote a.rb' }

      it 'shows the model what the hook returned, after the result, and records only the result' do
        sent = run_calls(allowing { after(:spy_writer) { 'lint: 2 offences' } }, { 'path' => 'a.rb' }, native: native)

        expect(sent).to include("#{shown}\nlint: 2 offences")
        expect(@result[:tool_calls_history].map { |h| h[:result] }).to eq(['wrote a.rb'])
        expect(events.grep(RCrewAI::Events::ToolCallResult).map(&:result)).to eq(['wrote a.rb'])
      end

      it 'adds nothing for a hook that returns something other than a String' do
        harness = allowing do
          [nil, true, false, :ok, ['x'], 42, ''].each { |value| after { value } }
        end
        sent = run_calls(harness, { 'path' => 'a.rb' }, native: native)

        expect(sent.lines.last).to eq(shown)
      end

      it 'keeps the result of a hook that raises, adds a note and runs the later hooks' do
        harness = allowing do
          after(:spy_writer) { raise 'secret detail' }
          after { 'second ran' }
        end
        sent = run_calls(harness, { 'path' => 'a.rb' }, native: native)

        expect(sent).to include("#{shown}\n#{failed_note('after(spy_writer) #1', 'RuntimeError')}\nsecond ran")
        expect(sent).not_to include('secret detail')
        expect(@result[:tool_calls_history].map { |h| h[:result] }).to eq(['wrote a.rb'])
        failed = events.grep(RCrewAI::Events::ToolHookFailed)
        expect(failed.map(&:to_h)).to contain_exactly(include(type: :tool_hook_failed, tool: 'spy_writer',
                                                              hook: 'after(spy_writer) #1', phase: :after))
        expect(failed.first.error).to include('RuntimeError', 'secret detail')
        expect(events.grep(RCrewAI::Events::ToolCallError)).to be_empty
        expect(events.grep(RCrewAI::Events::ToolBlocked)).to be_empty
      end

      it 'keeps the result of a hook that hangs past hook_timeout, adds a note and runs the later hooks' do
        harness = allowing(hook_timeout: 0.1) do
          after(:spy_writer) { sleep }
          after { 'second ran' }
        end
        sent = run_calls(harness, { 'path' => 'a.rb' }, native: native)

        expect(sent).to include("#{shown}\n#{failed_note('after(spy_writer) #1', 'timed out')}\nsecond ran")
        expect(@result[:tool_calls_history].map { |h| h[:result] }).to eq(['wrote a.rb'])
        expect(events.grep(RCrewAI::Events::ToolHookFailed).map(&:phase)).to eq([:after])
      end

      it 'shows the hook the error of a tool that raised, and the model the error followed by the note' do
        seen = nil
        harness = allowing do
          after do |call|
            seen = call
            'lint: skipped'
          end
        end
        sent = run_calls(harness, { 'path' => 'a.rb' }, native: native, tools: [failing_tool])

        expect(seen.error).to be_a(RCrewAI::Tools::ToolError)
        expect(seen.error.message).to eq('disk full')
        expect(seen.result).to be_nil
        error = native ? 'ERROR: disk full' : 'Tool spy_writer failed: disk full'
        expect(sent).to include("#{error}\nlint: skipped")
      end

      it 'runs no after hooks for a call a rule blocks or a before hook refuses' do
        ran = []
        run_calls(allowing do
          block :spy_writer
          after { ran << :blocked and nil }
        end, { 'path' => 'a.rb' }, native: native)
        run_calls(allowing do
          before { 'No.' }
          after { ran << :refused and nil }
        end, { 'path' => 'a.rb' }, native: native)

        expect(ran).to be_empty
        expect(spy.calls).to be_empty
      end

      it 'runs no after hooks for a call whose approval was refused' do
        ran = []
        harness = RCrewAI::Harness.new(default: :ask) { after { ran << :hook and nil } }
        run_calls(harness, { 'path' => 'a.rb' }, native: native, approval_handler: ->(_request) { false })

        expect(ran).to be_empty
        expect(spy.calls).to be_empty
      end
    end
  end

  # What the model was told about the tool call: the tool message (native) or
  # the user message with the tool results (legacy).
  def tool_text(llm, native)
    messages = llm.requests.last
    (native ? messages.find { |m| m[:role] == 'tool' } : messages.last)[:content]
  end

  { 'native' => true, 'legacy' => false }.each do |runner, native|
    context "with notes and results in other encodings, on the #{runner} runner" do
      def run_with(native, tool, note)
        llm = HarnessLLM.new(native: native, turns: [native ? native_turn({ 'path' => 'a.rb' }) : legacy_turn({ 'path' => 'a.rb' })])
        @result = build_agent(allowing { after { note } }, llm, tools: [tool]).execute_task(task, stream: ->(e) { events << e })
        llm
      end

      def expect_success(text, *parts)
        expect(text.encoding).to eq(Encoding::UTF_8)
        expect(text).to be_valid_encoding
        expect(text).to include(*parts)
        expect(events.grep(RCrewAI::Events::ToolCallError)).to be_empty
        expect(@result[:tool_calls_history].length).to eq(1)
      end

      {
        'a binary note with a non-ASCII result' => ['wrote café', "lint \xFF\xFE ok".b, ['wrote café', 'lint ', ' ok']],
        'a UTF-16LE note with an ASCII result' => ['wrote a.rb', 'lint: 2 offences'.encode('UTF-16LE'),
                                                   ['wrote a.rb', 'lint: 2 offences']],
        'an invalid UTF-8 note' => ['wrote café', (+"bad \xFF note").force_encoding('UTF-8'), ['wrote café', 'bad ', ' note']],
        'a binary result with a non-ASCII note' => ["data \xFF".b, 'naïve lint', ['data ', 'naïve lint']],
        'an ISO-8859-1 result with a non-ASCII note' => [
          'wrote café'.encode('ISO-8859-1'), 'naïve lint', ['wrote café', 'naïve lint']
        ]
      }.each do |what, (result, note, parts)|
        it "keeps the call a success and tells the model, for #{what}" do
          llm = run_with(native, HarnessReturningTool.new(result), note)

          expect_success(tool_text(llm, native), *parts)
        end
      end

      it 'tells the model the error and the note for a tool whose error message is UTF-16LE' do
        error = RCrewAI::Tools::ToolError.new('disk full'.encode('UTF-16LE'))
        llm = run_with(native, HarnessReturningTool.new(error: error), 'naïve lint')
        text = tool_text(llm, native)

        expect(text).to be_valid_encoding
        expect(text).to include('disk full', 'naïve lint')
      end
    end

    context "with a result a hook could change, on the #{runner} runner" do
      it 'gives the hook a frozen copy, so history and the event keep the raw result' do
        harness = allowing { after { |call| call.result['k'] = 'MUTATED' } }
        turn = native ? native_turn({ 'path' => 'a.rb' }) : legacy_turn({ 'path' => 'a.rb' })
        llm = HarnessLLM.new(native: native, turns: [turn])
        result = build_agent(harness, llm, tools: [HarnessReturningTool.new({ 'k' => 'v', 'list' => ['x'] })])
                 .execute_task(task, stream: ->(e) { events << e })
        sent = tool_text(llm, native)

        expect(result[:tool_calls_history].map { |h| h[:result] }).to eq([{ 'k' => 'v', 'list' => ['x'] }])
        expect(events.grep(RCrewAI::Events::ToolCallResult).map(&:result)).to eq([{ 'k' => 'v', 'list' => ['x'] }])
        expect(sent).to include(failed_note('after(*) #1', 'FrozenError'))
      end
    end
  end

  it 'gives the hook the frozen arguments and the result' do
    seen = nil
    run_calls(allowing { after { |call| (seen = call) and nil } }, { path: 7 })

    expect(seen.tool_name).to eq('spy_writer')
    expect(seen.call_id).to eq('call_0')
    expect(seen.args).to eq('path' => '7')
    expect(seen.args).to be_frozen
    expect(seen.result).to eq('wrote 7')
    expect(seen.result).to be_frozen
    expect(seen.error).to be_nil
    expect(seen).to be_frozen
  end

  it 'runs the notes of several hooks in declaration order' do
    harness = allowing do
      after { 'first' }
      after(:other_tool) { 'never' }
      after(:spy_writer) { 'second' }
    end
    sent = run_calls(harness, { 'path' => 'a.rb' })

    expect(sent).to include("wrote a.rb\nfirst\nsecond")
    expect(sent).not_to include('never')
  end

  it 'runs before and after hooks of parallel calls one at a time' do
    active = 0
    overlapped = false
    lock = Mutex.new
    body = lambda do
      lock.synchronize do
        active += 1
        overlapped ||= active > 1
      end
      sleep 0.05
      lock.synchronize { active -= 1 }
      nil
    end
    harness = allowing do
      before { body.call }
      after { body.call }
    end
    run_calls(harness, { 'path' => 'a' }, { 'path' => 'b' }, { 'path' => 'c' })

    expect(spy.calls.map { |c| c[:path] }).to contain_exactly('a', 'b', 'c')
    expect(overlapped).to be(false)
  end

  # A legacy turn that used a tool never ends the run, however much the hooks
  # add: the model must see the note before the run can finish.
  it 'ends a legacy turn whose after note is long only after the model has seen it' do
    note = "lint: #{'x' * 5000} end of lint"
    llm = HarnessLLM.new(native: false, turns: [
                           legacy_turn({}, content: "USE_TOOL[spy_writer](path=a.rb)\nFINAL_ANSWER[done early]",
                                           finish_reason: :stop)
                         ])
    result = build_agent(allowing { after { note } }, llm).execute_task(task)

    expect(llm.requests.length).to eq(2)
    expect(llm.requests.last.map { |m| m[:content].to_s }.join("\n"))
      .to include("Tool spy_writer result: wrote a.rb\n#{note}")
    expect(result[:content]).to eq('all done')
  end

  describe 'use_tool' do
    it 'returns the raw result and logs the notes' do
      agent = build_agent(allowing { after { 'lint: 2 offences' } }, HarnessLLM.new(native: true, turns: []))
      logger = agent.instance_variable_get(:@logger)
      allow(logger).to receive(:info)

      expect(agent.use_tool('spy_writer', path: 'a.rb')).to eq('wrote a.rb')
      expect(logger).to have_received(:info).with(include('lint: 2 offences'))
    end

    it 'logs the notes of a tool that raised, and raises as before' do
      agent = build_agent(allowing { after { 'lint: skipped' } }, HarnessLLM.new(native: true, turns: []),
                          tools: [failing_tool])
      logger = agent.instance_variable_get(:@logger)
      allow(logger).to receive(:info)

      expect { agent.use_tool('spy_writer', path: 'a.rb') }.to raise_error(RCrewAI::Tools::ToolError, 'disk full')
      expect(logger).to have_received(:info).with(include('lint: skipped'))
    end

    # A hook that calls a tool on its own harness would wait for the lock its
    # caller holds. The inner call is refused at once instead, and its refusal
    # becomes the hook's note.
    it 'refuses a tool call an after hook makes on its own harness, without deadlocking' do
      linter = Class.new(HarnessSpyTool) { tool_name 'linter' }.new
      agent = nil
      harness = allowing(hook_timeout: 30) { after(:spy_writer) { agent.use_tool('linter', path: 'a.rb') } }
      llm = HarnessLLM.new(native: true, turns: [native_turn({ 'path' => 'a.rb' })])
      agent = build_agent(harness, llm, tools: [spy, linter])
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      agent.execute_task(task)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10
      expect(linter.calls).to be_empty
      expect(spy.calls).to eq([{ path: 'a.rb' }])
      sent = llm.requests.last.map { |m| m[:content].to_s }.join("\n")
      expect(sent).to include("wrote a.rb\nREFUSED: Tool 'linter' was not run:", "can't make tool calls")
    end
  end

  describe 'ToolExecution#call' do
    it 'appends notes to the array it was given, including when the tool raised' do
      agent = Struct.new(:name, :harness).new('a', allowing { after { 'noted' } })
      execution = RCrewAI::ToolExecution.new(agent: agent)
      notes = ['earlier']

      expect(execution.call(spy, { 'path' => 'a.rb' }, notes: notes)).to eq('wrote a.rb')
      expect(notes).to eq(%w[earlier noted])

      notes = []
      expect { execution.call(failing_tool, { 'path' => 'a.rb' }, notes: notes) }
        .to raise_error(RCrewAI::Tools::ToolError)
      expect(notes).to eq(['noted'])
    end
  end

  it 'warns about after hooks for tools the agent does not have' do
    warnings = RCrewAI::Harness.new { after(:spy_writr) { nil } }.validate_tools([spy])

    expect(warnings.length).to eq(1)
    expect(warnings.first).to include('after hook', 'spy_writr')
  end

  it 'labels hooks by phase and position' do
    harness = RCrewAI::Harness.new do
      before { true }
      after { raise 'x' }
      after(:w, :v) { raise 'y' }
    end
    notes = harness.run_after(RCrewAI::Harness::Call.new(tool_name: 'w', args: {}))

    expect(notes.map(&:hook)).to eq(['after(*) #1', 'after(w, v) #2'])
    expect(notes.map(&:text)).to eq([failed_note('after(*) #1', 'RuntimeError'),
                                     failed_note('after(w, v) #2', 'RuntimeError')])
  end
end

# After hooks get a deep, frozen copy of the result, so they can't change what
# history, memory and events record. Checked directly, not through an agent.
RSpec.describe 'the result a harness after hook is given' do
  def seen_by_hook(value)
    seen = nil
    harness = RCrewAI::Harness.new(default: :allow) { after { |call| (seen = call.result) and nil } }
    agent = Struct.new(:name, :harness).new('a', harness)
    returned = RCrewAI::ToolExecution.new(agent: agent).call(HarnessReturningTool.new(value), { 'path' => 'a.rb' })
    [returned, seen]
  end

  it 'is a deep frozen copy, even of a structure that contains itself' do
    cyclic = [{ 'k' => +'v' }]
    cyclic << cyclic
    returned, seen = seen_by_hook(cyclic)

    expect(returned).to equal(cyclic)
    expect(returned).not_to be_frozen
    expect(seen).not_to equal(cyclic)
    expect(seen).to be_frozen
    expect(seen.first).to be_frozen
    expect(seen.first['k']).to be_frozen
    expect(seen.last).to equal(seen)
  end

  it 'is the text of a result that cannot be copied' do
    uncopyable = Struct.new(:callback).new(-> {})
    returned, seen = seen_by_hook(uncopyable)

    expect(returned).to equal(uncopyable)
    expect(seen).to eq(uncopyable.to_s)
    expect(seen).to be_frozen
  end

  it 'names the class of a result that can neither be copied nor turned into text' do
    hopeless = stub_const('HopelessResult', Class.new do
      def initialize
        @callback = -> {}
      end

      def to_s
        raise 'no text'
      end
    end).new
    returned, seen = seen_by_hook(hopeless)

    expect(returned).to equal(hopeless)
    expect(seen).to eq('(a result of class HopelessResult that could not be copied)')
    expect(seen).to be_frozen
  end
end

# A killed thread still runs its ensure blocks, so a timed-out hook can keep
# running after the kill. No other hook may run alongside it. Checked directly,
# not through an agent.
RSpec.describe 'a harness after hook while a timed-out hook keeps running' do
  def w_call(args = {})
    RCrewAI::Harness::Call.new(tool_name: 'w', args: args, agent: 'a', call_id: nil, result: 'done')
  end

  def failed_note(label, what)
    "Note: the after hook #{label} failed (#{what}). The tool call itself was not undone."
  end

  it 'reports later after hooks as failed without running them, and refuses before hooks, until it stops' do
    release = Queue.new
    stuck = nil
    entered = []
    harness = RCrewAI::Harness.new(hook_timeout: 0.2) do
      before(:w) { nil }
      after(:w) do |call|
        entered << :first
        if call.args['hang']
          stuck = Thread.current
          sleep
        end
        nil
      ensure
        release.pop if call.args['hang'] # cleanup that outlives any bound
      end
      after(:w) { (entered << :second) and 'second ran' }
    end

    notes = harness.run_after(w_call('hang' => true))
    expect(notes.map(&:text).first).to eq(failed_note('after(w) #1', 'timed out'))
    expect(notes.map(&:text).last).to include('after(w) #2', 'after(w) #1', 'still running')
    expect(notes.map(&:error)).to all(be_a(String))
    expect(entered).to eq([:first])

    expect(harness.run_after(w_call).map(&:text)).to all(include('still running'))
    expect(entered).to eq([:first])
    expect(harness.check_before(w_call).reason).to include('after(w) #1', 'still running')

    release << :go
    stuck.join(10)
    expect(harness.run_after(w_call).map(&:text)).to eq(['second ran'])
    expect(entered).to eq(%i[first first second])
  end

  it 'never overlaps a hook with a timed-out one that is still cleaning up' do
    active = 0
    overlapped = false
    lock = Mutex.new
    harness = RCrewAI::Harness.new(hook_timeout: 0.3) do
      after(:w) do |call|
        lock.synchronize do
          active += 1
          overlapped ||= active > 1
        end
        sleep if call.args['hang']
        nil
      ensure
        sleep 0.1 if call.args['hang'] # cleanup, well within another timeout
        lock.synchronize { active -= 1 }
      end
    end

    expect(harness.run_after(w_call('hang' => true)).map(&:text)).to eq([failed_note('after(w) #1', 'timed out')])
    expect(harness.run_after(w_call)).to eq([])
    expect(overlapped).to be(false)
  end
end
