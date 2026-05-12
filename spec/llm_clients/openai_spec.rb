# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::OpenAI do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :openai
      c.openai_api_key = 'test-key'
      c.openai_model = 'gpt-4o'
    end
  end
  let(:client) { described_class.new(config) }

  describe '#chat with tools (non-streaming)' do
    it 'sends tools in OpenAI shape and returns tool_calls' do
      tool_schema = {
        name: 'web_search',
        description: 'Search',
        parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] }
      }

      stub = stub_request(:post, 'https://api.openai.com/v1/chat/completions')
             .with(body: hash_including(
               'model' => 'gpt-4o',
               'tools' => [{ 'type' => 'function', 'function' => tool_schema.transform_keys(&:to_s) }]
             ))
             .to_return(status: 200,
                        body: File.read('spec/fixtures/llm_responses/openai/tool_call.json'),
                        headers: { 'Content-Type' => 'application/json' })

      result = client.chat(messages: [{ role: 'user', content: 'hi' }], tools: [tool_schema])

      expect(stub).to have_been_requested
      expect(result[:content]).to be_nil
      expect(result[:tool_calls]).to eq([{
                                          id: 'call_1', name: 'web_search', arguments: { 'query' => 'ruby' }
                                        }])
      expect(result[:finish_reason]).to eq(:tool_calls)
      expect(result[:usage]).to eq(prompt_tokens: 50, completion_tokens: 10, total_tokens: 60)
    end
  end

  describe '#chat with stream:' do
    it 'emits TextDelta events and returns final assembled result' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200,
                   body: File.read('spec/fixtures/llm_responses/openai/stream_text.sse'),
                   headers: { 'Content-Type' => 'text/event-stream' })

      events = []
      result = client.chat(messages: [{ role: 'user', content: 'hi' }],
                           stream: ->(e) { events << e })

      text_events = events.select { |e| e.is_a?(RCrewAI::Events::TextDelta) }
      expect(text_events.map(&:text)).to eq(%w[Hel lo])
      expect(result[:content]).to eq('Hello')
      expect(result[:finish_reason]).to eq(:stop)
      expect(events.last).to be_a(RCrewAI::Events::Usage)
    end

    it 'assembles streamed tool_call arguments' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200,
                   body: File.read('spec/fixtures/llm_responses/openai/stream_tool_call.sse'),
                   headers: { 'Content-Type' => 'text/event-stream' })

      events = []
      result = client.chat(messages: [{ role: 'user', content: 'search' }],
                           tools: [{ name: 'web_search', description: 'x',
                                     parameters: { type: 'object', properties: {}, required: [] } }],
                           stream: ->(e) { events << e })

      expect(result[:tool_calls]).to eq([{ id: 'call_1', name: 'web_search',
                                           arguments: { 'query' => 'ruby' } }])
      expect(result[:finish_reason]).to eq(:tool_calls)
    end
  end

  describe '#supports_native_tools?' do
    it 'returns true for any OpenAI model' do
      expect(client.supports_native_tools?(model: 'gpt-4o')).to be true
    end
  end

  describe '#validate_config!' do
    it 'requires OpenAI API key' do
      invalid_config = double('Configuration',
                              api_key: nil,
                              openai_api_key: nil,
                              model: 'gpt-4')

      expect { described_class.new(invalid_config) }
        .to raise_error(RCrewAI::ConfigurationError, /OpenAI API key is required/)
    end
  end
end
