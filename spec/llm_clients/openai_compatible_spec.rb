# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::OpenAICompatible do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :openai_compatible
      c.api_key = 'k'
      c.model = 'mixtral-8x7b'
      c.base_url = 'https://api.together.xyz/v1'
    end
  end
  let(:client) { described_class.new(config) }

  let(:body) do
    { 'choices' => [{ 'message' => { 'content' => 'hi', 'role' => 'assistant' },
                      'finish_reason' => 'stop' }],
      'usage' => { 'prompt_tokens' => 1, 'completion_tokens' => 2, 'total_tokens' => 3 },
      'model' => 'mixtral-8x7b' }.to_json
  end

  it 'posts to the configured base url' do
    stub = stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'authenticates with a bearer token' do
    stub = stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
           .with(headers: { 'Authorization' => 'Bearer k' })
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'reports its own provider name' do
    expect(client.provider_name).to eq(:openai_compatible)
  end

  it 'normalizes the response like OpenAI' do
    stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(result[:content]).to eq('hi')
    expect(result[:provider]).to eq(:openai_compatible)
    expect(result[:usage][:total_tokens]).to eq(3)
  end

  it 'requires a base url' do
    config.base_url = nil
    expect { described_class.new(config) }
      .to raise_error(RCrewAI::ConfigurationError, /base url/i)
  end

  it 'requires an api key' do
    expect do
      described_class.new(RCrewAI.configuration.tap do |c|
        c.llm_provider = :openai_compatible
        c.api_key = nil
        c.base_url = 'https://x/v1'
      end)
    end.to raise_error(RCrewAI::ConfigurationError, /api key/i)
  end

  it 'supports interceptor hooks like every other client' do
    stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })
    seen = nil
    client.before_request { |_p, ctx| seen = ctx }

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(seen[:provider]).to eq(:openai_compatible)
  end
end

RSpec.describe RCrewAI::LLMClients::Bedrock do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :bedrock
      c.api_key = 'k'
      c.model = 'anthropic.claude-sonnet-4-v1:0'
      c.aws_region = 'us-east-1'
    end
  end
  let(:client) { described_class.new(config) }

  let(:body) do
    { 'output' => { 'message' => { 'content' => [{ 'text' => 'hi' }], 'role' => 'assistant' } },
      'stopReason' => 'end_turn',
      'usage' => { 'inputTokens' => 1, 'outputTokens' => 2, 'totalTokens' => 3 } }.to_json
  end

  def converse_url
    'https://bedrock-runtime.us-east-1.amazonaws.com/model/' \
      'anthropic.claude-sonnet-4-v1%3A0/converse'
  end

  it 'posts to the regional converse endpoint' do
    stub = stub_request(:post, converse_url)
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'sends messages in Converse shape' do
    stub = stub_request(:post, converse_url)
           .with(body: hash_including(
             'messages' => [{ 'role' => 'user', 'content' => [{ 'text' => 'hello' }] }]
           ))
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'lifts a system message into the top-level system field' do
    stub = stub_request(:post, converse_url)
           .with(body: hash_including('system' => [{ 'text' => 'be terse' }]))
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'system', content: 'be terse' },
                           { role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'normalizes the Converse response' do
    stub_request(:post, converse_url)
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(result[:content]).to eq('hi')
    expect(result[:provider]).to eq(:bedrock)
    expect(result[:finish_reason]).to eq(:stop)
    expect(result[:usage][:total_tokens]).to eq(3)
  end

  it 'parses a tool call into the canonical shape' do
    tool_body = {
      'output' => { 'message' => { 'content' => [
        { 'toolUse' => { 'toolUseId' => 'tu_1', 'name' => 'web_search',
                         'input' => { 'query' => 'ruby' } } }
      ] } },
      'stopReason' => 'tool_use',
      'usage' => { 'inputTokens' => 1, 'outputTokens' => 2, 'totalTokens' => 3 }
    }.to_json
    stub_request(:post, converse_url)
      .to_return(status: 200, body: tool_body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(result[:tool_calls]).to eq([{ id: 'tu_1', name: 'web_search',
                                         arguments: { 'query' => 'ruby' } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
  end

  it 'requires a region' do
    config.aws_region = nil
    expect { described_class.new(config) }
      .to raise_error(RCrewAI::ConfigurationError, /region/i)
  end
end

RSpec.describe RCrewAI::LLMClients::SnowflakeCortex do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :snowflake
      c.api_key = 'tok'
      c.model = 'mistral-large2'
      c.snowflake_account = 'acme-xy12345'
    end
  end
  let(:client) { described_class.new(config) }

  let(:url) { 'https://acme-xy12345.snowflakecomputing.com/api/v2/cortex/inference:complete' }
  let(:body) do
    { 'choices' => [{ 'message' => { 'content' => 'hi' }, 'finish_reason' => 'stop' }],
      'usage' => { 'prompt_tokens' => 1, 'completion_tokens' => 2, 'total_tokens' => 3 } }.to_json
  end

  it 'posts to the account inference endpoint' do
    stub = stub_request(:post, url)
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'authenticates with a Snowflake keypair JWT header' do
    stub = stub_request(:post, url)
           .with(headers: { 'Authorization' => 'Bearer tok',
                            'X-Snowflake-Authorization-Token-Type' => 'KEYPAIR_JWT' })
           .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(stub).to have_been_requested
  end

  it 'normalizes the response' do
    stub_request(:post, url)
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hello' }])

    expect(result[:content]).to eq('hi')
    expect(result[:provider]).to eq(:snowflake)
  end

  it 'requires an account identifier' do
    config.snowflake_account = nil
    expect { described_class.new(config) }
      .to raise_error(RCrewAI::ConfigurationError, /account/i)
  end
end

RSpec.describe 'provider registry' do
  it 'resolves every new provider by symbol' do
    RCrewAI.configure do |c|
      c.api_key = 'k'
      c.base_url = 'https://x/v1'
      c.aws_region = 'us-east-1'
      c.snowflake_account = 'acct'
    end

    {
      openai_compatible: RCrewAI::LLMClients::OpenAICompatible,
      bedrock: RCrewAI::LLMClients::Bedrock,
      snowflake: RCrewAI::LLMClients::SnowflakeCortex
    }.each do |sym, klass|
      expect(RCrewAI::LLMClient.for_provider(sym)).to be_a(klass)
    end
  end

  it 'passes interceptor hooks through for_provider' do
    RCrewAI.configure do |c|
      c.api_key = 'k'
      c.base_url = 'https://x/v1'
    end
    hook = ->(p, _ctx) { p }

    client = RCrewAI::LLMClient.for_provider(:openai_compatible, RCrewAI.configuration,
                                             before_request: [hook])

    expect(client).to be_a(RCrewAI::LLMClients::OpenAICompatible)
  end

  it 'still raises for an unknown provider' do
    expect { RCrewAI::LLMClient.for_provider(:nope) }
      .to raise_error(RCrewAI::ConfigurationError, /unsupported provider/i)
  end
end
