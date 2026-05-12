# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::Google do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :google
      c.google_api_key = 'gkey'
      c.google_model = 'gemini-1.5-pro'
    end
  end
  let(:client) { described_class.new(config) }

  it 'sends function_declarations and parses functionCall from response' do
    tool_schema = {
      name: 'web_search', description: 'Search',
      parameters: { type: 'object', properties: { query: { type: 'string' } },
                    required: ['query'] }
    }

    stub = stub_request(:post,
                        %r{generativelanguage\.googleapis\.com/v1beta/models/gemini-1\.5-pro:generateContent})
           .with do |req|
             body = JSON.parse(req.body)
             body['tools'].is_a?(Array) &&
               body.dig('tools', 0, 'function_declarations', 0, 'name') == 'web_search'
           end
           .to_return(status: 200,
                      body: File.read('spec/fixtures/llm_responses/google/tool_call.json'),
                      headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hi' }], tools: [tool_schema])

    expect(stub).to have_been_requested
    expect(result[:tool_calls]).to eq([{ id: nil, name: 'web_search',
                                         arguments: { 'query' => 'ruby' } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
    expect(result[:usage]).to eq(prompt_tokens: 50, completion_tokens: 10, total_tokens: 60)
  end

  it 'emits TextDelta events when streaming' do
    stub_request(:post,
                 %r{generativelanguage\.googleapis\.com/v1beta/models/gemini-1\.5-pro:streamGenerateContent})
      .to_return(status: 200,
                 body: File.read('spec/fixtures/llm_responses/google/stream.sse'),
                 headers: { 'Content-Type' => 'text/event-stream' })

    events = []
    result = client.chat(messages: [{ role: 'user', content: 'hi' }],
                         stream: ->(e) { events << e })

    text_events = events.select { |e| e.is_a?(RCrewAI::Events::TextDelta) }
    expect(text_events.map(&:text)).to eq(%w[Hel lo])
    expect(result[:content]).to eq('Hello')
    expect(result[:finish_reason]).to eq(:stop)
  end

  describe '#supports_native_tools?' do
    it 'returns true' do
      expect(client.supports_native_tools?).to be true
    end
  end

  describe '#validate_config!' do
    it 'requires Google API key' do
      invalid = double('Configuration', api_key: nil, google_api_key: nil,
                                        model: 'gemini-1.5-pro')
      expect { described_class.new(invalid) }
        .to raise_error(RCrewAI::ConfigurationError, /Google API key is required/)
    end
  end
end
