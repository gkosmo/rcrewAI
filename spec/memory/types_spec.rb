# frozen_string_literal: true

require 'spec_helper'

# A fake embedder that maps texts to vectors by concept, so we can prove
# *semantic* recall independent of shared words.
class ConceptEmbedder
  # concept => unit vector
  CONCEPTS = {
    'feline' => [1.0, 0.0, 0.0],
    'canine' => [0.0, 1.0, 0.0],
    'vehicle' => [0.0, 0.0, 1.0]
  }.freeze

  def embed(texts)
    texts.map do |t|
      case t.downcase
      when /cat|kitten|feline|meow/ then CONCEPTS['feline']
      when /dog|puppy|canine|bark/ then CONCEPTS['canine']
      when /car|truck|vehicle|drive/ then CONCEPTS['vehicle']
      else [0.3, 0.3, 0.3]
      end
    end
  end
end

RSpec.describe RCrewAI::Memory::ShortTermMemory do
  let(:embedder) { ConceptEmbedder.new }
  subject(:mem) { described_class.new(scope: 'agentX', embedder: embedder) }

  it 'recalls the semantically closest record, not the keyword-overlapping one' do
    mem.record('The kitten chased a laser pointer', {})
    mem.record('The puppy learned to fetch', {})
    mem.record('I drove the truck to the depot', {})

    # Query shares NO content words with the cat record, but is conceptually feline.
    results = mem.recall('a meowing feline on the sofa', limit: 1)

    expect(results.first[:text]).to eq('The kitten chased a laser pointer')
  end

  it 'caps stored records at its limit (oldest evicted)' do
    small = described_class.new(scope: 'agentX', embedder: embedder, limit: 2)
    small.record('one', {})
    small.record('two', {})
    small.record('three', {})

    expect(small.count).to eq(2)
  end
end

RSpec.describe 'memory recall without an embedder (lexical fallback)' do
  subject(:mem) { RCrewAI::Memory::ShortTermMemory.new(scope: 'a', embedder: nil) }

  it 'still recalls via word overlap' do
    mem.record('research the ruby programming language', {})
    mem.record('bake a chocolate cake', {})

    results = mem.recall('ruby programming questions', limit: 1)
    expect(results.first[:text]).to eq('research the ruby programming language')
  end
end

RSpec.describe RCrewAI::Memory::LongTermMemory do
  let(:embedder) { ConceptEmbedder.new }
  subject(:mem) { described_class.new(scope: 'agentX', embedder: embedder) }

  it 'stores insights and dedupes near-identical ones' do
    mem.record('cats are independent pets', {})
    mem.record('kittens are independent felines', {}) # semantically ~identical

    expect(mem.count).to eq(1)
  end

  it 'keeps semantically distinct insights' do
    mem.record('cats are independent pets', {})
    mem.record('trucks haul heavy cargo', {})

    expect(mem.count).to eq(2)
  end
end

RSpec.describe RCrewAI::Memory::EntityMemory do
  subject(:mem) { described_class.new(scope: 'agentX', embedder: nil) }

  it 'extracts capitalized entities from text' do
    mem.observe('Alice deployed the service to AWS while Bob reviewed the code')

    names = mem.entities
    expect(names).to include('Alice', 'Bob', 'AWS')
  end

  it 'recalls entity facts relevant to a query' do
    mem.observe('Alice is the lead engineer on the Payments team')
    mem.observe('Redis is used for the rate limiter')

    facts = mem.recall('who works on payments', limit: 2)
    expect(facts.join).to include('Alice')
  end
end

RSpec.describe RCrewAI::Memory::ToolMemory do
  subject(:mem) { described_class.new(scope: 'agentX', embedder: nil) }

  it 'records tool calls and returns recent usage for a tool' do
    mem.record_call('web_search', { 'q' => 'ruby' }, 'result A')
    mem.record_call('web_search', { 'q' => 'python' }, 'result B')
    mem.record_call('calculator', { 'x' => 1 }, '2')

    usage = mem.usage_for('web_search', limit: 5)
    expect(usage.length).to eq(2)
    expect(usage.join).to include('ruby').and include('python')
  end
end
