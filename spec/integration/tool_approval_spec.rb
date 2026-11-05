# frozen_string_literal: true

require 'spec_helper'

# Records every call. Thread-safe because parallel tool calls share it.
class ApprovalSpyTool < RCrewAI::Tools::Base
  tool_name 'spy'
  description 'records that it ran'
  param :target, type: :string, required: true

  attr_reader :calls

  def initialize
    super
    @calls = []
    @lock = Mutex.new
  end

  def execute(target:)
    @lock.synchronize { @calls << target }
    "ran on #{target}"
  end
end

# Replays scripted responses and remembers what it was sent.
class ApprovalFakeLLM
  attr_reader :requests

  def initialize(responses, native:)
    @responses = responses
    @native = native
    @requests = []
  end

  def supports_native_tools?(**)
    @native
  end

  def chat(messages:, **)
    @requests << messages.map(&:dup)
    @responses.shift || { content: 'FINAL_ANSWER[all done]', tool_calls: [], finish_reason: :stop, usage: {} }
  end
end

# Full agent runs against a fake LLM, with a spy tool. What matters here is
# whether the tool ran and what the model was told.
RSpec.describe 'tool approval' do
  def native_call(*targets)
    { content: nil,
      tool_calls: targets.each_with_index.map do |target, i|
        { id: "call_#{i}", name: 'spy', arguments: { 'target' => target } }
      end,
      finish_reason: :tool_calls, usage: {} }
  end

  def legacy_call(target)
    { content: "USE_TOOL[spy](target=#{target})", tool_calls: [], finish_reason: :length, usage: {} }
  end

  let(:spy) { ApprovalSpyTool.new }
  let(:task) { RCrewAI::Task.new(name: 't', description: 'do it', expected_output: 'x') }

  def run_agent(llm, **agent_options)
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: llm, **agent_options)
    agent.execute_task(task)
    agent
  end

  around do |example|
    original = $stdin
    $stdin = StringIO.new # not a terminal: nobody can answer
    example.run
    $stdin = original
  end

  def tool_results_sent_to(llm)
    llm.requests.last.map { |m| m[:content].to_s }.join("\n")
  end

  { 'native' => { native: true, call: :native_call },
    'legacy' => { native: false, call: :legacy_call } }.each do |runner, setup|
    context "on the #{runner} runner" do
      define_method(:llm) do
        @llm ||= ApprovalFakeLLM.new([send(setup[:call], 'prod-db')], native: setup[:native])
      end

      it 'does not run the tool with no handler and no terminal' do
        run_agent(llm, human_input: true, require_approval_for_tools: true)

        expect(spy.calls).to be_empty
        expect(tool_results_sent_to(llm)).to match(/not run.*no terminal/m)
      end

      it 'does not run the tool even if human_input was never turned on' do
        run_agent(llm, require_approval_for_tools: true)

        expect(spy.calls).to be_empty
      end

      it 'runs the tool once when the handler approves' do
        run_agent(llm, require_approval_for_tools: true, approval_handler: ->(_) { true })

        expect(spy.calls).to eq(['prod-db'])
        expect(tool_results_sent_to(llm)).to include('ran on prod-db')
      end

      it 'gives the handler the tool name and arguments' do
        seen = nil
        run_agent(llm, require_approval_for_tools: true, approval_handler: lambda { |request|
          seen = request
          true
        })

        expect(seen.tool_name).to eq('spy')
        expect(seen.arguments).to eq('target' => 'prod-db')
        expect(seen.agent).to eq('a')
      end

      it 'tells the model when the handler refuses, with the reason, and finishes the run' do
        agent = run_agent(llm, require_approval_for_tools: true,
                               approval_handler: ->(_) { RCrewAI::ToolApproval.refuse('production is frozen') })

        expect(agent).to be_a(RCrewAI::Agent)
        expect(spy.calls).to be_empty
        expect(llm.requests.length).to eq(2)
        expect(tool_results_sent_to(llm)).to include('production is frozen')
        expect(task.result).to include('all done')
      end

      it 'treats a timeout as a refusal, and a late yes changes nothing' do
        run_agent(llm, require_approval_for_tools: true, approval_timeout: 0.05, approval_handler: lambda { |_|
          sleep 2
          true
        })

        expect(spy.calls).to be_empty
        expect(tool_results_sent_to(llm)).to include('No answer within 0.05 seconds')
      end

      it 'treats a handler that raises as a refusal, without crashing the run' do
        run_agent(llm, require_approval_for_tools: true, approval_handler: ->(_) { raise 'boom' })

        expect(spy.calls).to be_empty
        expect(tool_results_sent_to(llm)).to include('handler failed')
      end

      [false, nil, 'yes', 1, :approved, {}, { approved: 'true' }, { approved: nil }].each do |answer|
        it "treats a handler answer of #{answer.inspect} as a refusal" do
          run_agent(llm, require_approval_for_tools: true, approval_handler: ->(_) { answer })

          expect(spy.calls).to be_empty
        end
      end

      it 'stops a handler from changing the arguments that run' do
        run_agent(llm, require_approval_for_tools: true, approval_handler: lambda { |request|
          request.arguments['target'] << '-changed'
          true
        })

        expect(spy.calls).to be_empty
      end

      it 'asks the configured global handler' do
        RCrewAI.configuration.approval_handler = ->(_) { RCrewAI::ToolApproval.approve }
        run_agent(llm, require_approval_for_tools: true)

        expect(spy.calls).to eq(['prod-db'])
      ensure
        RCrewAI.configuration.approval_handler = nil
      end

      it 'prefers the agent handler to the global one' do
        RCrewAI.configuration.approval_handler = ->(_) { true }
        run_agent(llm, require_approval_for_tools: true, approval_handler: ->(_) { false })

        expect(spy.calls).to be_empty
      ensure
        RCrewAI.configuration.approval_handler = nil
      end

      it 'emits each decision as an event' do
        events = []
        agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: llm,
                                   require_approval_for_tools: true,
                                   approval_handler: ->(_) { RCrewAI::ToolApproval.refuse('nope') })
        agent.execute_task(task, stream: ->(e) { events << e })

        requested = events.grep(RCrewAI::Events::ToolApprovalRequested)
        decided = events.grep(RCrewAI::Events::ToolApprovalDecided)
        expect(requested.map(&:tool)).to eq(['spy'])
        expect(decided.map { |e| [e.tool, e.approved, e.reason, e.type] })
          .to eq([['spy', false, 'nope', :tool_approval_decided]])
        expect(decided.first.parent_id).not_to be_nil
        expect(events.grep(RCrewAI::Events::ToolCallResult)).to be_empty
        expect(events.grep(RCrewAI::Events::ToolCallError).map(&:tool)).to eq(['spy'])
      end

      it 'runs tools freely, without events, when approval is not required' do
        events = []
        agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: llm)
        agent.execute_task(task, stream: ->(e) { events << e })

        expect(spy.calls).to eq(['prod-db'])
        expect(events.grep(RCrewAI::Events::ToolApprovalDecided)).to be_empty
      end

      context 'at a terminal' do
        def answer(text)
          $stdin = StringIO.new("#{text}\n")
          $stdin.define_singleton_method(:tty?) { true }
        end

        it 'runs the tool when the person says yes' do
          answer('yes')
          run_agent(llm, require_approval_for_tools: true)

          expect(spy.calls).to eq(['prod-db'])
        end

        it 'does not run the tool when the person says deny' do
          answer('deny')
          run_agent(llm, require_approval_for_tools: true)

          expect(spy.calls).to be_empty
        end
      end

      it 'keeps requiring approval after a task with human_input ran on the agent' do
        agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: llm,
                                   human_input: true, require_approval_for_tools: true)
        allow(agent).to receive(:puts)
        human_task = RCrewAI::Task.new(name: 'h', description: 'do it', agent: agent, human_input: true)

        human_task.execute
        expect(spy.calls).to be_empty
        expect(agent.require_approval_for_tools?).to be true
      end
    end
  end

  it 'tells the model about a refusal on the legacy runner when the provider reports :stop, as real ones do' do
    stop_turn = legacy_call('prod-db').merge(finish_reason: :stop)
    llm = ApprovalFakeLLM.new([stop_turn], native: false)
    run_agent(llm, require_approval_for_tools: true, approval_handler: ->(_) { RCrewAI::ToolApproval.refuse('frozen') })

    expect(llm.requests.length).to eq(2)
    expect(tool_results_sent_to(llm)).to include('frozen')
  end

  describe 'parallel tool calls' do
    def llm_with_three
      ApprovalFakeLLM.new([native_call('a', 'b', 'c')], native: true)
    end

    it 'checks each call, and runs only those approved' do
      llm = llm_with_three
      asked = Queue.new
      run_agent(llm, require_approval_for_tools: true, approval_handler: lambda { |request|
        asked << request.arguments['target']
        request.arguments['target'] != 'b'
      })

      expect(Array.new(asked.size) { asked.pop }).to contain_exactly('a', 'b', 'c')
      expect(spy.calls).to contain_exactly('a', 'c')
      results = llm.requests.last.select { |m| m[:role] == 'tool' }
      expect(results.map { |m| m[:tool_call_id] }).to eq(%w[call_0 call_1 call_2])
      expect(results[1][:content]).to start_with('REFUSED:')
      expect(results[0][:content]).to eq('ran on a')
    end

    it 'runs none with no handler and no terminal' do
      run_agent(llm_with_three, require_approval_for_tools: true)

      expect(spy.calls).to be_empty
    end

    it 'asks the handler one call at a time' do
      inside = 0
      most = 0
      lock = Mutex.new
      run_agent(llm_with_three, require_approval_for_tools: true, approval_handler: lambda { |_|
        lock.synchronize { most = [most, inside += 1].max }
        sleep 0.02
        lock.synchronize { inside -= 1 }
        true
      })

      expect(most).to eq(1)
      expect(spy.calls.length).to eq(3)
    end
  end

  describe 'Agent#use_tool' do
    let(:agent) do
      RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: ApprovalFakeLLM.new([], native: true),
                         require_approval_for_tools: true, approval_handler: handler)
    end

    context 'when refused' do
      let(:handler) { ->(_) { RCrewAI::ToolApproval.refuse('nope') } }

      it 'does not run the tool and returns the refusal' do
        expect(agent.use_tool('spy', target: 'x')).to include('nope')
        expect(spy.calls).to be_empty
      end
    end

    context 'when approved' do
      let(:handler) { ->(_) { true } }

      it 'runs the tool' do
        expect(agent.use_tool('spy', target: 'x')).to eq('ran on x')
      end
    end

    context 'when a person retries a failed tool with new parameters' do
      let(:answers) { [true, false] }
      let(:handler) { ->(_) { answers.shift } }

      before do
        calls = 0
        allow(spy).to receive(:execute).and_wrap_original do |original, **args|
          (calls += 1) == 1 ? raise('boom') : original.call(**args)
        end
        agent.enable_human_input
        allow(agent).to receive(:request_human_choice).and_return(choice_index: 1)
        allow(agent).to receive(:request_human_input).and_return(valid: true, processed_input: { 'target' => 'other' })
      end

      it 'asks again before the retry' do
        expect(agent.use_tool('spy', target: 'x')).to match(/not run/)
        expect(spy.calls).to be_empty
        expect(answers).to be_empty
      end
    end
  end

  describe 'human input toggles' do
    let(:agent) { RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: ApprovalFakeLLM.new([], native: true), require_approval_for_tools: true) }

    it 'are not a way to turn approval off by accident' do
      agent.enable_human_input
      expect(agent.require_approval_for_tools?).to be true

      agent.disable_human_input
      expect(agent.require_approval_for_tools?).to be true
    end

    it 'leaves an explicit off switch' do
      agent.require_approval_for_tools = false

      expect(agent.require_approval_for_tools?).to be false
    end
  end

  # Keeps the choke point the only one: anything that calls a tool directly from
  # lib/ would skip the check again.
  it 'has one place in lib/ that executes a tool' do
    direct = Dir[File.join(RCrewAI.root, 'lib/**/*.rb')].flat_map do |file|
      File.readlines(file).grep(/\btool\.execute|execute_with_validation\(/)
          .reject { |line| line.strip.start_with?('#', 'def ') }
          .map { |line| "#{File.basename(file)}: #{line.strip}" }
    end

    expect(direct.map { |entry| entry.split(':').first }.uniq).to eq(['tool_execution.rb'])
  end
end
