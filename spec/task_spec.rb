# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Task do
  let(:agent) { create_test_agent }
  
  subject do
    described_class.new(
      name: 'test_task',
      description: 'A test task description',
      agent: agent,
      expected_output: 'Expected test output'
    )
  end

  describe '#initialize' do
    it 'sets basic attributes' do
      expect(subject.name).to eq('test_task')
      expect(subject.description).to eq('A test task description')
      expect(subject.agent).to eq(agent)
      expect(subject.expected_output).to eq('Expected test output')
      expect(subject.context).to eq([])
      expect(subject.tools).to eq([])
    end

    it 'sets default status and timing' do
      expect(subject.status).to eq(:pending)
      expect(subject.result).to be_nil
      expect(subject.start_time).to be_nil
      expect(subject.end_time).to be_nil
      expect(subject.execution_time).to be_nil
    end

    it 'accepts optional parameters' do
      context_task = create_test_task(name: 'context_task')
      tool = double('Tool')

      task = described_class.new(
        name: 'complex_task',
        description: 'A complex task',
        agent: agent,
        expected_output: 'Complex output',
        context: [context_task],
        tools: [tool],
        async: true,
        max_retries: 5
      )

      expect(task.context).to eq([context_task])
      expect(task.tools).to eq([tool])
      expect(task.async).to be true
      expect(task.instance_variable_get(:@max_retries)).to eq(5)
    end

    it 'accepts human input options' do
      task = described_class.new(
        name: 'human_task',
        description: 'Task with human input',
        agent: agent,
        human_input: true,
        require_confirmation: true,
        allow_guidance: true,
        human_review_points: [:completion]
      )

      expect(task.human_input_enabled?).to be true
      expect(task.instance_variable_get(:@require_human_confirmation)).to be true
      expect(task.instance_variable_get(:@allow_human_guidance)).to be true
      expect(task.instance_variable_get(:@human_review_points)).to eq([:completion])
    end
  end

  describe '#execute' do
    before do
      allow(agent).to receive(:execute_task).with(subject).and_return('Task completed')
    end

    it 'executes task and sets result' do
      result = subject.execute
      
      expect(result).to eq('Task completed')
      expect(subject.result).to eq('Task completed')
      expect(subject.status).to eq(:completed)
      expect(subject.start_time).to be_a(Time)
      expect(subject.end_time).to be_a(Time)
      expect(subject.execution_time).to be_a(Numeric)
    end

    it 'validates dependencies before execution' do
      dependency = create_test_task(name: 'dependency')
      subject.add_context_task(dependency)

      expect { subject.execute }
        .to raise_error(RCrewAI::TaskDependencyError, /Dependencies not met/)
    end

    it 'executes with satisfied dependencies' do
      dependency = create_test_task(name: 'dependency')
      dependency.instance_variable_set(:@status, :completed)
      subject.add_context_task(dependency)

      result = subject.execute
      expect(result).to eq('Task completed')
    end

    it 'fails gracefully without agent' do
      task = described_class.new(
        name: 'no_agent_task',
        description: 'Task without agent'
      )

      result = task.execute
      expect(result).to eq('Task requires an agent')
      expect(task.status).to eq(:failed)
    end

    it 'executes callback if provided' do
      callback_executed = false
      callback = proc { |task, result| callback_executed = true }

      task = described_class.new(
        name: 'callback_task',
        description: 'Task with callback',
        agent: agent,
        callback: callback
      )

      allow(agent).to receive(:execute_task).and_return('Done')
      task.execute

      expect(callback_executed).to be true
    end

    context 'with human confirmation required' do
      before do
        subject.instance_variable_set(:@require_human_confirmation, true)
      end

      it 'requests human confirmation before execution' do
        expect(subject).to receive(:confirm_task_execution)
          .and_return({ approved: true })

        subject.execute
        expect(subject.status).to eq(:completed)
      end

      it 'cancels execution if human rejects' do
        expect(subject).to receive(:confirm_task_execution)
          .and_return({ approved: false, reason: 'Too risky' })

        result = subject.execute
        expect(result).to include('cancelled by human')
        expect(subject.status).to eq(:cancelled)
      end
    end

    context 'with human interaction enabled' do
      before do
        subject.enable_human_input(
          require_confirmation: false,
          allow_guidance: true,
          review_points: [:completion]
        )
      end

      it 'enables human input for agent during execution' do
        expect(agent).to receive(:enable_human_input)
          .with(hash_including(
            require_approval_for_tools: false,
            require_approval_for_final_answer: true
          ))

        expect(agent).to receive(:disable_human_input)
        subject.execute
      end

      it 'requests human review at completion if configured' do
        expect(subject).to receive(:request_task_completion_review)
          .and_return({ approved: true })

        subject.execute
      end
    end

    context 'with retry logic' do
      it 'retries on failure' do
        call_count = 0
        allow(agent).to receive(:execute_task) do
          call_count += 1
          if call_count < 2
            raise StandardError.new('Temporary failure')
          else
            'Success on retry'
          end
        end

        expect(subject).to receive(:sleep).with(2).once
        result = subject.execute

        expect(result).to eq('Success on retry')
        expect(subject.instance_variable_get(:@retry_count)).to eq(1)
      end

      it 'fails after max retries' do
        allow(agent).to receive(:execute_task).and_raise(StandardError.new('Persistent failure'))
        allow(subject).to receive(:sleep)

        expect { subject.execute }
          .to raise_error(RCrewAI::TaskExecutionError, /Task 'test_task' failed: Persistent failure/)

        expect(subject.status).to eq(:failed)
        expect(subject.result).to include('failed after 2 retries')
      end

      context 'with human intervention on failure' do
        before do
          subject.enable_human_input
          allow(agent).to receive(:execute_task).and_raise(StandardError.new('Test failure'))
        end

        it 'requests human guidance on failure' do
          expect(subject).to receive(:request_retry_guidance)
            .and_return({ choice: 'retry' })
          expect(subject).to receive(:sleep).with(2)

          # First call fails, second call succeeds
          call_count = 0
          allow(agent).to receive(:execute_task) do
            call_count += 1
            if call_count == 1
              raise StandardError.new('Test failure')
            else
              'Recovered'
            end
          end

          result = subject.execute
          expect(result).to eq('Recovered')
        end

        it 'allows task modification on retry' do
          expect(subject).to receive(:request_retry_guidance)
            .and_return({ choice: 'modify' })
          expect(subject).to receive(:request_task_modification)
            .and_return({ modified: true, changes: { 'description' => 'Modified description' } })

          allow(subject).to receive(:sleep)
          
          # Mock second execution to succeed
          call_count = 0
          allow(agent).to receive(:execute_task) do
            call_count += 1
            if call_count == 1
              raise StandardError.new('Test failure')
            else
              'Modified and completed'
            end
          end

          subject.execute
          expect(subject.description).to eq('Modified description')
        end

        it 'aborts on human request' do
          expect(subject).to receive(:request_retry_guidance)
            .and_return({ choice: 'abort' })

          expect { subject.execute }
            .to raise_error(RCrewAI::TaskExecutionError, /aborted by human/)
        end
      end
    end
  end

  describe '#context_data' do
    it 'returns empty string when no context' do
      expect(subject.context_data).to eq('')
    end

    it 'formats completed context tasks' do
      context_task = create_test_task(name: 'context_task')
      context_task.instance_variable_set(:@status, :completed)
      context_task.instance_variable_set(:@result, 'Context result')
      
      subject.add_context_task(context_task)
      context_data = subject.context_data

      expect(context_data).to include('Task: context_task')
      expect(context_data).to include('Result: Context result')
    end

    it 'shows status for incomplete context tasks' do
      context_task = create_test_task(name: 'pending_task')
      context_task.instance_variable_set(:@status, :running)
      
      subject.add_context_task(context_task)
      context_data = subject.context_data

      expect(context_data).to include('Task: pending_task')
      expect(context_data).to include('Status: running')
    end
  end

  describe 'status predicates' do
    it 'reports correct status' do
      expect(subject.pending?).to be true
      expect(subject.running?).to be false
      expect(subject.completed?).to be false
      expect(subject.failed?).to be false

      subject.instance_variable_set(:@status, :running)
      expect(subject.running?).to be true
      expect(subject.pending?).to be false

      subject.instance_variable_set(:@status, :completed)
      expect(subject.completed?).to be true
      expect(subject.running?).to be false

      subject.instance_variable_set(:@status, :failed)
      expect(subject.failed?).to be true
      expect(subject.completed?).to be false
    end
  end

  describe '#dependencies_met?' do
    it 'returns true with no dependencies' do
      expect(subject.dependencies_met?).to be true
    end

    it 'returns true when all dependencies are completed' do
      dep1 = create_test_task(name: 'dep1')
      dep2 = create_test_task(name: 'dep2')
      dep1.instance_variable_set(:@status, :completed)
      dep2.instance_variable_set(:@status, :completed)
      
      subject.add_context_task(dep1)
      subject.add_context_task(dep2)

      expect(subject.dependencies_met?).to be true
    end

    it 'returns false when any dependency is not completed' do
      dep1 = create_test_task(name: 'dep1')
      dep2 = create_test_task(name: 'dep2')
      dep1.instance_variable_set(:@status, :completed)
      dep2.instance_variable_set(:@status, :running)
      
      subject.add_context_task(dep1)
      subject.add_context_task(dep2)

      expect(subject.dependencies_met?).to be false
    end
  end

  describe '#add_context_task' do
    it 'adds task to context' do
      context_task = create_test_task(name: 'context')
      subject.add_context_task(context_task)
      expect(subject.context).to include(context_task)
    end

    it 'does not add duplicate tasks' do
      context_task = create_test_task(name: 'context')
      subject.add_context_task(context_task)
      subject.add_context_task(context_task)
      expect(subject.context.size).to eq(1)
    end
  end

  describe '#add_tool' do
    it 'adds tool to task tools' do
      tool = double('Tool')
      subject.add_tool(tool)
      expect(subject.tools).to include(tool)
    end

    it 'does not add duplicate tools' do
      tool = double('Tool')
      subject.add_tool(tool)
      subject.add_tool(tool)
      expect(subject.tools.size).to eq(1)
    end
  end

  describe 'human interaction methods' do
    before do
      subject.enable_human_input(
        require_confirmation: true,
        allow_guidance: true,
        review_points: [:completion]
      )
    end

    describe '#enable_human_input' do
      it 'enables human interaction features' do
        expect(subject.human_input_enabled?).to be true
        expect(subject.instance_variable_get(:@require_human_confirmation)).to be true
        expect(subject.instance_variable_get(:@allow_human_guidance)).to be true
        expect(subject.instance_variable_get(:@human_review_points)).to eq([:completion])
      end
    end

    describe '#disable_human_input' do
      it 'disables all human interaction features' do
        subject.disable_human_input
        expect(subject.human_input_enabled?).to be false
        expect(subject.instance_variable_get(:@require_human_confirmation)).to be false
        expect(subject.instance_variable_get(:@allow_human_guidance)).to be false
        expect(subject.instance_variable_get(:@human_review_points)).to eq([])
      end
    end
  end
end