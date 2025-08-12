# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::LLMClients::Base do
  let(:config) do
    double('Configuration', 
           api_key: 'test-key', 
           model: 'test-model',
           temperature: 0.1,
           timeout: 60)
  end
  let(:client) { described_class.new(config) }

  describe '#initialize' do
    it 'sets config and logger' do
      expect(client.config).to eq(config)
      expect(client.logger).to be_a(Logger)
    end

    it 'validates config on initialization' do
      invalid_config = double('Configuration', api_key: nil, model: 'test-model')
      expect { described_class.new(invalid_config) }.to raise_error(RCrewAI::ConfigurationError)
    end
  end

  describe '#chat' do
    it 'raises NotImplementedError' do
      expect { client.chat(messages: []) }.to raise_error(NotImplementedError)
    end
  end

  describe '#complete' do
    it 'calls chat with formatted message' do
      expect(client).to receive(:chat).with(hash_including(messages: [{ role: 'user', content: 'test prompt' }]))
      client.complete(prompt: 'test prompt')
    end
  end

  describe '#validate_config!' do
    it 'validates api_key presence' do
      config = double('Configuration', api_key: nil, model: 'test')
      expect { described_class.new(config) }.to raise_error(RCrewAI::ConfigurationError)
    end

    it 'validates model presence' do
      config = double('Configuration', api_key: 'test', model: nil)
      expect { described_class.new(config) }.to raise_error(RCrewAI::ConfigurationError)
    end
  end

  describe '#handle_response' do
    it 'returns body for successful responses' do
      response = double('Response', status: 200, body: { 'result' => 'success' })
      expect(client.send(:handle_response, response)).to eq({ 'result' => 'success' })
    end

    it 'raises APIError for bad requests' do
      response = double('Response', status: 400, body: { 'error' => 'bad request' })
      expect { client.send(:handle_response, response) }.to raise_error(RCrewAI::LLMClients::APIError)
    end

    it 'raises AuthenticationError for unauthorized' do
      response = double('Response', status: 401, body: {})
      expect { client.send(:handle_response, response) }.to raise_error(RCrewAI::LLMClients::AuthenticationError)
    end

    it 'raises RateLimitError for rate limits' do
      response = double('Response', status: 429, body: {})
      expect { client.send(:handle_response, response) }.to raise_error(RCrewAI::LLMClients::RateLimitError)
    end

    it 'raises APIError for server errors' do
      response = double('Response', status: 500, body: {})
      expect { client.send(:handle_response, response) }.to raise_error(RCrewAI::LLMClients::APIError)
    end
  end

  describe '#build_headers' do
    it 'returns standard headers' do
      headers = client.send(:build_headers)
      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['User-Agent']).to include('rcrewai/')
    end
  end

  describe '#http_client' do
    it 'returns configured Faraday client' do
      http = client.send(:http_client)
      expect(http).to be_a(Faraday::Connection)
    end
  end
end