# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::OpenAIResponses do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :openai_responses
      c.openai_api_key = 'k'
      c.openai_model = 'gpt-5'
    end
  end
  let(:client) { described_class.new(config) }

  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:body) do
    {
      'id' => 'resp_1',
      'model' => 'gpt-5',
      'status' => 'completed',
      'output' => [
        { 'type' => 'message', 'role' => 'assistant',
          'content' => [{ 'type' => 'output_text', 'text' => 'hi' }] }
      ],
      'usage' => { 'input_tokens' => 1, 'output_tokens' => 2, 'total_tokens' => 3 }
    }.to_json
  end

  it 'posts to the responses endpoint' do
    stub = stub_request(:post, url)
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'sends messages under the input key' do
    stub = stub_request(:post, url)
           .with(body: hash_including(
             'input' => [{ 'role' => 'user', 'content' => 'hello' }]
           ))
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'lifts a system message into the instructions field' do
    stub = stub_request(:post, url)
           .with(body: hash_including('instructions' => 'be terse'))
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'system', content: 'be terse' },
                           { role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'uses max_output_tokens rather than max_tokens' do
    stub = stub_request(:post, url)
           .with(body: hash_including('max_output_tokens' => 128))
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }], max_tokens: 128)

    expect(stub).to have_been_requested
  end

  it 'extracts assistant text from the output array' do
    stub_request(:post, url)
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(result[:content]).to eq('hi')
    expect(result[:provider]).to eq(:openai_responses)
    expect(result[:finish_reason]).to eq(:stop)
  end

  it 'maps Responses usage fields onto the canonical shape' do
    stub_request(:post, url)
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(result[:usage]).to eq(prompt_tokens: 1, completion_tokens: 2, total_tokens: 3)
  end

  it 'sends tools in the flat Responses shape' do
    stub = stub_request(:post, url)
           .with(body: hash_including(
             'tools' => [{ 'type' => 'function', 'name' => 'web_search',
                           'description' => 'Search',
                           'parameters' => { 'type' => 'object',
                                             'properties' => { 'query' => { 'type' => 'string' } },
                                             'required' => ['query'] } }]
           ))
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hi' }],
                tools: [{ name: 'web_search', description: 'Search',
                          parameters: { type: 'object',
                                        properties: { query: { type: 'string' } },
                                        required: ['query'] } }])

    expect(stub).to have_been_requested
  end

  it 'parses a function call from the output array' do
    tool_body = {
      'id' => 'resp_2', 'model' => 'gpt-5', 'status' => 'completed',
      'output' => [
        { 'type' => 'function_call', 'call_id' => 'call_1',
          'name' => 'web_search', 'arguments' => '{"query":"ruby"}' }
      ],
      'usage' => { 'input_tokens' => 1, 'output_tokens' => 2, 'total_tokens' => 3 }
    }.to_json
    stub_request(:post, url)
      .to_return(status: 200, body: tool_body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hi' }])

    expect(result[:tool_calls]).to eq([{ id: 'call_1', name: 'web_search',
                                         arguments: { 'query' => 'ruby' } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
  end

  it 'reports an incomplete response as length-limited' do
    incomplete = {
      'id' => 'r', 'model' => 'gpt-5', 'status' => 'incomplete',
      'incomplete_details' => { 'reason' => 'max_output_tokens' },
      'output' => [{ 'type' => 'message', 'role' => 'assistant',
                     'content' => [{ 'type' => 'output_text', 'text' => 'partial' }] }],
      'usage' => { 'input_tokens' => 1, 'output_tokens' => 2, 'total_tokens' => 3 }
    }.to_json
    stub_request(:post, url)
      .to_return(status: 200, body: incomplete, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hi' }])

    expect(result[:finish_reason]).to eq(:length)
  end

  it 'supports interceptor hooks' do
    stub_request(:post, url)
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })
    seen = nil
    client.after_response { |_r, ctx| seen = ctx }

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(seen[:provider]).to eq(:openai_responses)
    expect(seen[:duration_ms]).to be_a(Numeric)
  end

  it 'is resolvable through the provider registry' do
    expect(RCrewAI::LLMClient.for_provider(:openai_responses, config))
      .to be_a(described_class)
  end
end
