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

  describe 'temperature' do
    let(:reply) do
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { model: 'm', stop_reason: 'end_turn', content: [{ type: 'text', text: 'hi' }],
                usage: { input_tokens: 1, output_tokens: 1 } }.to_json }
    end
    let(:fresh) do
      RCrewAI::Configuration.new.tap do |c|
        c.llm_provider = :anthropic
        c.anthropic_api_key = 'k'
      end
    end

    def sent_body(chat_config, **options)
      body = nil
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return do |r|
        body = JSON.parse(r.body)
        reply
      end
      described_class.new(chat_config).chat(messages: [{ role: 'user', content: 'x' }], **options)
      body
    end

    it 'leaves temperature out when nobody set one' do
      expect(sent_body(fresh)).not_to have_key('temperature')
    end

    it 'sends a temperature the user configured' do
      fresh.temperature = 0.7
      expect(sent_body(fresh)['temperature']).to eq(0.7)
    end

    it 'sends a per-call temperature' do
      expect(sent_body(fresh, temperature: 0.3)['temperature']).to eq(0.3)
    end

    it 'lets a per-agent override clear a global temperature' do
      fresh.temperature = 0.7
      expect(sent_body(fresh.with_overrides(temperature: nil))).not_to have_key('temperature')
    end
  end

  describe 'replaying a tool loop' do
    let(:raw) do
      [{ 'type' => 'thinking', 'thinking' => '', 'signature' => 'sig' },
       { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'echo', 'input' => { 'text' => 'hi' } },
       { 'type' => 'tool_use', 'id' => 'tu_2', 'name' => 'echo', 'input' => { 'text' => 'yo' } }]
    end
    let(:reply) do
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { model: 'm', stop_reason: 'end_turn', content: [{ type: 'text', text: 'ok' }],
                usage: { input_tokens: 1, output_tokens: 1 } }.to_json }
    end

    def sent_messages(history)
      body = nil
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return do |r|
        body = JSON.parse(r.body)
        reply
      end
      client.chat(messages: history)
      body['messages']
    end

    let(:tool_results) do
      [{ role: 'tool', tool_call_id: 'tu_1', content: 'hi' },
       { role: 'tool', tool_call_id: 'tu_2', content: 'yo' }]
    end

    it 'replays the assistant blocks unchanged, including thinking' do
      messages = sent_messages([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: [], raw_content: raw },
                                *tool_results])

      expect(messages[1]).to eq('role' => 'assistant', 'content' => raw)
    end

    it 'sends every tool result in one user message' do
      messages = sent_messages([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: [], raw_content: raw },
                                *tool_results])

      expect(messages.size).to eq(3)
      expect(messages[2]).to eq(
        'role' => 'user',
        'content' => [
          { 'type' => 'tool_result', 'tool_use_id' => 'tu_1', 'content' => 'hi' },
          { 'type' => 'tool_result', 'tool_use_id' => 'tu_2', 'content' => 'yo' }
        ]
      )
    end

    it 'builds tool_use blocks when a history has no raw content' do
      messages = sent_messages([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: 'Checking.',
                                  tool_calls: [{ id: 'tu_1', name: 'echo', arguments: { 'text' => 'hi' } }] },
                                { role: 'tool', tool_call_id: 'tu_1', content: 'hi' }])

      expect(messages[1]['content']).to eq(
        [{ 'type' => 'text', 'text' => 'Checking.' },
         { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'echo', 'input' => { 'text' => 'hi' } }]
      )
    end

    it 'returns raw content blocks from a plain response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { model: 'm', stop_reason: 'tool_use', content: raw,
                           usage: { input_tokens: 1, output_tokens: 1 } }.to_json)

      expect(client.chat(messages: [{ role: 'user', content: 'x' }])[:raw_content]).to eq(raw)
    end

    it 'reassembles raw content blocks from a stream' do
      sse = [
        { type: 'message_start', message: { usage: { input_tokens: 1 } } },
        { type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: '', signature: '' } },
        { type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: 'hm' } },
        { type: 'content_block_delta', index: 0, delta: { type: 'signature_delta', signature: 'sig' } },
        { type: 'content_block_start', index: 1, content_block: { type: 'text', text: '' } },
        { type: 'content_block_delta', index: 1, delta: { type: 'text_delta', text: 'Checking.' } },
        { type: 'content_block_start', index: 2, content_block: { type: 'tool_use', id: 'tu_1', name: 'echo', input: {} } },
        { type: 'content_block_delta', index: 2, delta: { type: 'input_json_delta', partial_json: '{"text":"hi"}' } },
        { type: 'message_delta', delta: { stop_reason: 'tool_use' }, usage: { output_tokens: 2 } }
      ].map { |e| "event: #{e[:type]}\ndata: #{e.to_json}\n\n" }.join
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: sse, headers: { 'Content-Type' => 'text/event-stream' })

      result = client.chat(messages: [{ role: 'user', content: 'x' }], stream: ->(_) {})

      expect(result[:raw_content]).to eq(
        [{ 'type' => 'thinking', 'thinking' => 'hm', 'signature' => 'sig' },
         { 'type' => 'text', 'text' => 'Checking.' },
         { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'echo', 'input' => { 'text' => 'hi' } }]
      )
    end
  end

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
