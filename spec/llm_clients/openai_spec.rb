# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::LLMClients::OpenAI do
  let(:config) do
    double('Configuration',
           api_key: 'test-openai-key',
           openai_api_key: 'test-openai-key',
           model: 'gpt-4',
           temperature: 0.1,
           max_tokens: 1000,
           timeout: 60)
  end
  
  subject { described_class.new(config) }

  it_behaves_like 'an LLM client'

  describe '#initialize' do
    it 'sets base URL' do
      expect(subject.instance_variable_get(:@base_url)).to eq('https://api.openai.com/v1')
    end
  end

  describe '#chat' do
    let(:mock_http) { double('HTTP Client') }
    let(:successful_response) do
      double('Response',
             status: 200,
             body: {
               'choices' => [{
                 'message' => {
                   'content' => 'Hello, how can I help?',
                   'role' => 'assistant'
                 },
                 'finish_reason' => 'stop'
               }],
               'usage' => { 'total_tokens' => 50 },
               'model' => 'gpt-4'
             })
    end

    before do
      allow(subject).to receive(:http_client).and_return(mock_http)
    end

    it 'makes POST request to chat completions endpoint' do
      expect(mock_http).to receive(:post)
        .with(
          'https://api.openai.com/v1/chat/completions',
          hash_including(
            model: 'gpt-4',
            messages: [{ role: 'user', content: 'Hello' }],
            temperature: 0.1,
            max_tokens: 1000
          ),
          hash_including('Authorization' => 'Bearer test-openai-key')
        )
        .and_return(successful_response)

      result = subject.chat(messages: [{ role: 'user', content: 'Hello' }])
      
      expect(result).to include(
        content: 'Hello, how can I help?',
        role: 'assistant',
        finish_reason: 'stop',
        provider: :openai
      )
    end

    it 'formats string messages correctly' do
      expect(mock_http).to receive(:post)
        .with(
          anything,
          hash_including(messages: [{ role: 'user', content: 'Hello' }]),
          anything
        )
        .and_return(successful_response)

      subject.chat(messages: ['Hello'])
    end

    it 'includes additional OpenAI options' do
      expect(mock_http).to receive(:post)
        .with(
          anything,
          hash_including(
            top_p: 0.9,
            frequency_penalty: 0.5,
            stop: ['###']
          ),
          anything
        )
        .and_return(successful_response)

      subject.chat(
        messages: [{ role: 'user', content: 'Hello' }],
        top_p: 0.9,
        frequency_penalty: 0.5,
        stop: ['###']
      )
    end

    it 'handles API errors' do
      error_response = double('Response',
                             status: 400,
                             body: { 'error' => { 'message' => 'Invalid request' } })
      
      allow(mock_http).to receive(:post).and_return(error_response)
      
      expect { subject.chat(messages: ['Hello']) }
        .to raise_error(RCrewAI::LLMClients::APIError, /Invalid request/)
    end
  end

  describe '#complete' do
    let(:mock_http) { double('HTTP Client') }

    before do
      allow(subject).to receive(:http_client).and_return(mock_http)
    end

    context 'with newer models' do
      it 'uses chat endpoint' do
        expect(subject).to receive(:chat).with(hash_including(messages: [{ role: 'user', content: 'Complete this' }]))
        subject.complete(prompt: 'Complete this')
      end
    end

    context 'with legacy models' do
      let(:config) do
        double('Configuration',
               api_key: 'test-key',
               openai_api_key: 'test-key',
               model: 'text-davinci-003',
               temperature: 0.1,
               max_tokens: 1000,
               timeout: 60)
      end

      let(:completion_response) do
        double('Response',
               status: 200,
               body: {
                 'choices' => [{
                   'text' => 'This is a completion',
                   'finish_reason' => 'stop'
                 }],
                 'usage' => { 'total_tokens' => 30 },
                 'model' => 'text-davinci-003'
               })
      end

      it 'uses completions endpoint for davinci models' do
        expect(mock_http).to receive(:post)
          .with(
            'https://api.openai.com/v1/completions',
            hash_including(
              model: 'text-davinci-003',
              prompt: 'Complete this',
              temperature: 0.1
            ),
            anything
          )
          .and_return(completion_response)

        result = subject.complete(prompt: 'Complete this')
        expect(result).to include(content: 'This is a completion', provider: :openai)
      end
    end
  end

  describe '#models' do
    let(:mock_http) { double('HTTP Client') }
    let(:models_response) do
      double('Response',
             status: 200,
             body: {
               'data' => [
                 { 'id' => 'gpt-4' },
                 { 'id' => 'gpt-3.5-turbo' }
               ]
             })
    end

    before do
      allow(subject).to receive(:http_client).and_return(mock_http)
    end

    it 'fetches available models' do
      expect(mock_http).to receive(:get)
        .with('https://api.openai.com/v1/models', {}, anything)
        .and_return(models_response)

      models = subject.models
      expect(models).to eq(['gpt-4', 'gpt-3.5-turbo'])
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