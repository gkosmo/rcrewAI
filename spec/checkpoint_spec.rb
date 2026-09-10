# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RCrewAI::Checkpoint do
  describe RCrewAI::Checkpoint::MemoryStore do
    subject(:store) { described_class.new }

    it 'returns nil for an unknown run' do
      expect(store.load('nope')).to be_nil
    end

    it 'round-trips a saved record' do
      store.save('run-1', { 'run_id' => 'run-1', 'tasks' => {} })
      expect(store.load('run-1')['run_id']).to eq('run-1')
    end

    it 'overwrites on re-save' do
      store.save('run-1', { 'run_id' => 'run-1', 'seq' => 1 })
      store.save('run-1', { 'run_id' => 'run-1', 'seq' => 2 })
      expect(store.load('run-1')['seq']).to eq(2)
    end

    it 'lists saved run ids' do
      store.save('a', { 'run_id' => 'a' })
      store.save('b', { 'run_id' => 'b' })
      expect(store.list).to match_array(%w[a b])
    end

    it 'deletes a run' do
      store.save('a', { 'run_id' => 'a' })
      store.delete('a')
      expect(store.load('a')).to be_nil
    end
  end

  describe RCrewAI::Checkpoint::FileStore do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    subject(:store) { described_class.new(@dir) }

    it 'persists a record across store instances' do
      store.save('run-1', { 'run_id' => 'run-1', 'tasks' => { 'a' => 'completed' } })
      reopened = described_class.new(@dir)
      expect(reopened.load('run-1')['tasks']).to eq({ 'a' => 'completed' })
    end

    it 'returns nil for an unknown run' do
      expect(store.load('missing')).to be_nil
    end

    it 'lists persisted run ids' do
      store.save('a', { 'run_id' => 'a' })
      store.save('b', { 'run_id' => 'b' })
      expect(described_class.new(@dir).list).to match_array(%w[a b])
    end

    it 'deletes a persisted run' do
      store.save('a', { 'run_id' => 'a' })
      store.delete('a')
      expect(store.load('a')).to be_nil
    end

    it 'refuses a run id that would escape the directory' do
      expect { store.save('../evil', { 'run_id' => 'x' }) }
        .to raise_error(RCrewAI::Checkpoint::CheckpointError, /invalid run id/i)
    end
  end
end

RSpec.describe 'crew checkpointing' do
  let(:store) { RCrewAI::Checkpoint::MemoryStore.new }

  def stub_llm(answer: 'FINAL_ANSWER[done]')
    llm = instance_double('LLMClient')
    allow(llm).to receive(:chat).and_return(
      content: answer, finish_reason: :stop,
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    )
    allow(llm).to receive(:supports_native_tools?).and_return(false)
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(llm)
    llm
  end

  def build_crew(name: 'cp', task_names: %w[t1 t2 t3])
    crew = RCrewAI::Crew.new(name)
    agent = RCrewAI::Agent.new(name: 'w', role: 'W', goal: 'G', backstory: 'B')
    crew.add_agent(agent)
    task_names.each do |tn|
      crew.add_task(
        RCrewAI::Task.new(name: tn, description: "do #{tn}",
                          expected_output: 'out', agent: agent)
      )
    end
    crew
  end

  describe 'writing checkpoints' do
    it 'is off unless a store is supplied' do
      stub_llm
      crew = build_crew
      crew.execute
      expect(store.list).to be_empty
    end

    it 'records a run id on the crew' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      expect(crew.run_id).to be_a(String)
      expect(crew.run_id).not_to be_empty
    end

    it 'saves a record under the run id' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      expect(store.load(crew.run_id)).not_to be_nil
    end

    it 'marks every completed task in the record' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)

      tasks = store.load(crew.run_id)['tasks']
      expect(tasks.keys).to match_array(%w[t1 t2 t3])
      expect(tasks.values.map { |t| t['status'] }).to all(eq('completed'))
    end

    it 'stores each task result so resume need not re-run it' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)

      expect(store.load(crew.run_id)['tasks']['t1']['result']).to include('done')
    end

    it 'checkpoints incrementally rather than only at the end' do
      stub_llm
      crew = build_crew
      seen = []
      recorder = Class.new do
        def initialize(seen) = @seen = seen
        def save(_id, record) = @seen << record['tasks'].keys.size
        def load(_id) = nil
        def list = []
        def delete(_id) = nil
      end.new(seen)

      crew.execute(checkpoint: recorder)

      expect(seen).to include(1, 2, 3),
                      'checkpoint was not written after each task'
    end

    it 'persists a checkpoint even when a task fails mid-run' do
      llm = stub_llm
      crew = build_crew
      call = 0
      allow(llm).to receive(:chat) do
        call += 1
        raise 'boom' if call > 1

        { content: 'FINAL_ANSWER[ok]', finish_reason: :stop,
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
      end

      crew.execute(checkpoint: store)

      record = store.load(crew.run_id)
      expect(record['tasks']['t1']['status']).to eq('completed')
      expect(record['tasks']['t2']['status']).to eq('failed')
    end
  end

  describe '#resume' do
    it 'raises without a store configured' do
      stub_llm
      crew = build_crew
      expect { crew.resume('whatever') }
        .to raise_error(RCrewAI::Checkpoint::CheckpointError, /no checkpoint store/i)
    end

    it 'raises for an unknown run id' do
      stub_llm
      crew = build_crew
      expect { crew.resume('missing', checkpoint: store) }
        .to raise_error(RCrewAI::Checkpoint::CheckpointError, /no checkpoint/i)
    end

    it 'skips tasks already completed' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      run_id = crew.run_id

      resumed = build_crew
      executed = []
      resumed.tasks.each do |t|
        allow(t).to receive(:execute).and_wrap_original do |orig, *args|
          executed << t.name
          orig.call(*args)
        end
      end

      resumed.resume(run_id, checkpoint: store)

      expect(executed).to be_empty, "re-ran completed tasks: #{executed.inspect}"
    end

    it 'restores results for skipped tasks' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)

      resumed = build_crew
      result = resumed.resume(crew.run_id, checkpoint: store)

      expect(result[:results].map { |r| r[:status] }).to all(eq(:completed))
      expect(resumed.tasks.first.result).to include('done')
    end

    it 're-runs only the tasks that had not completed' do
      llm = stub_llm
      crew = build_crew
      call = 0
      allow(llm).to receive(:chat) do
        call += 1
        raise 'boom' if call > 1

        { content: 'FINAL_ANSWER[ok]', finish_reason: :stop,
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
      end
      crew.execute(checkpoint: store)

      stub_llm(answer: 'FINAL_ANSWER[second]')
      resumed = build_crew
      executed = []
      resumed.tasks.each do |t|
        allow(t).to receive(:execute).and_wrap_original do |orig, *args|
          executed << t.name
          orig.call(*args)
        end
      end

      resumed.resume(crew.run_id, checkpoint: store)

      expect(executed).to match_array(%w[t2 t3])
    end
  end

  describe 'lineage' do
    it 'records no parent for a fresh run' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      expect(store.load(crew.run_id)['parent_run_id']).to be_nil
    end

    it 'records the parent run id on a resumed run' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      parent = crew.run_id

      resumed = build_crew
      resumed.resume(parent, checkpoint: store)

      expect(resumed.run_id).not_to eq(parent)
      expect(store.load(resumed.run_id)['parent_run_id']).to eq(parent)
    end

    it 'leaves the parent record intact after a resume' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      parent = crew.run_id

      build_crew.resume(parent, checkpoint: store)

      expect(store.load(parent)).not_to be_nil
      expect(store.load(parent)['tasks'].keys).to match_array(%w[t1 t2 t3])
    end

    it 'walks a chain of resumes back to the root' do
      stub_llm
      crew = build_crew
      crew.execute(checkpoint: store)
      root = crew.run_id

      second = build_crew
      second.resume(root, checkpoint: store)
      third = build_crew
      third.resume(second.run_id, checkpoint: store)

      chain = RCrewAI::Checkpoint.lineage(store, third.run_id)
      expect(chain).to eq([root, second.run_id, third.run_id])
    end
  end
end

RSpec.describe 'checkpointing across process types' do
  let(:store) { RCrewAI::Checkpoint::MemoryStore.new }

  def stub_llm(answer: 'FINAL_ANSWER[done]')
    llm = instance_double('LLMClient')
    allow(llm).to receive(:chat).and_return(
      content: answer, finish_reason: :stop,
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    )
    allow(llm).to receive(:supports_native_tools?).and_return(false)
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(llm)
    llm
  end

  def hierarchical_crew(name: 'hcp')
    crew = RCrewAI::Crew.new(name, process: :hierarchical)
    manager = RCrewAI::Agent.new(name: 'boss', role: 'Manager', goal: 'Coordinate',
                                 backstory: 'Leads', manager: true, allow_delegation: true)
    worker = RCrewAI::Agent.new(name: 'w', role: 'W', goal: 'G', backstory: 'B')
    crew.add_agent(manager)
    crew.add_agent(worker)
    %w[t1 t2].each do |tn|
      crew.add_task(RCrewAI::Task.new(name: tn, description: "do #{tn}",
                                      expected_output: 'out', agent: worker))
    end
    crew
  end

  def consensual_crew(name: 'ccp')
    crew = RCrewAI::Crew.new(name, process: :consensual, consensus_agents: 2)
    2.times do |i|
      crew.add_agent(RCrewAI::Agent.new(name: "a#{i}", role: 'W', goal: 'G', backstory: 'B'))
    end
    %w[t1 t2].each do |tn|
      crew.add_task(RCrewAI::Task.new(name: tn, description: "do #{tn}",
                                      expected_output: 'out', agent: crew.agents.first))
    end
    crew
  end

  describe 'hierarchical process' do
    it 'checkpoints each delegated task' do
      stub_llm
      crew = hierarchical_crew
      crew.execute(checkpoint: store)

      tasks = store.load(crew.run_id)['tasks']
      expect(tasks.keys).to match_array(%w[t1 t2])
    end

    it 'skips restored tasks on resume' do
      stub_llm
      crew = hierarchical_crew
      crew.execute(checkpoint: store)

      resumed = hierarchical_crew
      executed = []
      resumed.tasks.each do |t|
        allow(t).to receive(:execute).and_wrap_original do |orig, *args|
          executed << t.name
          orig.call(*args)
        end
      end
      resumed.resume(crew.run_id, checkpoint: store)

      expect(executed).to be_empty
    end
  end

  describe 'consensual process' do
    it 'checkpoints each consensus task' do
      stub_llm
      crew = consensual_crew
      crew.execute(checkpoint: store)

      tasks = store.load(crew.run_id)['tasks']
      expect(tasks.keys).to match_array(%w[t1 t2])
    end

    it 'skips restored tasks on resume' do
      stub_llm
      crew = consensual_crew
      crew.execute(checkpoint: store)

      resumed = consensual_crew
      resumed.resume(crew.run_id, checkpoint: store)

      expect(resumed.restored_task_names).to match_array(%w[t1 t2])
    end
  end
end
