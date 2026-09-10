# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe 'concurrent embedding' do
  # Each stubbed request sleeps, so serial vs concurrent shows up as wall clock.
  def slow_stub(url_pattern, body, delay: 0.12)
    stub_request(:post, url_pattern).to_return do
      sleep delay
      { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  let(:texts) { %w[alpha beta gamma delta] }

  describe 'google' do
    let(:config) do
      RCrewAI.configuration.tap do |c|
        c.llm_provider = :google
        c.google_api_key = 'k'
      end
    end

    it 'embeds several texts concurrently' do
      slow_stub(/generativelanguage\.googleapis\.com/, { 'embedding' => { 'values' => [0.1, 0.2] } })
      embedder = RCrewAI::Knowledge::Embedder.new(provider: :google, config: config)

      started = Time.now
      vectors = embedder.embed(texts)
      elapsed = Time.now - started

      expect(vectors.size).to eq(4)
      expect(elapsed).to be < 0.3,
                         "embedded serially (#{elapsed.round(2)}s for 4 x 0.12s)"
    end

    it 'returns vectors in input order' do
      # Key each response off its own request text, and make the FIRST text the
      # slowest -- so if results were ordered by completion, alpha would land last.
      stub_request(:post, /generativelanguage\.googleapis\.com/).to_return do |req|
        text = JSON.parse(req.body).dig('content', 'parts', 0, 'text')
        sleep(text == 'alpha' ? 0.25 : 0.02)
        { status: 200,
          body: { 'embedding' => { 'values' => [texts.index(text).to_f] } }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end

      embedder = RCrewAI::Knowledge::Embedder.new(provider: :google, config: config)
      vectors = embedder.embed(texts)

      expect(vectors.map(&:first)).to eq([0.0, 1.0, 2.0, 3.0]),
                                      'vectors must follow input order, not completion order'
    end

    it 'still embeds a single text' do
      slow_stub(/generativelanguage\.googleapis\.com/, { 'embedding' => { 'values' => [0.5] } }, delay: 0.01)
      embedder = RCrewAI::Knowledge::Embedder.new(provider: :google, config: config)

      expect(embedder.embed(['solo'])).to eq([[0.5]])
    end

    it 'propagates an error from any one request' do
      stub_request(:post, /generativelanguage\.googleapis\.com/)
        .to_return(status: 500, body: 'boom')
      embedder = RCrewAI::Knowledge::Embedder.new(provider: :google, config: config)

      expect { embedder.embed(texts) }.to raise_error(RCrewAI::Knowledge::EmbeddingError)
    end
  end

  describe 'ollama' do
    let(:config) do
      RCrewAI.configuration.tap do |c|
        c.llm_provider = :ollama
        c.base_url = 'http://localhost:11434'
      end
    end

    it 'embeds several texts concurrently' do
      slow_stub(%r{/api/embeddings}, { 'embedding' => [0.3] })
      embedder = RCrewAI::Knowledge::Embedder.new(provider: :ollama, config: config)

      started = Time.now
      vectors = embedder.embed(texts)
      elapsed = Time.now - started

      expect(vectors.size).to eq(4)
      expect(elapsed).to be < 0.3,
                         "embedded serially (#{elapsed.round(2)}s for 4 x 0.12s)"
    end

    it 'returns vectors in input order' do
      stub_request(:post, %r{/api/embeddings}).to_return do |req|
        text = JSON.parse(req.body)['prompt']
        sleep(text == 'alpha' ? 0.25 : 0.02)
        { status: 200, body: { 'embedding' => [texts.index(text).to_f] }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end

      embedder = RCrewAI::Knowledge::Embedder.new(provider: :ollama, config: config)

      expect(embedder.embed(texts).map(&:first)).to eq([0.0, 1.0, 2.0, 3.0]),
                                                    'vectors must follow input order, not completion order'
    end
  end

  describe 'batching providers are untouched' do
    it 'sends one request for openai regardless of text count' do
      stub = stub_request(:post, 'https://api.openai.com/v1/embeddings')
             .to_return(status: 200,
                        body: { 'data' => texts.map { |_| { 'embedding' => [0.1] } } }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      config = RCrewAI.configuration.tap { |c| c.openai_api_key = 'k' }
      RCrewAI::Knowledge::Embedder.new(provider: :openai, config: config).embed(texts)

      expect(stub).to have_been_requested.once
    end
  end

  describe 'concurrency bound' do
    it 'caps in-flight requests' do
      inflight = 0
      peak = 0
      lock = Mutex.new
      stub_request(:post, %r{/api/embeddings}).to_return do
        lock.synchronize do
          inflight += 1
          peak = [peak, inflight].max
        end
        sleep 0.05
        lock.synchronize { inflight -= 1 }
        { status: 200, body: { 'embedding' => [0.1] }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end

      config = RCrewAI.configuration.tap { |c| c.base_url = 'http://localhost:11434' }
      embedder = RCrewAI::Knowledge::Embedder.new(provider: :ollama, config: config,
                                                  max_concurrency: 2)
      embedder.embed(%w[a b c d e f])

      expect(peak).to be <= 2, "peak in-flight was #{peak}, expected <= 2"
    end
  end
end
