# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::Anthropic do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :anthropic
      c.anthropic_api_key = 'k'
      c.anthropic_model = 'claude-sonnet-4-6'
    end
  end
  let(:client) { described_class.new(config) }

  it 'sends tools at top level with input_schema and parses tool_use blocks' do
    tool_schema = {
      name: 'web_search', description: 'Search',
      parameters: { type: 'object', properties: { query: { type: 'string' } },
                    required: ['query'] }
    }

    stub = stub_request(:post, 'https://api.anthropic.com/v1/messages')
           .with(body: hash_including(
             'model' => 'claude-sonnet-4-6',
             'tools' => [{ 'name' => 'web_search', 'description' => 'Search',
                           'input_schema' => { 'type' => 'object',
                                               'properties' => { 'query' => { 'type' => 'string' } },
                                               'required' => ['query'] } }]
           ))
           .to_return(status: 200,
                      body: File.read('spec/fixtures/llm_responses/anthropic/tool_call.json'),
                      headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hi' }], tools: [tool_schema])

    expect(stub).to have_been_requested
    expect(result[:tool_calls]).to eq([{ id: 'toolu_1', name: 'web_search',
                                         arguments: { 'query' => 'ruby' } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
    expect(result[:usage]).to eq(prompt_tokens: 50, completion_tokens: 10, total_tokens: 60)
  end

  it 'assembles streamed input_json_delta into a tool_call' do
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200,
                 body: File.read('spec/fixtures/llm_responses/anthropic/stream_tool_call.sse'),
                 headers: { 'Content-Type' => 'text/event-stream' })

    events = []
    result = client.chat(
      messages: [{ role: 'user', content: 'x' }],
      tools: [{ name: 'web_search', description: 'x',
                parameters: { type: 'object', properties: {}, required: [] } }],
      stream: ->(e) { events << e }
    )

    expect(result[:tool_calls]).to eq([{ id: 'toolu_1', name: 'web_search',
                                         arguments: { 'query' => 'ruby' } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
  end

  it 'attaches cache_control to system blocks when cache_system: true' do
    captured_body = nil
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .with do |req|
      captured_body = JSON.parse(req.body)
      true
    end
      .to_return(status: 200,
                 body: '{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}',
                 headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'system', content: 'BIG SYSTEM' * 200 },
                           { role: 'user', content: 'hi' }],
                cache_system: true)

    expect(captured_body['system']).to be_an(Array)
    expect(captured_body.dig('system', 0, 'cache_control')).to eq('type' => 'ephemeral')
  end

  describe '#format_messages' do
    it 'converts messages to Anthropic format' do
      messages = [
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there!' }
      ]
      formatted = client.send(:format_messages, messages)
      expect(formatted).to eq([
                                { role: 'user', content: 'Hello' },
                                { role: 'assistant', content: 'Hi there!' }
                              ])
    end

    it 'converts string messages to user messages' do
      formatted = client.send(:format_messages, ['Hello'])
      expect(formatted).to eq([{ role: 'user', content: 'Hello' }])
    end
  end

  describe '#extract_system_message' do
    it 'extracts system message content' do
      messages = [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
      expect(client.send(:extract_system_message, messages)).to eq('You are helpful')
    end

    it 'returns nil when no system message' do
      expect(client.send(:extract_system_message, [{ role: 'user', content: 'Hello' }])).to be_nil
    end
  end

  describe '#supports_native_tools?' do
    it 'returns true' do
      expect(client.supports_native_tools?).to be true
    end
  end

  describe '#validate_config!' do
    it 'requires Anthropic API key' do
      invalid = double('Configuration', api_key: nil, anthropic_api_key: nil,
                                        model: 'claude-3-sonnet')
      expect { described_class.new(invalid) }
        .to raise_error(RCrewAI::ConfigurationError, /Anthropic API key is required/)
    end
  end
end
