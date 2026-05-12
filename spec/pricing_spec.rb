# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Pricing do
  it 'computes cost for a known model' do
    cost = described_class.cost_for('gpt-4o', prompt_tokens: 1_000_000, completion_tokens: 1_000_000)
    expect(cost).to be > 0
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
