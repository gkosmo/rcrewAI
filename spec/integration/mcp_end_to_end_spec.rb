# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP end-to-end' do
  let(:server_path) { File.expand_path('../fixtures/mcp_servers/echo_server.rb', __dir__) }

  it 'lets an agent call an MCP tool via the ToolRunner' do
    RCrewAI::MCP::Client.with_connection(command: 'ruby', args: [server_path]) do |client|
      llm = double('LLM')
      allow(llm).to receive(:supports_native_tools?).and_return(true)
      allow(llm).to receive(:config).and_return(RCrewAI.configuration)
      sequence = [
        { content: nil,
          tool_calls: [{ id: '1', name: 'echo-server__echo', arguments: { 'message' => 'hi' } }],
          usage: {}, finish_reason: :tool_calls, model: 'm', provider: :openai },
        { content: 'Done.', tool_calls: [], usage: {},
          finish_reason: :stop, model: 'm', provider: :openai }
      ]
      allow(llm).to receive(:chat) { sequence.shift }

      configure_test_llm
      agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: client.tools)
      agent.instance_variable_set(:@llm_client, llm)

      task = RCrewAI::Task.new(name: 't', description: 'echo hi',
                               agent: agent, expected_output: 'x')
      result = agent.execute_task(task)

      expect(result[:content]).to eq('Done.')
      expect(result[:tool_calls_history].first[:result]).to include('echo: hi')
    end
  end
end
