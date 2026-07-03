# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::ContextWindow do
  describe '.estimate_tokens' do
    it 'estimates roughly chars/4' do
      expect(described_class.estimate_tokens('a' * 40)).to eq(10)
    end

    it 'sums across a message list' do
      msgs = [{ role: 'user', content: 'a' * 20 }, { role: 'assistant', content: 'b' * 20 }]
      expect(described_class.estimate_tokens(msgs)).to eq(10)
    end
  end

  describe '.window_for' do
    it 'knows common models' do
      expect(described_class.window_for('gpt-4o')).to eq(128_000)
      expect(described_class.window_for('gpt-3.5-turbo')).to eq(16_385)
    end

    it 'falls back to a conservative default for unknown models' do
      expect(described_class.window_for('some-unknown-model')).to eq(described_class::DEFAULT_WINDOW)
    end
  end

  describe '.fit' do
    def msg(role, size) = { role: role, content: 'x' * size }

    it 'returns messages unchanged when they already fit' do
      msgs = [msg('system', 40), msg('user', 40)]
      expect(described_class.fit(msgs, limit: 1000)).to eq(msgs)
    end

    it 'drops the oldest non-system messages until it fits' do
      msgs = [
        msg('system', 40),   # 10 tokens, always kept
        msg('user', 400),    # 100 tokens, oldest — dropped first
        msg('assistant', 400), # 100 tokens
        msg('user', 40) # 10 tokens, last user — always kept
      ]
      # limit 130 tokens: system(10) + last user(10) = 20 must stay; only one of
      # the middle messages (100 each) can fit.
      result = described_class.fit(msgs, limit: 130)

      expect(result.first[:role]).to eq('system')
      expect(result.last[:content]).to eq('x' * 40)
      expect(result.length).to eq(3) # dropped exactly the oldest middle message
    end

    it 'always keeps system messages even under extreme pressure' do
      msgs = [msg('system', 400), msg('user', 400), msg('user', 400)]
      result = described_class.fit(msgs, limit: 1)

      expect(result.map { |m| m[:role] }).to include('system')
      expect(result.last[:role]).to eq('user') # last message preserved
    end

    it 'reserves headroom for the response' do
      msgs = [msg('system', 40), msg('user', 400), msg('user', 40)]
      # window 130, reserve 100 -> effective limit 30 tokens; middle msg drops.
      result = described_class.fit(msgs, limit: 130, reserve: 100)

      expect(result.length).to eq(2)
      expect(result.map { |m| m[:role] }).to eq(%w[system user])
    end
  end
end

RSpec.describe 'ContextWindow wiring into Agent' do
  before { configure_test_llm(provider: :openai, model: 'gpt-3.5-turbo') }

  let(:big_history) do
    [
      { role: 'system', content: 'You are helpful.' },
      { role: 'user', content: 'x' * 400_000 }, # ~100k tokens, over the window
      { role: 'user', content: 'final question' }
    ]
  end

  it 'trims messages when respect_context_window is enabled' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', respect_context_window: true)

    fitted = agent.fit_context(big_history)

    tokens = RCrewAI::ContextWindow.estimate_tokens(fitted)
    expect(tokens).to be < RCrewAI::ContextWindow.window_for('gpt-3.5-turbo')
    expect(fitted.first[:role]).to eq('system')
    expect(fitted.last[:content]).to eq('final question')
  end

  it 'leaves messages untouched when disabled (default)' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')

    expect(agent.fit_context(big_history)).to eq(big_history)
  end
end
