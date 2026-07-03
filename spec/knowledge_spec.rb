# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RCrewAI::Knowledge::Chunker do
  it 'returns the whole text as one chunk when shorter than chunk_size' do
    chunks = described_class.new(chunk_size: 100, overlap: 10).chunk('short text')

    expect(chunks).to eq(['short text'])
  end

  it 'splits long text into overlapping chunks' do
    text = ('a'..'z').to_a.join # 26 chars
    chunks = described_class.new(chunk_size: 10, overlap: 2).chunk(text)

    expect(chunks.length).to be > 1
    expect(chunks.first.length).to eq(10)
    # consecutive chunks overlap by `overlap` characters
    expect(chunks[1][0, 2]).to eq(chunks[0][-2, 2])
  end

  it 'ignores empty input' do
    expect(described_class.new.chunk('')).to eq([])
  end
end

RSpec.describe RCrewAI::Knowledge::Store do
  it 'returns the most similar chunks by cosine similarity' do
    store = described_class.new
    store.add('cats', [1.0, 0.0])
    store.add('dogs', [0.9, 0.1])
    store.add('cars', [0.0, 1.0])

    results = store.search([1.0, 0.0], k: 2)

    expect(results).to eq(%w[cats dogs])
  end

  it 'returns fewer than k results when the store is small' do
    store = described_class.new
    store.add('only', [1.0, 0.0])

    expect(store.search([1.0, 0.0], k: 5)).to eq(['only'])
  end

  it 'returns nothing when empty' do
    expect(described_class.new.search([1.0], k: 3)).to eq([])
  end
end

RSpec.describe RCrewAI::Knowledge::StringSource do
  it 'yields its text' do
    expect(described_class.new('hello world').read).to eq('hello world')
  end
end

RSpec.describe RCrewAI::Knowledge::FileSource do
  it 'reads a text file' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'doc.txt')
      File.write(path, 'file contents')

      expect(described_class.new(path).read).to eq('file contents')
    end
  end
end

RSpec.describe RCrewAI::Knowledge::Base do
  # A deterministic fake embedder: each text maps to a 2D vector so we can
  # reason about similarity without hitting an API.
  let(:embedder) do
    instance_double(RCrewAI::Knowledge::Embedder).tap do |e|
      allow(e).to receive(:embed) do |texts|
        texts.map do |t|
          if t.include?('ruby')
            [1.0, 0.0]
          elsif t.include?('python')
            [0.0, 1.0]
          else
            [0.5, 0.5]
          end
        end
      end
    end
  end

  it 'indexes sources and retrieves the most relevant chunk for a query' do
    kb = described_class.new(
      sources: [
        RCrewAI::Knowledge::StringSource.new('ruby is a gem'),
        RCrewAI::Knowledge::StringSource.new('python has pip')
      ],
      embedder: embedder,
      chunk_size: 1000
    )
    kb.build!

    results = kb.search('tell me about ruby', k: 1)

    expect(results.first).to include('ruby')
  end

  it 'returns an empty array when it has no sources' do
    kb = described_class.new(sources: [], embedder: embedder)
    kb.build!

    expect(kb.search('anything', k: 3)).to eq([])
  end
end

RSpec.describe 'Knowledge wiring into Agent' do
  let(:embedder) do
    instance_double(RCrewAI::Knowledge::Embedder).tap do |e|
      allow(e).to receive(:embed) { |texts| texts.map { [1.0, 0.0] } }
    end
  end

  before { configure_test_llm }

  it 'accepts knowledge_sources and exposes a knowledge base' do
    kb = RCrewAI::Knowledge::Base.new(
      sources: [RCrewAI::Knowledge::StringSource.new('the launch code is 1234')],
      embedder: embedder
    )
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', knowledge: kb)

    expect(agent.knowledge).to eq(kb)
  end

  it 'injects retrieved knowledge into the task prompt' do
    kb = RCrewAI::Knowledge::Base.new(
      sources: [RCrewAI::Knowledge::StringSource.new('the launch code is 1234')],
      embedder: embedder
    )
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', knowledge: kb)
    task = RCrewAI::Task.new(name: 't', description: 'What is the launch code?', agent: agent)

    messages = agent.send(:build_initial_messages, task)
    user_message = messages.find { |m| m[:role] == 'user' }[:content]

    expect(user_message).to include('launch code is 1234')
  end

  it 'does not add a knowledge section when no knowledge is configured' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')
    task = RCrewAI::Task.new(name: 't', description: 'hi', agent: agent)

    messages = agent.send(:build_initial_messages, task)
    user_message = messages.find { |m| m[:role] == 'user' }[:content]

    expect(user_message).not_to include('Relevant Knowledge')
  end
end

RSpec.describe 'Knowledge wiring into Crew' do
  let(:embedder) do
    instance_double(RCrewAI::Knowledge::Embedder).tap do |e|
      allow(e).to receive(:embed) { |texts| texts.map { [1.0, 0.0] } }
    end
  end

  before { configure_test_llm }

  it 'shares crew-level knowledge with its agents' do
    kb = RCrewAI::Knowledge::Base.new(
      sources: [RCrewAI::Knowledge::StringSource.new('shared secret is 42')],
      embedder: embedder
    )
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')
    crew = RCrewAI::Crew.new('c', knowledge: kb)
    crew.add_agent(agent)
    crew.add_task(RCrewAI::Task.new(name: 't', description: 'q', agent: agent))

    allow_any_instance_of(RCrewAI::Process::Sequential)
      .to receive(:execute).and_return([])

    crew.execute

    task = RCrewAI::Task.new(name: 't2', description: 'what is the shared secret?', agent: agent)
    messages = agent.send(:build_initial_messages, task)
    user_message = messages.find { |m| m[:role] == 'user' }[:content]

    expect(user_message).to include('shared secret is 42')
  end
end
