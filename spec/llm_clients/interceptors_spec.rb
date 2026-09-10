# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe 'LLM message interceptors' do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :openai
      c.openai_api_key = 'k'
      c.openai_model = 'gpt-4o'
    end
  end
  let(:client) { RCrewAI::LLMClients::OpenAI.new(config) }

  let(:success_body) do
    {
      'choices' => [{ 'message' => { 'content' => 'hi', 'role' => 'assistant' },
                      'finish_reason' => 'stop' }],
      'usage' => { 'prompt_tokens' => 1, 'completion_tokens' => 2, 'total_tokens' => 3 },
      'model' => 'gpt-4o'
    }.to_json
  end

  def stub_chat
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .to_return(status: 200, body: success_body,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#before_request' do
    it 'invokes the hook with the outgoing payload' do
      stub_chat
      seen = nil
      client.before_request { |payload, _ctx| seen = payload }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(seen[:model]).to eq('gpt-4o')
      expect(seen[:messages]).to eq([{ role: 'user', content: 'hello' }])
    end

    it 'passes provider and model in the context' do
      stub_chat
      seen = nil
      client.before_request { |_payload, ctx| seen = ctx }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(seen[:provider]).to eq(:openai)
      expect(seen[:model]).to eq('gpt-4o')
    end

    it 'sends a payload rewritten by the hook' do
      stub = stub_request(:post, 'https://api.openai.com/v1/chat/completions')
             .with(body: hash_including('temperature' => 0.9))
             .to_return(status: 200, body: success_body,
                        headers: { 'Content-Type' => 'application/json' })

      client.before_request { |payload, _ctx| payload.merge(temperature: 0.9) }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(stub).to have_been_requested
    end

    it 'keeps the original payload when the hook returns nil' do
      stub = stub_request(:post, 'https://api.openai.com/v1/chat/completions')
             .with(body: hash_including('model' => 'gpt-4o'))
             .to_return(status: 200, body: success_body,
                        headers: { 'Content-Type' => 'application/json' })

      client.before_request { |_payload, _ctx| nil }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(stub).to have_been_requested
    end

    it 'runs multiple hooks in registration order, threading the payload' do
      stub = stub_request(:post, 'https://api.openai.com/v1/chat/completions')
             .with(body: hash_including('temperature' => 0.2))
             .to_return(status: 200, body: success_body,
                        headers: { 'Content-Type' => 'application/json' })

      client.before_request { |payload, _ctx| payload.merge(temperature: 0.1) }
      client.before_request { |payload, _ctx| payload.merge(temperature: 0.2) }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(stub).to have_been_requested
    end
  end

  describe '#after_response' do
    it 'invokes the hook with the normalized result' do
      stub_chat
      seen = nil
      client.after_response { |result, _ctx| seen = result }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(seen[:content]).to eq('hi')
      expect(seen[:provider]).to eq(:openai)
    end

    it 'returns a result rewritten by the hook' do
      stub_chat
      client.after_response { |result, _ctx| result.merge(content: 'rewritten') }

      result = client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(result[:content]).to eq('rewritten')
    end

    it 'keeps the original result when the hook returns nil' do
      stub_chat
      client.after_response { |_result, _ctx| nil }

      result = client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(result[:content]).to eq('hi')
    end

    it 'reports the request duration in the context' do
      stub_chat
      seen = nil
      client.after_response { |_result, ctx| seen = ctx }

      client.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(seen[:duration_ms]).to be_a(Numeric)
      expect(seen[:duration_ms]).to be >= 0
    end
  end

  describe 'error isolation' do
    it 'does not let a raising before_request hook break the call' do
      stub_chat
      client.before_request { |_payload, _ctx| raise 'boom' }

      result = nil
      io = with_captured_io { result = client.chat(messages: [{ role: 'user', content: 'hello' }]) }

      expect(result[:content]).to eq('hi')
      expect(io[:stderr]).to include('boom')
    end

    it 'does not let a raising after_response hook break the call' do
      stub_chat
      client.after_response { |_result, _ctx| raise 'boom' }

      result = nil
      io = with_captured_io { result = client.chat(messages: [{ role: 'user', content: 'hello' }]) }

      expect(result[:content]).to eq('hi')
      expect(io[:stderr]).to include('boom')
    end
  end

  describe 'registration' do
    it 'accepts hooks at construction time' do
      stub_chat
      seen = nil
      c = RCrewAI::LLMClients::OpenAI.new(
        config, before_request: [->(payload, _ctx) { seen = payload }]
      )

      c.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(seen).not_to be_nil
    end

    it 'is available on every provider client' do
      [RCrewAI::LLMClients::OpenAI, RCrewAI::LLMClients::Anthropic,
       RCrewAI::LLMClients::Google, RCrewAI::LLMClients::Azure,
       RCrewAI::LLMClients::Ollama].each do |klass|
        expect(klass.instance_methods).to include(:before_request, :after_response)
      end
    end
  end

  describe 'per-provider wiring' do
    it 'fires both hooks on the anthropic client' do
      RCrewAI.configuration.tap do |c|
        c.llm_provider = :anthropic
        c.anthropic_api_key = 'k'
        c.anthropic_model = 'claude-sonnet-4-6'
      end
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200,
                   body: { 'content' => [{ 'type' => 'text', 'text' => 'hi' }],
                           'stop_reason' => 'end_turn',
                           'usage' => { 'input_tokens' => 1, 'output_tokens' => 2 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      c = RCrewAI::LLMClients::Anthropic.new(RCrewAI.configuration)
      before_ctx = nil
      after_ctx = nil
      c.before_request { |_p, ctx| before_ctx = ctx }
      c.after_response { |_r, ctx| after_ctx = ctx }

      c.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(before_ctx[:provider]).to eq(:anthropic)
      expect(after_ctx[:duration_ms]).to be_a(Numeric)
    end

    it 'fires both hooks on the ollama client' do
      RCrewAI.configuration.tap do |c|
        c.llm_provider = :ollama
        c.api_key = 'k'
        c.model = 'llama3'
      end
      stub_request(:post, %r{/api/chat})
        .to_return(status: 200,
                   body: { 'message' => { 'content' => 'hi' }, 'done' => true,
                           'prompt_eval_count' => 1, 'eval_count' => 2 }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      c = RCrewAI::LLMClients::Ollama.new(RCrewAI.configuration)
      before_ctx = nil
      after_ctx = nil
      c.before_request { |_p, ctx| before_ctx = ctx }
      c.after_response { |_r, ctx| after_ctx = ctx }

      c.chat(messages: [{ role: 'user', content: 'hello' }])

      expect(before_ctx[:provider]).to eq(:ollama)
      expect(after_ctx[:duration_ms]).to be_a(Numeric)
    end
  end
end
