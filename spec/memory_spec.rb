# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Memory do
  let(:task) do
    instance_double(RCrewAI::Task, name: 'research_ruby',
                                   description: 'Research the Ruby programming language')
  end

  describe 'backward-compatible API (zero-config, no embedder)' do
    subject(:memory) { described_class.new }

    it 'records an execution and recalls it as a formatted string' do
      memory.add_execution(task, 'Ruby is a dynamic language', 1.5)

      other = instance_double(RCrewAI::Task, name: 'q', description: 'Tell me about the Ruby language')
      recalled = memory.relevant_executions(other)

      expect(recalled).to be_a(String)
      expect(recalled).to include('Ruby is a dynamic language')
    end

    it 'returns nil from relevant_executions when nothing matches' do
      expect(memory.relevant_executions(task)).to be_nil
    end

    it 'records and formats tool usage' do
      memory.add_tool_usage('web_search', { 'q' => 'ruby' }, 'found results')

      usage = memory.tool_usage_for('web_search')
      expect(usage).to include('web_search')
    end

    it 'clears short-term without wiping long-term insights' do
      memory.add_execution(task, 'result', 1.0)
      memory.clear_short_term!

      # short-term is empty, but the successful execution was promoted to
      # long-term, so it is still recalled.
      expect(memory.stats[:short_term_count]).to eq(0)
      expect(memory.relevant_executions(task)).to include('result')
    end

    it 'clear_all! wipes everything' do
      memory.add_execution(task, 'result', 1.0)
      memory.clear_all!

      expect(memory.relevant_executions(task)).to be_nil
      expect(memory.stats[:short_term_count]).to eq(0)
      expect(memory.stats[:long_term_total]).to eq(0)
    end

    it 'reports stats' do
      memory.add_execution(task, 'ok', 1.0)
      expect(memory.stats).to include(:short_term_count, :tool_usage_count)
    end
  end

  describe 'semantic recall (with embedder)' do
    let(:embedder) do
      instance_double(RCrewAI::Knowledge::Embedder).tap do |e|
        allow(e).to receive(:embed) do |texts|
          texts.map do |t|
            case t.downcase
            when /ruby|gem/ then [1.0, 0.0]
            when /python|pip/ then [0.0, 1.0]
            else [0.5, 0.5]
            end
          end
        end
      end
    end

    subject(:memory) { described_class.new(embedder: embedder) }

    it 'recalls the conceptually related execution even without shared words' do
      ruby_task = instance_double(RCrewAI::Task, name: 't1', description: 'work with gems and bundler')
      py_task = instance_double(RCrewAI::Task, name: 't2', description: 'set up pip and venv')
      memory.add_execution(ruby_task, 'used bundler', 1.0)
      memory.add_execution(py_task, 'used pip', 1.0)

      query = instance_double(RCrewAI::Task, name: 'q', description: 'the Ruby ecosystem')
      recalled = memory.relevant_executions(query, 1)

      expect(recalled).to include('used bundler')
      expect(recalled).not_to include('used pip')
    end
  end

  describe 'persistence' do
    around do |example|
      Dir.mktmpdir do |dir|
        @path = File.join(dir, 'mem.db')
        example.run
      end
    end

    it 'survives a restart when backed by a SQLite store' do
      store = RCrewAI::Memory::SqliteStore.new(path: @path)
      mem = described_class.new(scope: 'agentZ', store: store)
      mem.add_execution(task, 'persistent result', 1.0)

      reopened_store = RCrewAI::Memory::SqliteStore.new(path: @path)
      reopened = described_class.new(scope: 'agentZ', store: reopened_store)

      other = instance_double(RCrewAI::Task, name: 'q', description: 'the Ruby language again')
      expect(reopened.relevant_executions(other)).to include('persistent result')
    end
  end
end

RSpec.describe 'Memory wiring into Agent' do
  before { configure_test_llm }

  it 'gives each agent a Memory scoped to itself by default' do
    agent = RCrewAI::Agent.new(name: 'scribe', role: 'r', goal: 'g')

    expect(agent.memory).to be_a(RCrewAI::Memory)
  end

  it 'accepts a pre-built Memory instance' do
    custom = RCrewAI::Memory.new(scope: 'custom')
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', memory: custom)

    expect(agent.memory).to equal(custom)
  end

  it 'accepts a memory options hash (embedder/store)' do
    store = RCrewAI::Memory::InMemoryStore.new
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', memory: { store: store })

    expect(agent.memory).to be_a(RCrewAI::Memory)
  end

  it 'isolates memory between two agents (different scopes)' do
    a1 = RCrewAI::Agent.new(name: 'alpha', role: 'r', goal: 'g')
    a2 = RCrewAI::Agent.new(name: 'beta', role: 'r', goal: 'g')

    t = instance_double(RCrewAI::Task, name: 't', description: 'shared topic')
    a1.memory.add_execution(t, 'alpha private note', 1.0)

    # beta must not see alpha's memory
    expect(a2.memory.relevant_executions(t)).to be_nil
  end
end
