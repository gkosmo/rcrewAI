# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Pricing do
  it 'computes cost for a known model' do
    cost = described_class.cost_for('gpt-4o', prompt_tokens: 1_000_000, completion_tokens: 1_000_000)
    expect(cost).to be > 0
  end

  # Anthropic's published prices, per 1M tokens.
  { 'claude-fable-5-1' => [10.00, 50.00], 'claude-fable-5' => [10.00, 50.00], 'claude-opus-5-5' => [4.00, 20.00],
    'claude-sonnet-5-5' => [2.00, 10.00], 'claude-haiku-5-5' => [0.10, 0.50] }.each do |model, (input, output)|
    it "prices #{model}" do
      expect(described_class.cost_for(model, prompt_tokens: 100_000, completion_tokens: 0)).to eq(input / 10)
      expect(described_class.cost_for(model, prompt_tokens: 0, completion_tokens: 100_000)).to eq(output / 10)
    end
  end

  it 'charges the higher Haiku 5.5 rate for all of a prompt over 100K tokens' do
    expect(described_class.cost_for('claude-haiku-5-5', prompt_tokens: 100_001, completion_tokens: 100_000))
      .to be_within(1e-9).of((100_001 * 0.50 / 1_000_000) + 0.25)
  end

  it 'prices each default model' do
    RCrewAI::Configuration::DEFAULT_MODELS.each_value do |model|
      expect(described_class.cost_for(model, prompt_tokens: 1, completion_tokens: 1)).not_to be_nil
    end
  end

  it 'returns nil for unknown model' do
    cost = described_class.cost_for('definitely-not-real', prompt_tokens: 1, completion_tokens: 1)
    expect(cost).to be_nil
  end

  it 'accepts user overrides from configuration' do
    RCrewAI.configuration.pricing = { 'totally-fake' => { input: 1.0, output: 2.0 } }
    cost = described_class.cost_for('totally-fake', prompt_tokens: 1_000_000, completion_tokens: 1_000_000)
    expect(cost).to eq(3.0)
  ensure
    RCrewAI.configuration.pricing = nil
  end
end
