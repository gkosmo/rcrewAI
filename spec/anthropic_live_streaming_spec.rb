# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/fake_sse_server'

# The low-latency streaming path used by real-time callers (voice agents):
# fiber-safe under an Async reactor, cancellable mid-stream, and reusing one
# keep-alive connection across calls.
RSpec.describe RCrewAI::LLMClients::Anthropic, 'live streaming' do
  let(:deltas) { Array.new(10) { |i| "w#{i} " } }
  let(:server) { FakeSSEServer.new(deltas: deltas, delay: 0.02) }
  let(:config) do
    RCrewAI::Configuration.new.tap do |c|
      c.llm_provider = :anthropic
      c.anthropic_api_key = 'test-key'
      c.anthropic_model = 'claude-test'
      c.base_url = server.url
      c.log_level = :error
    end
  end
  let(:client) { described_class.new(config) }
  let(:messages) { [{ role: 'user', content: 'hi' }] }

  # WebMock's Net::HTTP adapter buffers whole responses, which would hide
  # incremental delivery; these specs talk to a real local socket.
  around do |example|
    VCR.turned_off do
      WebMock.disable!
      example.run
    ensure
      WebMock.enable!
    end
  end
  after { server.stop }

  def texts_from(events) = events.select { |e| e.is_a?(RCrewAI::Events::TextDelta) }.map(&:text)

  it 'streams text deltas and reports cache-read tokens in usage' do
    events = []
    result = client.chat(messages: messages, stream: ->(e) { events << e })
    expect(texts_from(events).join).to eq(deltas.join)
    expect(result[:usage]).to include(prompt_tokens: 50, cached_tokens: 40, completion_tokens: 10)
    expect(events.grep(RCrewAI::Events::Usage).last.cached_tokens).to eq(40)
  end

  it 'lets a call override the configured model' do
    client.chat(messages: messages, stream: ->(_) {}, model: 'claude-other')
    expect(server.requests.last[:body]['model']).to eq('claude-other')
  end

  it 'passes pre-built system blocks (with cache_control) through untouched' do
    system = [{ type: 'text', text: 'You are Seneca.', cache_control: { type: 'ephemeral' } }]
    client.chat(messages: [{ role: 'system', content: system }, *messages], stream: ->(_) {})
    expect(server.requests.last[:body]['system']).to eq(JSON.parse(system.to_json))
  end

  it 'reuses one keep-alive connection across streaming calls' do
    3.times { client.chat(messages: messages, stream: ->(_) {}) }
    expect(server.requests.size).to eq(3)
    expect(server.connections).to eq(1)
  end

  describe 'cancellation' do
    it 'stops a stream when its cancel token is triggered, then reconnects for the next call' do
      token = RCrewAI::CancelToken.new
      seen = []
      expect do
        client.chat(messages: messages, cancel: token, stream: lambda { |e|
          next unless e.is_a?(RCrewAI::Events::TextDelta)

          seen << e.text
          token.cancel! if seen.size == 3
        })
      end.to raise_error(RCrewAI::StreamCancelled)
      expect(seen.size).to eq(3)

      events = []
      client.chat(messages: messages, stream: ->(e) { events << e })
      expect(texts_from(events).size).to eq(10)
      expect(server.connections).to eq(2)
    end
  end

  describe 'under an Async reactor', if: RUBY_VERSION >= '3.2' do
    before { require 'async' }

    it 'does not block other fibers while streaming' do
      gaps = []
      Sync do |task|
        running = true
        ticker = task.async do
          last = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          while running
            sleep 0.01
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            gaps << now - last
            last = now
          end
        end
        client.chat(messages: messages, stream: ->(_) {})
        running = false
        ticker.wait
      end
      expect(gaps.size).to be >= 10
      expect(gaps.max).to be < 0.05
    end

    it 'closes the stream within 100ms when the calling task is stopped' do
      seen = []
      Sync do |task|
        call = task.async { client.chat(messages: messages, stream: ->(e) { seen << e if e.is_a?(RCrewAI::Events::TextDelta) }) }
        sleep 0.01 until seen.size >= 2
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        call.stop
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.1
      end
      sleep 0.1
      expect(seen.size).to be < 10
      expect(server.aborted).to eq(1)

      events = []
      client.chat(messages: messages, stream: ->(e) { events << e })
      expect(texts_from(events).size).to eq(10)
    end
  end
end
