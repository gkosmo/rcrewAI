# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::MCP::ToolAdapter do
  let(:client) { instance_double(RCrewAI::MCP::Client) }
  let(:descriptor) do
    {
      'name' => 'echo',
      'description' => 'Echoes',
      'inputSchema' => { type: 'object',
                         properties: { message: { type: 'string' } },
                         required: ['message'] }
    }
  end
  let(:adapter) { described_class.new(client, descriptor, 'srv') }

  it 'prefixes name with server' do
    expect(adapter.name).to eq('srv__echo')
  end

  it 'stringifies schema keys' do
    schema = adapter.json_schema
    expect(schema[:parameters]['type']).to eq('object')
    expect(schema[:parameters]['required']).to eq(['message'])
  end

  it 'falls back to permissive schema when inputSchema is missing' do
    a = described_class.new(client, { 'name' => 'x' }, 's')
    expect(a.json_schema[:parameters]).to eq('type' => 'object', 'additionalProperties' => true)
  end

  it 'execute delegates to client.call_tool' do
    expect(client).to receive(:call_tool).with('srv__echo', { message: 'hi' }).and_return('echo: hi')
    expect(adapter.execute(message: 'hi')).to eq('echo: hi')
  end

  it 'execute_with_validation accepts string-keyed args' do
    expect(client).to receive(:call_tool).with('srv__echo', { message: 'hi' }).and_return('ok')
    expect(adapter.execute_with_validation('message' => 'hi')).to eq('ok')
  end
end
