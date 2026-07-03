# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::RateLimiter do
  # A controllable clock + sleep so tests never touch the wall clock.
  let(:now) { [1000.0] }
  let(:clock) { -> { now[0] } }
  let(:slept) { [] }
  let(:sleeper) do
    lambda do |seconds|
      slept << seconds
      now[0] += seconds
    end
  end

  def limiter(max_rpm)
    described_class.new(max_rpm: max_rpm, clock: clock, sleeper: sleeper)
  end

  it 'does not sleep while under the limit' do
    rl = limiter(3)

    3.times { rl.acquire }

    expect(slept).to be_empty
  end

  it 'sleeps until the oldest call falls outside the 60s window' do
    rl = limiter(2)

    rl.acquire # t=1000
    rl.acquire # t=1000, now at capacity within the window
    rl.acquire # must wait until the first call ages out (t=1060)

    expect(slept.sum).to be_within(0.001).of(60.0)
  end

  it 'allows a call once earlier calls age out of the window' do
    rl = limiter(1)

    rl.acquire            # t=1000
    now[0] += 61          # advance past the window manually
    rl.acquire            # should not need to sleep

    expect(slept).to be_empty
  end

  it 'treats max_rpm nil or 0 as unlimited (never sleeps)' do
    [nil, 0].each do |cap|
      rl = limiter(cap)
      10.times { rl.acquire }
    end

    expect(slept).to be_empty
  end

  it 'is safe to call concurrently' do
    rl = described_class.new(max_rpm: 1000) # high cap so no sleeping
    threads = Array.new(10) { Thread.new { 50.times { rl.acquire } } }
    threads.each(&:join)

    # 500 calls recorded without raising / corrupting internal state
    expect(rl.recent_count).to be <= 1000
  end
end

RSpec.describe 'RateLimiter wiring into Agent' do
  before { configure_test_llm }

  it 'routes chat calls through a limiter when max_rpm is set' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', max_rpm: 5)

    expect(agent.llm_client).to respond_to(:chat)
    expect(agent.rate_limiter).to be_a(RCrewAI::RateLimiter)
  end

  it 'calls the underlying client and acquires a slot per chat' do
    inner = instance_double(RCrewAI::LLMClients::Base, chat: { content: 'hi' })
    limiter = instance_spy(RCrewAI::RateLimiter)

    throttled = RCrewAI::RateLimiter::ThrottledClient.new(inner, limiter)
    result = throttled.chat(messages: [])

    expect(limiter).to have_received(:acquire).once
    expect(inner).to have_received(:chat).with(messages: [])
    expect(result).to eq({ content: 'hi' })
  end

  it 'leaves the client unwrapped when max_rpm is not set' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')

    expect(agent.rate_limiter).to be_nil
    expect(agent.llm_client).not_to be_a(RCrewAI::RateLimiter::ThrottledClient)
  end
end
