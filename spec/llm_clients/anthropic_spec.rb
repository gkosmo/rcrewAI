# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::LLMClients::Anthropic do
  let(:config) do
    double('Configuration',
           api_key: 'test-anthropic-key',
           anthropic_api_key: 'test-anthropic-key',
           model: 'claude-3-sonnet-20240229',
           temperature: 0.1,
           max_tokens: 1000,
           timeout: 60)
  end
  
  subject { described_class.new(config) }

  it_behaves_like 'an LLM client'

  describe '#initialize' do
    it 'sets base URL and API version' do
      expect(subject.instance_variable_get(:@base_url)).to eq('https://api.anthropic.com/v1')
    end
  end

  describe '#chat' do
    let(:mock_http) { double('HTTP Client') }
    let(:successful_response) do
      double('Response',
             status: 200,
             body: {
               'content' => [{
                 'text' => 'Hello! How can I assist you today?'
               }],
               'stop_reason' => 'end_turn',
               'usage' => {
                 'input_tokens' => 10,
                 'output_tokens' => 20
               },
               'model' => 'claude-3-sonnet-20240229'
             })
    end

    before do
      allow(subject).to receive(:http_client).and_return(mock_http)
    end

    it 'makes POST request to messages endpoint' do
      expect(mock_http).to receive(:post)
        .with(
          'https://api.anthropic.com/v1/messages',
          hash_including(
            model: 'claude-3-sonnet-20240229',
            messages: [{ role: 'user', content: 'Hello' }],
            temperature: 0.1,
            max_tokens: 1000
          ),
          hash_including(
            'Authorization' => 'Bearer test-anthropic-key',
            'anthropic-version' => '2023-06-01'
          )
        )
        .and_return(successful_response)

      result = subject.chat(messages: [{ role: 'user', content: 'Hello' }])
      
      expect(result).to include(
        content: 'Hello! How can I assist you today?',
        role: 'assistant',
        finish_reason: 'end_turn',
        provider: :anthropic
      )
    end

    it 'handles system messages correctly' do
      expect(mock_http).to receive(:post)
        .with(
          anything,
          hash_including(
            system: 'You are a helpful assistant',
            messages: [{ role: 'user', content: 'Hello' }]
          ),
          anything
        )
        .and_return(successful_response)

      subject.chat(messages: [
        { role: 'system', content: 'You are a helpful assistant' },
        { role: 'user', content: 'Hello' }
      ])
    end

    it 'includes Anthropic-specific options' do
      expect(mock_http).to receive(:post)
        .with(
          anything,
          hash_including(
            top_p: 0.9,
            top_k: 50,
            stop_sequences: ['Human:', 'AI:']
          ),
          anything
        )
        .and_return(successful_response)

      subject.chat(
        messages: [{ role: 'user', content: 'Hello' }],
        top_p: 0.9,
        top_k: 50,
        stop_sequences: ['Human:', 'AI:']
      )
    end

    it 'formats usage information correctly' do
      expect(mock_http).to receive(:post).and_return(successful_response)
      
      result = subject.chat(messages: [{ role: 'user', content: 'Hello' }])
      
      expect(result[:usage]).to include(
        'prompt_tokens' => 10,
        'completion_tokens' => 20,
        'total_tokens' => 30
      )
    end

    it 'handles API errors with detailed messages' do
      error_response = double('Response',
                             status: 400,
                             body: {
                               'error' => {
                                 'message' => 'Invalid request format'
                               }
                             })
      
      allow(mock_http).to receive(:post).and_return(error_response)
      
      expect { subject.chat(messages: ['Hello']) }
        .to raise_error(RCrewAI::LLMClients::APIError, /Invalid request format/)
    end
  end

  describe '#models' do
    it 'returns known Claude models' do
      models = subject.models
      expect(models).to include(
        'claude-3-opus-20240229',
        'claude-3-sonnet-20240229',
        'claude-3-haiku-20240307',
        'claude-2.1'
      )
    end
  end

  describe '#format_messages' do
    it 'converts messages to Anthropic format' do
      messages = [
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there!' }
      ]
      
      formatted = subject.send(:format_messages, messages)
      
      expect(formatted).to eq([
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there!' }
      ])
    end

    it 'converts string messages to user messages' do
      formatted = subject.send(:format_messages, ['Hello'])
      expect(formatted).to eq([{ role: 'user', content: 'Hello' }])
    end
  end

  describe '#extract_system_message' do
    it 'extracts system message content' do
      messages = [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
      
      system_content = subject.send(:extract_system_message, messages)
      expect(system_content).to eq('You are helpful')
    end

    it 'returns nil when no system message' do
      messages = [{ role: 'user', content: 'Hello' }]
      system_content = subject.send(:extract_system_message, messages)
      expect(system_content).to be_nil
    end
  end

  describe '#validate_config!' do
    it 'requires Anthropic API key' do
      invalid_config = double('Configuration',
                              api_key: nil,
                              anthropic_api_key: nil,
                              model: 'claude-3-sonnet')
      
      expect { described_class.new(invalid_config) }
        .to raise_error(RCrewAI::ConfigurationError, /Anthropic API key is required/)
    end
  end
end