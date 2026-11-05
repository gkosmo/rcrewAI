# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe 'Replaying a tool loop' do
  let(:calls) do
    [{ id: nil, name: 'echo', arguments: { 'text' => 'hi' } },
     { id: nil, name: 'lookup', arguments: { 'q' => 'yo' } }]
  end
  let(:results) do
    [{ role: 'tool', tool_call_id: nil, content: 'hi' },
     { role: 'tool', tool_call_id: nil, content: 'yo' }]
  end

  def capture(url, reply)
    body = nil
    stub_request(:post, url).to_return do |request|
      body = JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: reply.to_json }
    end
    yield
    body
  end

  describe RCrewAI::LLMClients::Google do
    let(:config) do
      RCrewAI::Configuration.new.tap do |c|
        c.llm_provider = :google
        c.google_api_key = 'k'
        c.google_model = 'gemini-3.8-flash'
      end
    end
    let(:client) { described_class.new(config) }
    let(:url) { /generativelanguage\.googleapis\.com/ }
    let(:reply) do
      { candidates: [{ content: { parts: [{ text: 'ok' }] }, finishReason: 'STOP' }], usageMetadata: {} }
    end
    let(:raw) do
      [{ 'functionCall' => { 'name' => 'echo', 'args' => { 'text' => 'hi' } }, 'thoughtSignature' => 'sig' },
       { 'functionCall' => { 'name' => 'lookup', 'args' => { 'q' => 'yo' } } }]
    end

    def sent_contents(history)
      capture(url, reply) { client.chat(messages: history) }['contents']
    end

    it 'replays model parts unchanged, including thought signatures' do
      contents = sent_contents([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: calls, raw_content: raw },
                                *results])

      expect(contents[1]).to eq('role' => 'model', 'parts' => raw)
    end

    it 'sends results as functionResponse parts in one content, matched by order' do
      contents = sent_contents([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: calls, raw_content: raw },
                                *results])

      expect(contents.size).to eq(3)
      expect(contents[2]).to eq(
        'role' => 'user',
        'parts' => [
          { 'functionResponse' => { 'name' => 'echo', 'response' => { 'result' => 'hi' } } },
          { 'functionResponse' => { 'name' => 'lookup', 'response' => { 'result' => 'yo' } } }
        ]
      )
    end

    it 'matches results by id when the API supplies one' do
      with_ids = [calls[0].merge(id: 'a'), calls[1].merge(id: 'b')]
      contents = sent_contents([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: with_ids },
                                { role: 'tool', tool_call_id: 'b', content: 'yo' },
                                { role: 'tool', tool_call_id: 'a', content: 'hi' }])

      expect(contents[2]['parts'].map { |p| p['functionResponse'].slice('id', 'name') })
        .to eq([{ 'id' => 'b', 'name' => 'lookup' }, { 'id' => 'a', 'name' => 'echo' }])
    end

    it 'builds functionCall parts when a history has no raw content' do
      contents = sent_contents([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: 'Checking.', tool_calls: calls.first(1) },
                                results.first])

      expect(contents[1]['parts']).to eq(
        [{ 'text' => 'Checking.' }, { 'functionCall' => { 'name' => 'echo', 'args' => { 'text' => 'hi' } } }]
      )
    end

    it 'still prepends the system prompt to the first user message' do
      contents = sent_contents([{ role: 'system', content: 'Be brief.' }, { role: 'user', content: 'go' }])

      expect(contents[0]['parts'][0]['text']).to eq("Be brief.\n\ngo")
    end

    it 'returns raw parts from a plain response' do
      stub_request(:post, url).to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { candidates: [{ content: { parts: raw } }], usageMetadata: {} }.to_json
      )

      expect(client.chat(messages: [{ role: 'user', content: 'x' }])[:raw_content]).to eq(raw)
    end

    it 'returns raw parts from a stream' do
      sse = "data: #{{ candidates: [{ content: { parts: raw.first(1) } }] }.to_json}\n\n" \
            "data: #{{ candidates: [{ content: { parts: raw.last(1) } }] }.to_json}\n\n"
      stub_request(:post, url).to_return(status: 200, body: sse,
                                         headers: { 'Content-Type' => 'text/event-stream' })

      result = client.chat(messages: [{ role: 'user', content: 'x' }], stream: ->(_) {})

      expect(result[:raw_content]).to eq(raw)
    end
  end

  describe RCrewAI::LLMClients::Bedrock do
    let(:config) do
      RCrewAI::Configuration.new.tap do |c|
        c.llm_provider = :bedrock
        c.api_key = 'k'
        c.model = 'some-model'
        c.aws_region = 'us-east-1'
      end
    end
    let(:client) { described_class.new(config) }
    let(:url) { /bedrock-runtime/ }
    let(:reply) do
      { output: { message: { role: 'assistant', content: [{ text: 'ok' }] } }, stopReason: 'end_turn',
        usage: { inputTokens: 1, outputTokens: 1, totalTokens: 2 } }
    end
    let(:ided_calls) { [calls[0].merge(id: 'a'), calls[1].merge(id: 'b')] }
    let(:ided_results) do
      [{ role: 'tool', tool_call_id: 'a', content: 'hi' }, { role: 'tool', tool_call_id: 'b', content: 'yo' }]
    end
    let(:raw) do
      [{ 'reasoningContent' => { 'reasoningText' => { 'text' => 'hm', 'signature' => 'sig' } } },
       { 'toolUse' => { 'toolUseId' => 'a', 'name' => 'echo', 'input' => { 'text' => 'hi' } } }]
    end

    def sent_messages(history)
      capture(url, reply) { client.chat(messages: history) }['messages']
    end

    it 'replays assistant blocks unchanged, including reasoning' do
      messages = sent_messages([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: ided_calls, raw_content: raw },
                                *ided_results])

      expect(messages[1]).to eq('role' => 'assistant', 'content' => raw)
    end

    it 'sends results as toolResult blocks in one user message' do
      messages = sent_messages([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: nil, tool_calls: ided_calls, raw_content: raw },
                                *ided_results])

      expect(messages.size).to eq(3)
      expect(messages[2]).to eq(
        'role' => 'user',
        'content' => [
          { 'toolResult' => { 'toolUseId' => 'a', 'content' => [{ 'text' => 'hi' }] } },
          { 'toolResult' => { 'toolUseId' => 'b', 'content' => [{ 'text' => 'yo' }] } }
        ]
      )
    end

    it 'builds toolUse blocks when a history has no raw content' do
      messages = sent_messages([{ role: 'user', content: 'go' },
                                { role: 'assistant', content: 'Checking.', tool_calls: ided_calls.first(1) },
                                ided_results.first])

      expect(messages[1]['content']).to eq(
        [{ 'text' => 'Checking.' },
         { 'toolUse' => { 'toolUseId' => 'a', 'name' => 'echo', 'input' => { 'text' => 'hi' } } }]
      )
    end

    it 'returns raw blocks from a response' do
      stub_request(:post, url).to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { output: { message: { content: raw } }, stopReason: 'tool_use', usage: {} }.to_json
      )

      expect(client.chat(messages: [{ role: 'user', content: 'x' }])[:raw_content]).to eq(raw)
    end
  end
end
