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

    it 'shares the OpenAI api key with the Responses provider' do
      config.llm_provider = :openai_responses
      config.openai_api_key = 'openai-key'

      expect(config.api_key).to eq('openai-key')
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

    it 'honours config.model over the provider default' do
      %i[openai anthropic google azure].each do |provider|
        config = described_class.new
        config.llm_provider = provider
        config.model = 'my-model'

        expect(config.model).to eq('my-model')
      end
    end

    it 'honours config.model regardless of assignment order' do
      config.model = 'my-model'
      config.llm_provider = :anthropic

      expect(config.model).to eq('my-model')
    end

    it 'prefers an explicit provider model over config.model' do
      config.model = 'generic-model'
      config.openai_model = 'specific-model'

      expect(config.model).to eq('specific-model')
    end

    it 'shares OpenAI model settings with the Responses provider' do
      config.llm_provider = :openai_responses
      expect(config.model).to eq(described_class::DEFAULT_MODELS[:openai])

      config.openai_model = 'gpt-5'
      expect(config.model).to eq('gpt-5')
    end

    it 'falls back to the provider default when nothing is set' do
      config.llm_provider = :anthropic

      expect(config.model).to eq(config.anthropic_model)
      expect(config.model).to eq(described_class::DEFAULT_MODELS[:anthropic])
    end
  end

  describe '#validate!' do
    it 'validates required fields' do
      config.llm_provider = nil
      expect { config.validate! }.to raise_error(RCrewAI::ConfigurationError, /LLM provider must be set/)

      config.llm_provider = :openai
      expect { config.validate! }.to raise_error(RCrewAI::ConfigurationError, /API key must be set/)

      config.llm_provider = :bedrock
      config.api_key = 'test-key'
      expect { config.validate! }.to raise_error(RCrewAI::ConfigurationError, /Model must be set/)
    end

    it 'does not require an API key for ollama' do
      config.llm_provider = :ollama
      config.model = 'llama3.1'

      expect { config.validate! }.not_to raise_error
    end

    it 'still requires a model for ollama' do
      config.llm_provider = :ollama

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
      expect(config.supported_providers).to eq(RCrewAI::LLMClient::PROVIDERS.keys)
      expect(config.supported_providers).to include(:bedrock, :snowflake, :openai_compatible, :openai_responses)
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

  describe '#explicit_temperature' do
    it 'is nil until a temperature is set' do
      expect(config.temperature).to eq(described_class::DEFAULT_TEMPERATURE)
      expect(config.explicit_temperature).to be_nil
    end

    it 'returns a temperature the user set, even if it equals the default' do
      config.temperature = described_class::DEFAULT_TEMPERATURE

      expect(config.explicit_temperature).to eq(described_class::DEFAULT_TEMPERATURE)
    end
  end

  describe 'default models' do
    it 'uses current Anthropic and Google models' do
      expect(described_class::DEFAULT_MODELS).to include(anthropic: 'claude-opus-5-5', google: 'gemini-3.8-flash')
    end

    it 'has a price and context window for each default Anthropic and Google model' do
      described_class::DEFAULT_MODELS.values_at(:anthropic, :google).each do |model|
        expect(RCrewAI::Pricing::DEFAULT_PRICES).to have_key(model)
        expect(RCrewAI::ContextWindow::WINDOWS).to have_key(model)
      end
    end
  end

  describe '#with_overrides' do
    let(:base) do
      described_class.new.tap do |c|
        c.llm_provider = :openai
        c.openai_api_key = 'global-openai-key'
        c.temperature = 0.1
      end
    end

    it 'returns a new configuration, leaving the original untouched' do
      overridden = base.with_overrides(provider: :anthropic)

      expect(overridden).not_to equal(base)
      expect(base.llm_provider).to eq(:openai)
    end

    it 'overrides the provider' do
      overridden = base.with_overrides(provider: :anthropic)

      expect(overridden.llm_provider).to eq(:anthropic)
    end

    it 'overrides the model for the selected provider' do
      overridden = base.with_overrides(provider: :anthropic, model: 'claude-3-opus-20240229')

      expect(overridden.model).to eq('claude-3-opus-20240229')
    end

    it 'overrides the api_key for the selected provider' do
      overridden = base.with_overrides(provider: :anthropic, api_key: 'per-agent-key')

      expect(overridden.api_key).to eq('per-agent-key')
    end

    it 'does not carry a global config.model across to another provider' do
      base.model = 'gpt-4o'

      expect(base.with_overrides(provider: :anthropic).model).to eq(described_class::DEFAULT_MODELS[:anthropic])
    end

    it 'keeps a global config.model when the provider is unchanged' do
      base.model = 'gpt-4o'

      expect(base.with_overrides(provider: :openai).model).to eq('gpt-4o')
      expect(base.with_overrides(temperature: 0.9).model).to eq('gpt-4o')
    end

    it 'applies a per-agent model on the Responses provider over the global OpenAI model' do
      base.openai_model = 'gpt-4o'

      overridden = base.with_overrides(provider: :openai_responses, model: 'gpt-5')

      expect(overridden.model).to eq('gpt-5')
      expect(base.openai_model).to eq('gpt-4o')
    end

    it 'can clear the temperature with an explicit nil' do
      overridden = base.with_overrides(temperature: nil)

      expect(overridden.temperature).to be_nil
      expect(base.temperature).to eq(0.1)
    end

    it 'keeps the temperature when no override is given' do
      expect(base.with_overrides(provider: :anthropic).temperature).to eq(0.1)
    end

    it 'overrides temperature' do
      overridden = base.with_overrides(temperature: 0.9)

      expect(overridden.temperature).to eq(0.9)
    end

    it 'inherits unspecified values from the base config' do
      overridden = base.with_overrides(model: 'gpt-4o')

      expect(overridden.llm_provider).to eq(:openai)
      expect(overridden.api_key).to eq('global-openai-key')
      expect(overridden.temperature).to eq(0.1)
    end
  end
end

RSpec.describe RCrewAI do
  describe '.configure' do
    it 'yields configuration object' do
      expect { |b| RCrewAI.configure(validate: false, &b) }.to yield_with_args(RCrewAI::Configuration)
    end

    it 'validates configuration after block' do
      expect do
        RCrewAI.configure do |config|
          config.llm_provider = nil
        end
      end.to raise_error(RCrewAI::ConfigurationError)
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
