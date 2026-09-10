# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe 'knowledge base build with concurrent embedding' do
  it 'pairs each chunk with its own vector' do
    config = RCrewAI.configuration.tap { |c| c.base_url = 'http://localhost:11434' }

    # Vector encodes the text length, so a mispairing is detectable.
    stub_request(:post, %r{/api/embeddings}).to_return do |req|
      text = JSON.parse(req.body)['prompt']
      sleep(text.include?('AAA') ? 0.2 : 0.01)
      { status: 200, body: { 'embedding' => [text.length.to_f] }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end

    sources = [
      RCrewAI::Knowledge::StringSource.new('AAA' * 40),
      RCrewAI::Knowledge::StringSource.new('B' * 30),
      RCrewAI::Knowledge::StringSource.new('C' * 10)
    ]
    embedder = RCrewAI::Knowledge::Embedder.new(provider: :ollama, config: config)
    kb = RCrewAI::Knowledge::Base.new(sources: sources, embedder: embedder, chunk_size: 1000)
    kb.build!

    entries = kb.instance_variable_get(:@store).instance_variable_get(:@entries)
    entries.each do |e|
      expect(e.vector.first).to eq(e.text.length.to_f),
                                "chunk of length #{e.text.length} got vector #{e.vector.first} — mispaired"
    end
  end
end
