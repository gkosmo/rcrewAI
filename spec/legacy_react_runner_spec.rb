# frozen_string_literal: true

require 'spec_helper'
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
