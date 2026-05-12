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
        finish_reason: :stop, model: 'm', provider: :test, tool_calls: [] }
    ]
    llm = double('LLM').tap { |l| allow(l).to receive(:chat) { responses.shift } }

    runner = described_class.new(agent: agent, llm: llm, tools: [tool])
    result = runner.run(messages: [{ role: 'user', content: 'x' }])

    expect(result[:content]).to include('Done')
    expect(result[:tool_calls_history].first[:tool]).to eq('echo')
  end
end
