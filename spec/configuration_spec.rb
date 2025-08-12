# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Configuration do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(config.llm_provider).to eq(:openai)
      expect(config.model).to eq('gpt-4')
      expect(config.temperature).to eq(0.1)
      expect(config.max_tokens).to eq(4000)
      expect(config.timeout).to eq(120)
    end

    it 'loads environment variables' do
      allow(ENV).to receive(:[]).and_return(nil)
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-anthropic-key')
      allow(ENV).to receive(:[]).with('CLAUDE_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('GEMINI_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('AZURE_OPENAI_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('LLM_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('LLM_BASE_URL').and_return(nil)
      allow(ENV).to receive(:[]).with('AZURE_API_VERSION').and_return(nil)
      allow(ENV).to receive(:[]).with('AZURE_DEPLOYMENT_NAME').and_return(nil)
      
      config = described_class.new
      expect(config.openai_api_key).to eq('test-openai-key')
      expect(config.anthropic_api_key).to eq('test-anthropic-key')
    end
  end

  describe '#api_key' do
    it 'returns provider-specific api key' do
      config.llm_provider = :openai
      config.openai_api_key = 'openai-key'
      config.anthropic_api_key = 'anthropic-key'
      
      expect(config.api_key).to eq('openai-key')
      
      config.llm_provider = :anthropic
      expect(config.api_key).to eq('anthropic-key')
    end

    it 'falls back to generic api_key' do
      config.llm_provider = :openai
      config.instance_variable_set(:@api_key, 'generic-key')
      
      expect(config.api_key).to eq('generic-key')
    end
  end

  describe '#model' do
    it 'returns provider-specific model' do
      config.llm_provider = :openai
      config.openai_model = 'gpt-4'
      config.anthropic_model = 'claude-3-sonnet'
      
      expect(config.model).to eq('gpt-4')
      
      config.llm_provider = :anthropic
      expect(config.model).to eq('claude-3-sonnet')
    end

    it 'falls back to generic model' do
      config.llm_provider = :openai
      config.instance_variable_set(:@model, 'generic-model')
      config.instance_variable_set(:@openai_model, nil)
      
      expect(config.model).to eq('generic-model')
    end
  end

  describe '#validate!' do
    it 'validates required fields' do
      config.llm_provider = nil
      expect { config.validate! }.to raise_error(RCrewAI::ConfigurationError, /LLM provider must be set/)
      
      config.llm_provider = :openai
      expect { config.validate! }.to raise_error(RCrewAI::ConfigurationError, /API key must be set/)
      
      config.openai_api_key = 'test-key'
      config.instance_variable_set(:@model, nil)
      config.instance_variable_set(:@openai_model, nil)
      expect { config.validate! }.to raise_error(RCrewAI::ConfigurationError, /Model must be set/)
    end

    it 'passes validation with all required fields' do
      config.llm_provider = :openai
      config.openai_api_key = 'test-key'
      config.openai_model = 'gpt-4'
      
      expect { config.validate! }.not_to raise_error
    end
  end

  describe '#supported_providers' do
    it 'returns all supported providers' do
      expect(config.supported_providers).to eq([:openai, :anthropic, :google, :azure, :ollama])
    end
  end

  describe '#provider_supported?' do
    it 'returns true for supported providers' do
      expect(config.provider_supported?(:openai)).to be true
      expect(config.provider_supported?('anthropic')).to be true
    end

    it 'returns false for unsupported providers' do
      expect(config.provider_supported?(:unknown)).to be false
    end
  end
end

RSpec.describe RCrewAI do
  describe '.configure' do
    it 'yields configuration object' do
      expect { |b| RCrewAI.configure(validate: false, &b) }.to yield_with_args(RCrewAI::Configuration)
    end

    it 'validates configuration after block' do
      expect {
        RCrewAI.configure do |config|
          config.llm_provider = nil
        end
      }.to raise_error(RCrewAI::ConfigurationError)
    end

    it 'sets configuration values' do
      RCrewAI.configure do |config|
        config.llm_provider = :anthropic
        config.anthropic_api_key = 'test-key'
        config.temperature = 0.5
      end

      expect(RCrewAI.configuration.llm_provider).to eq(:anthropic)
      expect(RCrewAI.configuration.temperature).to eq(0.5)
    end
  end

  describe '.reset_configuration!' do
    it 'resets configuration to defaults' do
      RCrewAI.configure(validate: false) do |config|
        config.temperature = 0.9
        config.anthropic_api_key = 'test-key'
      end

      RCrewAI.reset_configuration!

      expect(RCrewAI.configuration.temperature).to eq(0.1)
      expect(RCrewAI.configuration.anthropic_api_key).to be_nil
    end
  end
end