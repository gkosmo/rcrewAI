# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Shared contract both stores must satisfy.
RSpec.shared_examples 'a memory vector store' do
  it 'adds and enumerates records within a scope' do
    store.add(id: '1', text: 'hello', vector: [1.0, 0.0], scope: 'agentA')
    store.add(id: '2', text: 'world', vector: [0.0, 1.0], scope: 'agentA')

    texts = store.all(scope: 'agentA').map { |r| r[:text] }
    expect(texts).to contain_exactly('hello', 'world')
  end

  it 'isolates records by scope' do
    store.add(id: '1', text: 'mine', vector: [1.0, 0.0], scope: 'agentA')
    store.add(id: '2', text: 'yours', vector: [1.0, 0.0], scope: 'agentB')

    expect(store.all(scope: 'agentA').map { |r| r[:text] }).to eq(['mine'])
  end

  it 'searches by cosine similarity within a scope, returning nearest first' do
    store.add(id: 'a', text: 'cats', vector: [1.0, 0.0], scope: 's')
    store.add(id: 'b', text: 'dogs', vector: [0.9, 0.1], scope: 's')
    store.add(id: 'c', text: 'cars', vector: [0.0, 1.0], scope: 's')

    results = store.search([1.0, 0.0], k: 2, scope: 's')
    expect(results.map { |r| r[:text] }).to eq(%w[cats dogs])
  end

  it 'does not return records from other scopes in search' do
    store.add(id: 'a', text: 'here', vector: [1.0, 0.0], scope: 's1')
    store.add(id: 'b', text: 'there', vector: [1.0, 0.0], scope: 's2')

    results = store.search([1.0, 0.0], k: 5, scope: 's1')
    expect(results.map { |r| r[:text] }).to eq(['here'])
  end

  it 'preserves metadata round-trip' do
    store.add(id: '1', text: 't', vector: [1.0], scope: 's', metadata: { 'success' => true, 'n' => 3 })

    record = store.all(scope: 's').first
    expect(record[:metadata]).to eq({ 'success' => true, 'n' => 3 })
  end

  it 'upserts on duplicate id' do
    store.add(id: '1', text: 'first', vector: [1.0], scope: 's')
    store.add(id: '1', text: 'second', vector: [1.0], scope: 's')

    expect(store.all(scope: 's').map { |r| r[:text] }).to eq(['second'])
  end

  it 'deletes a scope' do
    store.add(id: '1', text: 'x', vector: [1.0], scope: 's')
    store.delete(scope: 's')

    expect(store.all(scope: 's')).to be_empty
  end

  it 'handles records with nil vectors (returns them via all, skips them in vector search)' do
    store.add(id: '1', text: 'novec', vector: nil, scope: 's')

    expect(store.all(scope: 's').map { |r| r[:text] }).to eq(['novec'])
    expect(store.search([1.0], k: 3, scope: 's')).to eq([])
  end
end

RSpec.describe RCrewAI::Memory::InMemoryStore do
  subject(:store) { described_class.new }

  it_behaves_like 'a memory vector store'
end

RSpec.describe RCrewAI::Memory::SqliteStore do
  around do |example|
    Dir.mktmpdir do |dir|
      @db_path = File.join(dir, 'memory.db')
      example.run
    end
  end

  subject(:store) { described_class.new(path: @db_path) }

  it_behaves_like 'a memory vector store'

  it 'persists across store instances (survives a reopen)' do
    store.add(id: '1', text: 'durable', vector: [1.0, 0.0], scope: 's')

    reopened = described_class.new(path: @db_path)
    expect(reopened.all(scope: 's').map { |r| r[:text] }).to eq(['durable'])
    expect(reopened.search([1.0, 0.0], k: 1, scope: 's').first[:text]).to eq('durable')
  end

  describe 'bounded candidate set for scale' do
    it 'only cosines the most-recent-N candidates (max_candidates)' do
      bounded = described_class.new(path: @db_path, max_candidates: 2)
      # Add an old best-match, then two newer non-matches.
      bounded.add(id: 'old', text: 'perfect', vector: [1.0, 0.0], scope: 's')
      bounded.add(id: 'n1', text: 'newer1', vector: [0.0, 1.0], scope: 's')
      bounded.add(id: 'n2', text: 'newer2', vector: [0.0, 1.0], scope: 's')

      # With a candidate cap of 2, the old perfect match is outside the window
      # and is not considered.
      results = bounded.search([1.0, 0.0], k: 3, scope: 's')
      expect(results.map { |r| r[:text] }).not_to include('perfect')
      expect(results.length).to eq(2)
    end

    it 'considers all candidates when the cap is not exceeded' do
      bounded = described_class.new(path: @db_path, max_candidates: 100)
      bounded.add(id: 'a', text: 'match', vector: [1.0, 0.0], scope: 's')
      bounded.add(id: 'b', text: 'other', vector: [0.0, 1.0], scope: 's')

      expect(bounded.search([1.0, 0.0], k: 1, scope: 's').first[:text]).to eq('match')
    end
  end
end
