# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::Ollama do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :ollama
      c.model = 'llama3.1'
      c.base_url = 'http://localhost:11434'
    end
  end
  let(:client) { described_class.new(config) }

  it 'parses tool_calls from non-streamed response' do
    stub = stub_request(:post, 'http://localhost:11434/api/chat')
           .with { |req|
             body = JSON.parse(req.body)
             body['tools'].is_a?(Array) &&
               body.dig('tools', 0, 'function', 'name') == 'web_search'
           }
           .to_return(status: 200,
                      body: File.read('spec/fixtures/llm_responses/ollama/tool_call.json'),
                      headers: { 'Content-Type' => 'application/json' })

    tool_schema = {
      name: 'web_search', description: 'Search',
      parameters: { type: 'object', properties: { query: { type: 'string' } },
                    required: ['query'] }
    }
    result = client.chat(messages: [{ role: 'user', content: 'hi' }], tools: [tool_schema])

    expect(stub).to have_been_requested
    expect(result[:tool_calls]).to eq([{ id: nil, name: 'web_search',
                                         arguments: { 'query' => 'ruby' } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
  end

  describe '#supports_native_tools?' do
    it 'returns true for allowlisted models' do
      expect(client.supports_native_tools?(model: 'llama3.1')).to be true
      expect(client.supports_native_tools?(model: 'llama3.1:8b')).to be true
      expect(client.supports_native_tools?(model: 'qwen2.5:14b')).to be true
    end

    it 'returns false for unlisted models' do
      expect(client.supports_native_tools?(model: 'gemma2')).to be false
      expect(client.supports_native_tools?(model: 'tinyllama')).to be false
    end

    it 'honors configuration override' do
      RCrewAI.configuration.ollama_native_tools = false
      expect(client.supports_native_tools?(model: 'llama3.1')).to be false
    end
  end
end
