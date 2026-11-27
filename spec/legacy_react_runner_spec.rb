# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/harness_helpers'
require_relative 'tool_runner_spec' # for FakeTool

RSpec.describe RCrewAI::LegacyReactRunner do
  let(:tool) { FakeTool.new }
  let(:agent) do
    double('Agent', name: 'a',
                    memory: double('Memory', add_tool_usage: nil),
                    available_tools_description: '- echo: echo')
  end

  it 'parses USE_TOOL[name](k=v) and threads the result' do
    responses = [
      { content: "Reasoning... USE_TOOL[echo](msg=hi)\nDone", usage: {},
        finish_reason: :stop, model: 'm', provider: :test, tool_calls: [] },
      { content: 'FINAL_ANSWER[Done]', usage: {},
        finish_reason: :stop, model: 'm', provider: :test, tool_calls: [] }
    ]
    llm = double('LLM').tap { |l| allow(l).to receive(:chat) { responses.shift } }

    runner = described_class.new(agent: agent, llm: llm, tools: [tool])
    result = runner.run(messages: [{ role: 'user', content: 'x' }])

    expect(result[:content]).to include('Done')
    expect(result[:tool_calls_history].first[:tool]).to eq('echo')
  end

  def reply(content)
    { content: content, usage: {}, finish_reason: :stop, model: 'm', provider: :test, tool_calls: [] }
  end

  it 'sends a tool result back to the model although the provider reported :stop' do
    responses = [reply('USE_TOOL[echo](msg=hi)'), reply('FINAL_ANSWER[it said hi]')]
    seen = []
    llm = double('LLM')
    allow(llm).to receive(:chat) do |messages:|
      seen << messages.map { |m| m[:content] }.join("\n")
      responses.shift
    end

    result = described_class.new(agent: agent, llm: llm, tools: [tool]).run(messages: [{ role: 'user', content: 'x' }])

    expect(seen.length).to eq(2)
    expect(seen.last).to include('Tool echo result')
    expect(result[:content]).to eq('it said hi')
  end

  def run_replies(*contents)
    responses = contents.map { |c| reply(c) }
    llm = double('LLM')
    allow(llm).to receive(:chat) { responses.shift }
    described_class.new(agent: agent, llm: llm, tools: [tool]).run(messages: [{ role: 'user', content: 'x' }])
  end

  it 'returns a short plain answer given after a tool turn' do
    expect(run_replies('USE_TOOL[echo](msg=hi)', 'It is 42.')[:content]).to eq('It is 42.')
  end

  it 'does not take a final answer written before the tool result was seen' do
    result = run_replies('USE_TOOL[echo](msg=hi) FINAL_ANSWER[a guess]', 'FINAL_ANSWER[checked]')

    expect(result[:content]).to eq('checked')
  end
end

# Without a harness too: joining one turn's results used to raise on these.
RSpec.describe RCrewAI::LegacyReactRunner, 'tool text in mixed encodings' do
  let(:tool) do
    Class.new(RCrewAI::Tools::Base) do
      tool_name 'enc'
      description 'returns text in two encodings'
      param :kind, type: :string

      def execute(kind:)
        kind == 'binary' ? "caf\xC3\xA9".b : 'café'
      end
    end.new
  end

  it 'is converted to UTF-8 instead of failing the run' do
    llm = HarnessLLM.new(native: false, turns: [{ content: 'USE_TOOL[enc](kind=utf8) USE_TOOL[enc](kind=binary)',
                                                  tool_calls: [], finish_reason: :length, usage: {} }])
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [tool], llm: llm)

    agent.execute_task(RCrewAI::Task.new(name: 't', description: 'do it', expected_output: 'x'))

    expect(llm.requests.last.last[:content]).to eq("Tool enc result: café\nTool enc result: café")
  end
end
