# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::Azure do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :azure
      c.azure_api_key = 'azkey'
      c.base_url = 'https://example.openai.azure.com'
      c.azure_model = 'gpt-4o'
      c.deployment_name = 'my-deploy'
      c.api_version = '2024-02-01'
    end
  end
  let(:client) { described_class.new(config) }

  it 'routes to the deployment URL with api-version and uses api-key header' do
    expected = 'https://example.openai.azure.com/openai/deployments/my-deploy/chat/completions?api-version=2024-02-01'
    stub = stub_request(:post, expected)
           .with(headers: { 'api-key' => 'azkey' })
           .to_return(status: 200,
                      body: '{"choices":[{"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2},"model":"gpt-4o"}',
                      headers: { 'Content-Type' => 'application/json' })

    result = client.chat(messages: [{ role: 'user', content: 'hi' }])

    expect(stub).to have_been_requested
    expect(result[:provider]).to eq(:azure)
    expect(result[:content]).to eq('hi')
  end

  describe '#supports_native_tools?' do
    it 'returns true (inherited)' do
      expect(client.supports_native_tools?).to be true
    end
  end

  describe '#validate_config!' do
    it 'requires Azure API key' do
      invalid = double('Configuration',
                       api_key: nil, azure_api_key: nil,
                       model: 'gpt-4', base_url: 'https://x',
                       deployment_name: 'd', api_version: 'v',
                       timeout: 30,
                       temperature: 0.1, max_tokens: 100,
                       openai_api_key: nil)
      expect { described_class.new(invalid) }
        .to raise_error(RCrewAI::ConfigurationError, /Azure API key is required/)
    end
  end
end
