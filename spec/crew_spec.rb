# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Crew do
  subject { described_class.new('test_crew') }

  let(:agent1) { create_test_agent(name: 'agent1') }
  let(:agent2) { create_test_agent(name: 'agent2') }
  let(:task1) { create_test_task(name: 'task1', agent: agent1) }
  let(:task2) { create_test_task(name: 'task2', agent: agent2) }

  describe '#initialize' do
    it 'sets basic attributes' do
      expect(subject.name).to eq('test_crew')
      expect(subject.agents).to eq([])
      expect(subject.tasks).to eq([])
      expect(subject.process_type).to eq(:sequential)
    end

    it 'accepts optional parameters' do
      crew = described_class.new(
        'custom_crew',
        process: :hierarchical,
        verbose: true,
        max_iterations: 20
      )

      expect(crew.name).to eq('custom_crew')
      expect(crew.process_type).to eq(:hierarchical)
      expect(crew.verbose).to be true
      expect(crew.max_iterations).to eq(20)
    end

    it 'validates process type' do
      expect { described_class.new('test', process: :invalid) }
        .to raise_error(RCrewAI::ConfigurationError, /Invalid process type/)
    end
  end

  describe '#add_agent' do
    it 'adds agent to crew' do
      subject.add_agent(agent1)
      expect(subject.agents).to include(agent1)
    end
  end

  describe '#add_task' do
    it 'adds task to crew' do
      subject.add_task(task1)
      expect(subject.tasks).to include(task1)
    end
  end

  describe '#process=' do
    it 'changes process type' do
      subject.process = :hierarchical
      expect(subject.process_type).to eq(:hierarchical)
    end

    it 'validates new process type' do
      expect { subject.process = :invalid }
        .to raise_error(RCrewAI::ConfigurationError, /Invalid process type/)
    end

    it 'resets process instance when changed' do
      # Set up initial process instance
      subject.send(:create_process_instance)
      original_instance = subject.instance_variable_get(:@process_instance)

      subject.process = :hierarchical
      expect(subject.instance_variable_get(:@process_instance)).to be_nil
    end
  end

  describe '#execute' do
    before do
      subject.add_agent(agent1)
      subject.add_agent(agent2)
      subject.add_task(task1)
      subject.add_task(task2)
    end

    context 'synchronous execution' do
      it 'executes crew synchronously by default' do
        expect(subject).to receive(:execute_sync).and_call_original
        allow_any_instance_of(RCrewAI::Process::Sequential)
          .to receive(:execute).and_return([
            { name: 'task1', status: :completed, result: 'Result 1' },
            { name: 'task2', status: :completed, result: 'Result 2' }
          ])

        results = subject.execute
        expect(results).to be_a(Hash)
        expect(results[:crew]).to eq('test_crew')
        expect(results[:process]).to eq(:sequential)
      end

      it 'creates appropriate process instance' do
        allow_any_instance_of(RCrewAI::Process::Sequential)
          .to receive(:execute).and_return([])

        expect(RCrewAI::Process::Sequential).to receive(:new).with(subject).and_call_original
        subject.execute
      end
    end

    context 'asynchronous execution' do
      it 'executes crew asynchronously when requested' do
        allow(subject).to receive(:execute_sequential_async).with(any_args).and_return({
          crew: 'test_crew',
          process: :async_sequential,
          results: []
        })

        result = subject.execute(async: true, max_concurrency: 2)
        expect(result[:crew]).to eq('test_crew')
        expect(result[:process]).to eq(:async_sequential)
      end

      it 'handles different process types in async mode' do
        subject.process = :hierarchical
        expect(subject).to receive(:execute_hierarchical_async).and_call_original
        
        # Mock the hierarchical async execution
        allow(subject).to receive(:find_manager_agent).and_return(agent1)
        allow_any_instance_of(RCrewAI::AsyncExecutor).to receive(:execute_tasks_async)
          .and_return({ results: [] })
        allow_any_instance_of(RCrewAI::AsyncExecutor).to receive(:shutdown)

        subject.execute(async: true)
      end
    end

    it 'raises error for unsupported async process types' do
      allow(subject).to receive(:process_type).and_return(:unknown)
      expect { subject.execute(async: true) }
        .to raise_error(RCrewAI::ConfigurationError, /Async execution not implemented/)
    end
  end

  describe '#execute_sync' do
    before do
      subject.add_agent(agent1)
      subject.add_task(task1)
    end

    it 'creates process instance and executes' do
      mock_process = double('Process')
      expect(subject).to receive(:create_process_instance).and_return(mock_process)
      expect(mock_process).to receive(:execute).and_return([
        { name: 'task1', status: :completed, result: 'Done' }
      ])

      results = subject.execute_sync
      expect(results[:crew]).to eq('test_crew')
      expect(results[:total_tasks]).to eq(1)
      expect(results[:completed_tasks]).to eq(1)
    end
  end

  describe '#execute_sequential_async' do
    before do
      subject.add_agent(agent1)
      subject.add_task(task1)
    end

    it 'uses AsyncExecutor for parallel execution' do
      subject.process = :sequential
      subject.add_task(task1)
      subject.add_task(task2)
      
      mock_executor = double('AsyncExecutor')
      expect(RCrewAI::AsyncExecutor).to receive(:new).and_return(mock_executor)
      expect(mock_executor).to receive(:execute_tasks_async)
        .and_return({ results: [] })
      expect(mock_executor).to receive(:shutdown)

      result = subject.execute(async: true)
      expect(result[:process]).to eq(:async_sequential)
    end

    it 'builds dependency graph' do
      task2.add_context_task(task1)
      subject.add_task(task2)

      expect(subject).to receive(:build_dependency_graph).and_call_original
      dependency_graph = subject.send(:build_dependency_graph)
      expect(dependency_graph[task2]).to eq([task1])
    end
  end

  describe '#execute_hierarchical_async' do
    let(:manager) { create_test_agent(name: 'manager', manager: true) }

    before do
      subject.add_agent(manager)
      subject.add_agent(agent1)
      subject.add_task(task1)
    end

    it 'requires manager agent' do
      subject.process = :hierarchical
      subject.instance_variable_set(:@agents, [agent1])
      expect { subject.execute(async: true) }
        .to raise_error(RCrewAI::Process::ProcessError, /requires a manager agent/)
    end

    it 'coordinates execution through manager' do
      subject.process = :hierarchical
      subject.add_task(task1)
      
      mock_executor = double('AsyncExecutor')
      allow(RCrewAI::AsyncExecutor).to receive(:new).and_return(mock_executor)
      allow(mock_executor).to receive(:execute_tasks_async).and_return({ results: [] })
      allow(mock_executor).to receive(:shutdown)

      allow(subject).to receive(:organize_tasks_into_phases).and_return([[task1]])
      allow(subject).to receive(:find_best_agent_for_task).and_return(agent1)
      allow(subject).to receive(:add_delegation_context)

      result = subject.execute(async: true)
      expect(result[:manager]).to eq('manager')
      expect(result[:process]).to eq(:async_hierarchical)
    end
  end

  describe '#execute_consensual_async' do
    before do
      subject.add_agent(agent1)
      subject.add_task(task1)
    end

    it 'executes all tasks in parallel' do
      subject.process = :consensual
      
      mock_executor = double('AsyncExecutor')
      expect(RCrewAI::AsyncExecutor).to receive(:new).and_return(mock_executor)
      expect(mock_executor).to receive(:execute_tasks_async)
        .with(subject.tasks, {})
        .and_return({ results: [] })
      expect(mock_executor).to receive(:shutdown)

      result = subject.execute(async: true)
      expect(result[:process]).to eq(:async_consensual)
    end
  end

  describe 'dependency management' do
    it 'builds dependency graph correctly' do
      task2.add_context_task(task1)
      subject.add_task(task1)
      subject.add_task(task2)

      graph = subject.send(:build_dependency_graph)
      expect(graph[task1]).to eq([])
      expect(graph[task2]).to eq([task1])
    end

    it 'organizes tasks into execution phases' do
      task2.add_context_task(task1)
      task3 = create_test_task(name: 'task3', agent: agent1)
      task3.add_context_task(task2)

      subject.add_task(task1)
      subject.add_task(task2)
      subject.add_task(task3)

      dependency_graph = subject.send(:build_dependency_graph)
      phases = subject.send(:organize_tasks_into_phases, subject.tasks, dependency_graph)

      expect(phases[0]).to eq([task1])  # No dependencies
      expect(phases[1]).to eq([task2])  # Depends on task1
      expect(phases[2]).to eq([task3])  # Depends on task2
    end
  end

  describe 'manager agent selection' do
    it 'finds manager agent' do
      manager = create_test_agent(name: 'manager', manager: true)
      subject.add_agent(agent1)
      subject.add_agent(manager)

      found_manager = subject.send(:find_manager_agent)
      expect(found_manager).to eq(manager)
    end

    it 'falls back to delegation-capable agent' do
      delegator = create_test_agent(name: 'delegator', allow_delegation: true)
      subject.add_agent(agent1)
      subject.add_agent(delegator)

      found_manager = subject.send(:find_manager_agent)
      expect(found_manager).to eq(delegator)
    end

    it 'returns nil when no suitable manager found' do
      subject.add_agent(agent1)
      found_manager = subject.send(:find_manager_agent)
      expect(found_manager).to be_nil
    end
  end

  describe 'agent-task matching' do
    let(:research_task) do
      create_test_task(
        name: 'research_task',
        description: 'Research AI developments'
      )
    end

    let(:researcher) { create_test_agent(name: 'researcher', role: 'Research Specialist') }
    let(:writer) { create_test_agent(name: 'writer', role: 'Content Writer') }

    it 'finds best agent for task based on keywords' do
      subject.add_agent(researcher)
      subject.add_agent(writer)

      best_agent = subject.send(:find_best_agent_for_task, research_task)
      expect(best_agent).to eq(researcher)
    end

    it 'excludes manager agents from task assignment' do
      manager = create_test_agent(name: 'manager', role: 'Research Manager', manager: true)
      subject.add_agent(manager)
      subject.add_agent(writer)

      best_agent = subject.send(:find_best_agent_for_task, research_task)
      expect(best_agent).to eq(writer)
    end

    it 'considers tool availability in agent selection' do
      tool = double('Tool')
      skilled_agent = create_test_agent(name: 'skilled', tools: [tool])
      subject.add_agent(agent1)
      subject.add_agent(skilled_agent)

      best_agent = subject.send(:find_best_agent_for_task, research_task)
      expect(best_agent).to eq(skilled_agent)
    end
  end

  describe 'class methods' do
    describe '.create' do
      it 'creates and saves crew' do
        crew = described_class.create('new_crew')
        expect(crew).to be_a(described_class)
        expect(crew.name).to eq('new_crew')
      end
    end

    describe '.load' do
      it 'loads crew configuration' do
        crew = described_class.load('existing_crew')
        expect(crew.name).to eq('existing_crew')
      end
    end

    describe '.list' do
      it 'returns list of available crews' do
        crews = described_class.list
        expect(crews).to be_an(Array)
        expect(crews).to include('example_crew')
      end
    end
  end

  describe '#save' do
    it 'saves crew configuration' do
      expect(subject.save).to be true
    end
  end

  describe 'result formatting' do
    let(:results) do
      [
        { name: 'task1', status: :completed, result: 'Done' },
        { name: 'task2', status: :failed, result: 'Error' }
      ]
    end

    it 'formats execution results correctly' do
      formatted = subject.send(:format_execution_results, results)

      expect(formatted[:crew]).to eq('test_crew')
      expect(formatted[:process]).to eq(:sequential)
      expect(formatted[:total_tasks]).to eq(2)
      expect(formatted[:completed_tasks]).to eq(1)
      expect(formatted[:failed_tasks]).to eq(1)
      expect(formatted[:success_rate]).to eq(50.0)
    end
  end
end