# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe 'Replaying a tool loop on OpenAI-shaped providers' do
  let(:calls) { [{ id: 'c1', name: 'echo', arguments: { 'text' => 'hi' } }] }
  let(:history) do
    [{ role: 'user', content: 'go' },
     { role: 'assistant', content: nil, tool_calls: calls },
     { role: 'tool', tool_call_id: 'c1', content: 'hi' }]
  end
  let(:chat_reply) do
    { model: 'm', choices: [{ message: { role: 'assistant', content: 'ok' }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
  end
  let(:wire_call) do
    { 'id' => 'c1', 'type' => 'function', 'function' => { 'name' => 'echo', 'arguments' => '{"text":"hi"}' } }
  end

  def capture(reply)
    body = nil
    stub_request(:post, /.*/).to_return do |request|
      body = JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: reply.to_json }
    end
    yield
    body
  end

  def config_for(provider)
    RCrewAI::Configuration.new.tap do |c|
      c.llm_provider = provider
      c.api_key = 'k'
      c.openai_api_key = 'k'
      c.azure_api_key = 'k'
      c.base_url = 'https://example.test/v1'
      c.deployment_name = 'd'
      c.api_version = 'v'
      c.snowflake_account = 'acct'
      c.model = 'm'
    end
  end

  %i[openai azure openai_compatible snowflake].each do |provider|
    it "sends #{provider} tool_calls in the Chat Completions shape" do
      client = RCrewAI::LLMClient.for_provider(provider, config_for(provider))
      messages = capture(chat_reply) { client.chat(messages: history) }['messages']

      expect(messages[1]).to eq('role' => 'assistant', 'content' => nil, 'tool_calls' => [wire_call])
      expect(messages[2]).to eq('role' => 'tool', 'tool_call_id' => 'c1', 'content' => 'hi')
    end
  end

  it 'leaves ordinary OpenAI messages untouched' do
    client = RCrewAI::LLMClient.for_provider(:openai, config_for(:openai))
    plain = [{ role: 'user', content: [{ type: 'text', text: 'x' }] }, { role: 'assistant', content: 'y' }]

    expect(capture(chat_reply) { client.chat(messages: plain) }['messages'])
      .to eq(JSON.parse(plain.to_json))
  end

  describe 'the Responses API' do
    let(:client) { RCrewAI::LLMClient.for_provider(:openai_responses, config_for(:openai_responses)) }
    let(:reply) do
      { model: 'm', status: 'completed',
        output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'ok' }] }],
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 } }
    end

    it 'builds function_call and function_call_output items' do
      input = capture(reply) { client.chat(messages: history) }['input']

      expect(input[1]).to eq('type' => 'function_call', 'call_id' => 'c1', 'name' => 'echo',
                             'arguments' => '{"text":"hi"}')
      expect(input[2]).to eq('type' => 'function_call_output', 'call_id' => 'c1', 'output' => 'hi')
    end

    it 'replays output items unchanged, including reasoning' do
      raw = [{ 'type' => 'reasoning', 'id' => 'rs_1', 'summary' => [] },
             { 'type' => 'function_call', 'call_id' => 'c1', 'name' => 'echo', 'arguments' => '{"text":"hi"}' }]
      replay = [history[0], history[1].merge(raw_content: raw), history[2]]

      expect(capture(reply) { client.chat(messages: replay) }['input'][1, 2]).to eq(raw)
    end

    it 'returns raw output items' do
      stub_request(:post, /.*/).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                          body: reply.to_json)

      expect(client.chat(messages: [{ role: 'user', content: 'x' }])[:raw_content])
        .to eq(JSON.parse(reply[:output].to_json))
    end
  end

  describe 'Ollama' do
    let(:client) do
      RCrewAI::LLMClient.for_provider(:ollama, RCrewAI::Configuration.new.tap do |c|
        c.llm_provider = :ollama
        c.model = 'llama3.1'
        c.base_url = 'http://localhost:11434'
      end)
    end
    let(:reply) { { model: 'm', message: { role: 'assistant', content: 'ok' }, done: true } }

    it 'sends tool_calls and names the tool on each result' do
      messages = capture(reply) { client.chat(messages: history) }['messages']

      expect(messages[1]).to eq(
        'role' => 'assistant', 'content' => '',
        'tool_calls' => [{ 'function' => { 'name' => 'echo', 'arguments' => { 'text' => 'hi' } } }]
      )
      expect(messages[2]).to eq('role' => 'tool', 'content' => 'hi', 'tool_name' => 'echo')
    end
  end

  # Fakes in the other runner specs hide the request shape, so this one goes
  # through a real client.
  it 'completes a loop through ToolRunner with a real client' do
    tool_class = Class.new(RCrewAI::Tools::Base) do
      tool_name 'echo'
      description 'echo'
      param :text, type: :string, required: true
      def execute(text:) = "echoed #{text}"
    end
    sse = lambda do |*chunks|
      chunks.map { |chunk| "data: #{chunk.to_json}\n\n" }.join + "data: [DONE]\n\n"
    end
    tool_delta = { tool_calls: [{ index: 0, id: 'c1', type: 'function',
                                  function: { name: 'echo', arguments: '{"text":"hi"}' } }] }
    turns = [
      sse.call({ choices: [{ delta: tool_delta }] }, { choices: [{ delta: {}, finish_reason: 'tool_calls' }] }),
      sse.call({ choices: [{ delta: { content: 'ok' } }] }, { choices: [{ delta: {}, finish_reason: 'stop' }] })
    ]
    bodies = []
    stub_request(:post, /.*/).to_return do |request|
      bodies << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: turns[bodies.size - 1] }
    end
    agent = double('Agent', name: 'a', memory: double('Memory', add_tool_usage: nil),
                            require_approval_for_tools?: false)
    client = RCrewAI::LLMClient.for_provider(:openai, config_for(:openai))

    result = RCrewAI::ToolRunner.new(agent: agent, llm: client, tools: [tool_class.new])
                                .run(messages: [{ role: 'user', content: 'go' }])

    expect(result[:content]).to eq('ok')
    expect(bodies[1]['messages'][1]['tool_calls']).to eq([wire_call])
    expect(bodies[1]['messages'][2]).to include('role' => 'tool', 'content' => 'echoed hi')
  end
end
