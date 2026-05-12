# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::MCP::Client do
  let(:server_path) { File.expand_path('../fixtures/mcp_servers/echo_server.rb', __dir__) }

  it 'handshakes, lists tools, and calls a tool' do
    client = described_class.connect(command: 'ruby', args: [server_path])
    expect(client.server_name).to eq('echo-server')
    expect(client.tools.map(&:name)).to eq(['echo-server__echo'])

    tool = client.tools.first
    result = tool.execute(message: 'hello')
    expect(result).to include('echo: hello')
  ensure
    client&.close
  end

  it 'with_connection auto-closes on block exit' do
    described_class.with_connection(command: 'ruby', args: [server_path]) do |client|
      expect(client.tools).not_to be_empty
    end
  end

  it 'translates MCP inputSchema to canonical JSON schema for tool adapters' do
    described_class.with_connection(command: 'ruby', args: [server_path]) do |client|
      schema = client.tools.first.json_schema
      expect(schema[:name]).to eq('echo-server__echo')
      expect(schema[:parameters]).to include(
        'type' => 'object',
        'properties' => { 'message' => { 'type' => 'string' } },
        'required' => ['message']
      )
    end
  end
end
