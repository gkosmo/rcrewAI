# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Knowledge::Embedder do
  let(:vectors) { [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]] }

  describe 'OpenAI (default)' do
    it 'posts to the OpenAI embeddings endpoint and returns vectors' do
      stub = stub_request(:post, 'https://api.openai.com/v1/embeddings')
             .with(body: hash_including('model' => 'text-embedding-3-small',
                                        'input' => %w[a b]))
             .to_return(status: 200, body: JSON.generate(
               data: [{ embedding: vectors[0] }, { embedding: vectors[1] }]
             ))

      embedder = described_class.new(api_key: 'sk-test')
      result = embedder.embed(%w[a b])

      expect(result).to eq(vectors)
      expect(stub).to have_been_requested
    end

    it 'defaults the provider to :openai' do
      expect(described_class.new(api_key: 'k').provider).to eq(:openai)
    end
  end

  describe 'Ollama (local)' do
    it 'posts per-text to the Ollama embeddings endpoint' do
      stub_request(:post, 'http://localhost:11434/api/embeddings')
        .to_return(status: 200, body: JSON.generate(embedding: [0.7, 0.8]))

      embedder = described_class.new(provider: :ollama, model: 'nomic-embed-text')
      result = embedder.embed(%w[x y])

      expect(result).to eq([[0.7, 0.8], [0.7, 0.8]])
    end
  end

  describe 'Google' do
    it 'posts to the Gemini embedContent endpoint' do
      stub_request(:post, /generativelanguage\.googleapis\.com.*embedContent/)
        .to_return(status: 200, body: JSON.generate(embedding: { values: [0.9, 1.0] }))

      embedder = described_class.new(provider: :google, model: 'text-embedding-004', api_key: 'g-key')
      result = embedder.embed(['hello'])

      expect(result).to eq([[0.9, 1.0]])
    end
  end

  describe 'Azure' do
    it 'posts to the Azure OpenAI deployment embeddings endpoint' do
      config = RCrewAI::Configuration.new
      config.base_url = 'https://my.openai.azure.com'
      config.api_version = '2024-02-01'
      config.deployment_name = 'embed-deploy'
      config.azure_api_key = 'az-key'

      stub_request(:post, %r{my\.openai\.azure\.com/openai/deployments/embed-deploy/embeddings})
        .to_return(status: 200, body: JSON.generate(data: [{ embedding: [1.1, 1.2] }]))

      embedder = described_class.new(provider: :azure, config: config)
      expect(embedder.embed(['hi'])).to eq([[1.1, 1.2]])
    end
  end

  describe 'Anthropic (no first-party embeddings)' do
    it 'raises a clear, actionable error' do
      expect { described_class.new(provider: :anthropic) }
        .to raise_error(RCrewAI::Knowledge::EmbeddingError, /anthropic.*does not.*embedding/i)
    end
  end

  describe 'errors' do
    it 'raises EmbeddingError on a non-2xx response' do
      stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return(status: 500)

      expect { described_class.new(api_key: 'k').embed(['x']) }
        .to raise_error(RCrewAI::Knowledge::EmbeddingError, /500/)
    end

    it 'returns [] for empty input without calling the API' do
      expect(described_class.new(api_key: 'k').embed([])).to eq([])
    end
  end
end
