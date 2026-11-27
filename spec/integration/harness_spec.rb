# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/harness_helpers'

# Full agent runs against a scripted LLM, with a spy tool. What matters here is
# whether the tool ran, with what, and what the model was told.
RSpec.describe 'harness enforcement' do
  let(:spy) { HarnessSpyTool.new }
  let(:task) { RCrewAI::Task.new(name: 't', description: 'do it', expected_output: 'x') }
  let(:secrets_harness) do
    RCrewAI::Harness.new(default: :ask) do
      allow :spy_writer
      block :spy_writer, matching: { path: /\.env\z/ }, reason: 'Secrets are read-only.'
    end
  end

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

  def legacy_turn(args, name: 'spy_writer')
    params = args.map { |key, value| "#{key}=#{value}" }.join(', ')
    { content: "USE_TOOL[#{name}](#{params})", tool_calls: [], finish_reason: :length, usage: {} }
  end

  def build_agent(llm, tools: [spy], **options)
    RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: tools, llm: llm, **options)
  end

  def sent_to_model(llm)
    llm.requests.last.map { |m| m[:content].to_s }.join("\n")
  end

  def recording_handler(asked, answer: true)
    lambda do |request|
      asked << request
      answer
    end
  end

  { 'native' => true, 'legacy' => false }.each do |runner, native|
    context "on the #{runner} runner" do
      define_method(:turn) { |args| native ? native_turn(args) : legacy_turn(args) }
      define_method(:llm_for) { |*turns| HarnessLLM.new(native: native, turns: turns) }

      it 'does not run a blocked call and tells the model why' do
        llm = llm_for(turn('path' => '.env'))
        events = []
        result = build_agent(llm, harness: secrets_harness).execute_task(task, stream: ->(e) { events << e })

        expect(spy.calls).to be_empty
        expect(sent_to_model(llm)).to include("REFUSED: Tool 'spy_writer' was not run: Secrets are read-only.")
        expect(result[:tool_calls_history]).to be_empty
        blocked = events.grep(RCrewAI::Events::ToolBlocked)
        expect(blocked.length).to eq(1)
        expect(blocked.first.to_h).to include(tool: 'spy_writer', source: :rule, reason: 'Secrets are read-only.',
                                              type: :tool_blocked)
        expect(blocked.first.args).to eq('path' => '.env')
      end

      it 'runs an allowed call without asking' do
        asked = []
        build_agent(llm_for(turn('path' => 'notes.txt')), harness: secrets_harness,
                                                          approval_handler: recording_handler(asked)).execute_task(task)

        expect(spy.calls).to eq([{ path: 'notes.txt' }])
        expect(asked).to be_empty
      end

      it 'asks once for an ask rule' do
        asked = []
        harness = RCrewAI::Harness.new { ask :spy_writer }
        build_agent(llm_for(turn('path' => 'notes.txt')), harness: harness,
                                                          approval_handler: recording_handler(asked)).execute_task(task)

        expect(asked.map(&:arguments)).to eq([{ 'path' => 'notes.txt' }])
        expect(spy.calls).to eq([{ path: 'notes.txt' }])
      end

      it 'does not run an unlisted tool with no handler and no terminal' do
        harness = RCrewAI::Harness.new { allow :something_else }
        build_agent(llm_for(turn('path' => 'notes.txt')), harness: harness).execute_task(task)

        expect(spy.calls).to be_empty
      end

      it 'still asks about an allowed call when the agent requires approval for tools' do
        asked = []
        build_agent(llm_for(turn('path' => 'notes.txt')), harness: secrets_harness, require_approval_for_tools: true,
                                                          approval_handler: recording_handler(asked)).execute_task(task)

        expect(asked.length).to eq(1)
        expect(spy.calls).to eq([{ path: 'notes.txt' }])
      end

      it 'does not ask about a blocked call when the agent requires approval for tools' do
        asked = []
        build_agent(llm_for(turn('path' => '.env')), harness: secrets_harness, require_approval_for_tools: true,
                                                     approval_handler: recording_handler(asked)).execute_task(task)

        expect(asked).to be_empty
        expect(spy.calls).to be_empty
      end

      it 'does not run or ask about a call missing a required argument' do
        asked = []
        llm = llm_for(turn('body' => 'hi'))
        build_agent(llm, harness: RCrewAI::Harness.new { ask :spy_writer },
                         approval_handler: recording_handler(asked)).execute_task(task)

        expect(spy.calls).to be_empty
        expect(asked).to be_empty
        expect(sent_to_model(llm)).to include('missing required param: path')
      end

      it 'does not run or ask about a call with an undeclared argument' do
        asked = []
        llm = llm_for(turn('path' => 'notes.txt', 'mode' => 'append'))
        build_agent(llm, harness: RCrewAI::Harness.new { ask :spy_writer },
                         approval_handler: recording_handler(asked)).execute_task(task)

        expect(spy.calls).to be_empty
        expect(asked).to be_empty
        expect(sent_to_model(llm)).to include('unknown param: mode')
      end
    end
  end

  context 'on the native runner' do
    def native_llm(*turns)
      HarnessLLM.new(native: true, turns: turns)
    end

    it 'gives the handler coerced values, and a handler cannot change what runs' do
      asked = []
      handler = lambda do |request|
        asked << request.arguments
        begin
          request.arguments['path'] << '.env'
        rescue FrozenError
          nil
        end
        true
      end
      build_agent(native_llm(native_turn({ 'path' => 7 })), harness: RCrewAI::Harness.new { ask :spy_writer },
                                                            approval_handler: handler).execute_task(task)

      expect(asked).to eq([{ 'path' => '7' }])
      expect(spy.calls).to eq([{ path: '7' }])
    end

    it "runs what was checked when the model's original arguments change after the check" do
      original = { 'path' => +'notes.txt' }
      handler = lambda do |_request|
        original['path'].replace('.env')
        original['body'] = 'sneaked in'
        true
      end
      build_agent(native_llm(native_turn(original)), harness: RCrewAI::Harness.new { ask :spy_writer },
                                                     approval_handler: handler).execute_task(task)

      expect(spy.calls).to eq([{ path: 'notes.txt' }])
    end

    it 'runs only the unblocked one of two parallel calls' do
      llm = native_llm(native_turn({ 'path' => '.env' }, { 'path' => 'notes.txt' }))
      build_agent(llm, harness: secrets_harness).execute_task(task)

      expect(spy.calls).to eq([{ path: 'notes.txt' }])
      results = llm.requests.last.select { |m| m[:role] == 'tool' }
      expect(results.map { |m| m[:content] })
        .to eq(["REFUSED: Tool 'spy_writer' was not run: Secrets are read-only.", 'wrote notes.txt'])
    end

    it 'does not run a call with two arguments of the same name rather than picking one' do
      llm = native_llm(native_turn({ 'path' => 'notes.txt', path: '.env' }))
      build_agent(llm, harness: secrets_harness).execute_task(task)

      expect(spy.calls).to be_empty
    end

    it 'blocks a call whose rule check overflows the stack' do
      deep = lambda do |args|
        recurse = ->(n) { recurse.call(n + 1) }
        recurse.call(args.size)
      end
      harness = RCrewAI::Harness.new(default: :allow) { block :spy_writer, if: deep }
      llm = native_llm(native_turn({ 'path' => 'notes.txt' }))
      build_agent(llm, harness: harness).execute_task(task)

      expect(spy.calls).to be_empty
      expect(sent_to_model(llm)).to include("REFUSED: Tool 'spy_writer' was not run")
    end

    it 'drops undeclared arguments, as before, for an agent without a harness' do
      build_agent(native_llm(native_turn({ 'path' => 'notes.txt', 'mode' => 'append' }))).execute_task(task)

      expect(spy.calls).to eq([{ path: 'notes.txt' }])
    end

    describe 'a tool that overrides execute_with_validation' do
      let(:client) { double('MCP client') }
      let(:adapter) do
        RCrewAI::MCP::ToolAdapter.new(client, { 'name' => 'send', 'description' => 'sends' }, 'srv')
      end
      let(:llm) { native_llm(native_turn({ 'to' => 'x', 'extra' => 1 }, name: 'srv__send')) }

      it 'is blocked by a rule naming it' do
        harness = RCrewAI::Harness.new(default: :allow) { block :srv__send }
        build_agent(llm, tools: [adapter], harness: harness).execute_task(task)

        expect(sent_to_model(llm)).to include("REFUSED: Tool 'srv__send' was not run")
      end

      it 'gets exactly the supplied arguments when allowed' do
        expect(client).to receive(:call_tool).with('srv__send', { to: 'x', extra: 1 }).and_return('sent')
        build_agent(llm, tools: [adapter], harness: RCrewAI::Harness.new { allow :srv__send }).execute_task(task)

        expect(sent_to_model(llm)).to include('sent')
      end
    end
  end

  it 'blocks a legacy call made with the class name of the tool' do
    llm = HarnessLLM.new(native: false, turns: [legacy_turn({ 'path' => '.env' }, name: 'harnessspytool')])
    build_agent(llm, harness: secrets_harness).execute_task(task)

    expect(spy.calls).to be_empty
    expect(sent_to_model(llm)).to include("REFUSED: Tool 'spy_writer' was not run: Secrets are read-only.")
  end

  describe 'Agent#use_tool' do
    let(:agent) { build_agent(HarnessLLM.new(native: true, turns: []), harness: secrets_harness) }
    let(:refusal) { "REFUSED: Tool 'spy_writer' was not run: Secrets are read-only." }

    it 'returns the refusal for a blocked call' do
      expect(agent.use_tool('spy_writer', path: '.env')).to eq(refusal)
      expect(spy.calls).to be_empty
    end

    it 'returns the refusal when the tool is named by its class' do
      expect(agent.use_tool('harnessspytool', path: '.env')).to eq(refusal)
      expect(spy.calls).to be_empty
    end

    it 'runs an allowed call' do
      expect(agent.use_tool('spy_writer', path: 'notes.txt')).to eq('wrote notes.txt')
    end

    it 'blocks a retry that a person makes with new parameters' do
      agent.enable_human_input
      allow(agent).to receive(:request_human_choice).and_return(choice_index: 1)
      allow(agent).to receive(:request_human_input).and_return(valid: true, processed_input: { 'path' => '.env' })

      expect(agent.use_tool('spy_writer', path: 'notes.txt', mode: 'append')).to eq(refusal)
      expect(spy.calls).to be_empty
    end

    it 'does not run a tool given cyclic arguments' do
      client = double('MCP client')
      adapter = RCrewAI::MCP::ToolAdapter.new(client, { 'name' => 'send' }, 'srv')
      agent = build_agent(HarnessLLM.new(native: true, turns: []), tools: [adapter],
                                                                   harness: RCrewAI::Harness.new { allow :srv__send })
      cyclic = []
      cyclic << cyclic

      expect { agent.use_tool('srv__send', data: cyclic) }.to raise_error(RCrewAI::Tools::ToolError)
    end
  end

  describe 'building an agent' do
    it 'rejects a matching: argument the tool does not declare' do
      harness = RCrewAI::Harness.new { block :spy_writer, matching: { file_path: /x/ } }

      expect { build_agent(HarnessLLM.new(native: true, turns: []), harness: harness) }
        .to raise_error(ArgumentError, /file_path/)
    end

    it 'warns about a rule for a tool the agent does not have' do
      harness = RCrewAI::Harness.new { allow :spy_writr }

      expect { build_agent(HarnessLLM.new(native: true, turns: []), harness: harness) }
        .to output(/spy_writr/).to_stdout
    end

    it 'exposes the harness' do
      agent = build_agent(HarnessLLM.new(native: true, turns: []), harness: secrets_harness)

      expect(agent.harness).to be(secrets_harness)
    end
  end
end
