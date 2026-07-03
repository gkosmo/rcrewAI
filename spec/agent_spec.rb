# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Agent do
  let(:mock_llm_client) { double('LLMClient') }
  let(:mock_tool) { double('Tool', name: 'test_tool', description: 'A test tool') }

  before do
    configure_test_llm
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(mock_llm_client)
  end

  subject do
    described_class.new(
      name: 'test_agent',
      role: 'Test Agent',
      goal: 'Test things effectively',
      backstory: 'An agent created for testing purposes',
      tools: [mock_tool]
    )
  end

  describe '#initialize' do
    it 'sets basic attributes' do
      expect(subject.name).to eq('test_agent')
      expect(subject.role).to eq('Test Agent')
      expect(subject.goal).to eq('Test things effectively')
      expect(subject.backstory).to eq('An agent created for testing purposes')
      expect(subject.tools).to eq([mock_tool])
    end

    it 'sets default options' do
      expect(subject.verbose).to be false
      expect(subject.allow_delegation).to be false
      expect(subject.max_iterations).to eq(10)
      expect(subject.max_execution_time).to eq(300)
    end

    it 'creates memory and llm_client instances' do
      expect(subject.memory).to be_a(RCrewAI::Memory)
      expect(subject.llm_client).to eq(mock_llm_client)
    end

    it 'accepts custom options' do
      agent = described_class.new(
        name: 'custom_agent',
        role: 'Custom Agent',
        goal: 'Be customizable',
        verbose: true,
        allow_delegation: true,
        max_iterations: 20,
        manager: true
      )

      expect(agent.verbose).to be true
      expect(agent.allow_delegation).to be true
      expect(agent.max_iterations).to eq(20)
      expect(agent.is_manager?).to be true
    end

    it 'accepts human input options' do
      agent = described_class.new(
        name: 'human_agent',
        role: 'Human Interactive Agent',
        goal: 'Work with humans',
        human_input: true,
        require_approval_for_tools: true,
        require_approval_for_final_answer: true
      )

      expect(agent.human_input_enabled?).to be true
      expect(agent.instance_variable_get(:@require_approval_for_tools)).to be true
      expect(agent.instance_variable_get(:@require_approval_for_final_answer)).to be true
    end
  end

  describe '#execute_task' do
    let(:task) { create_test_task(agent: subject) }

    before do
      allow(mock_llm_client).to receive(:supports_native_tools?).and_return(false)
      allow(mock_llm_client).to receive(:chat).and_return(
        mock_llm_response(content: 'Task completed successfully')
      )
    end

    it 'executes task and returns result hash with content' do
      result = subject.execute_task(task)
      expect(result).to be_a(Hash)
      expect(result[:content]).to eq('Task completed successfully')
      expect(task.result).to eq('Task completed successfully')
    end

    it 'logs task execution' do
      expect(subject.instance_variable_get(:@logger)).to receive(:info)
        .with("Agent test_agent starting task: #{task.name}")
      expect(subject.instance_variable_get(:@logger)).to receive(:info).at_least(:once)
                                                                       .with(/Task completed in \d+\.\d+s|runner=/)

      subject.execute_task(task)
    end

    it 'builds context for the task' do
      expect(subject).to receive(:build_context).with(task).and_call_original
      subject.execute_task(task)
    end

    it 'stores execution in memory' do
      expect(subject.memory).to receive(:add_execution)
        .with(task, 'Task completed successfully', anything)

      subject.execute_task(task)
    end

    it 'handles execution errors' do
      allow(mock_llm_client).to receive(:chat).and_raise(StandardError.new('Test error'))

      expect { subject.execute_task(task) }
        .to raise_error(RCrewAI::AgentError, /Agent test_agent failed to execute task: Test error/)

      expect(task.result).to eq('Task failed: Test error')
    end
  end

  describe '#available_tools_description' do
    it 'returns description when tools are available' do
      description = subject.available_tools_description
      expect(description).to include('test_tool')
      expect(description).to include('A test tool')
    end

    it 'returns no tools message when empty' do
      subject.instance_variable_set(:@tools, [])
      description = subject.available_tools_description
      expect(description).to eq('No tools available.')
    end
  end

  describe '#use_tool' do
    before do
      allow(mock_tool).to receive(:execute).with(param: 'value').and_return('Tool executed')
    end

    it 'finds and executes tool by name' do
      result = subject.use_tool('test_tool', param: 'value')
      expect(result).to eq('Tool executed')
    end

    it 'finds tool by class name' do
      allow(mock_tool).to receive_message_chain(:class, :name).and_return('RCrewAI::Tools::TestTool')
      result = subject.use_tool('testtool', param: 'value')
      expect(result).to eq('Tool executed')
    end

    it 'raises error for unknown tool' do
      expect { subject.use_tool('unknown_tool') }
        .to raise_error(RCrewAI::ToolNotFoundError, /Tool 'unknown_tool' not found/)
    end

    it 'stores tool usage in memory' do
      expect(subject.memory).to receive(:add_tool_usage)
        .with('test_tool', { param: 'value' }, 'Tool executed')

      subject.use_tool('test_tool', param: 'value')
    end

    context 'with human approval required' do
      before do
        subject.instance_variable_set(:@require_approval_for_tools, true)
        subject.instance_variable_set(:@human_input_enabled, true)
      end

      it 'requests human approval before tool execution' do
        expect(subject).to receive(:request_tool_approval)
          .with('test_tool', { param: 'value' })
          .and_return({ approved: true })

        result = subject.use_tool('test_tool', param: 'value')
        expect(result).to eq('Tool executed')
      end

      it 'rejects tool usage when human disapproves' do
        expect(subject).to receive(:request_tool_approval)
          .and_return({ approved: false, reason: 'Too risky' })

        result = subject.use_tool('test_tool', param: 'value')
        expect(result).to include('Tool usage was rejected')
        expect(result).to include('Too risky')
      end
    end
  end

  describe 'manager functionality' do
    let(:manager) do
      described_class.new(
        name: 'manager',
        role: 'Project Manager',
        goal: 'Manage team effectively',
        manager: true,
        allow_delegation: true
      )
    end

    let(:subordinate) { create_test_agent(name: 'subordinate') }

    describe '#is_manager?' do
      it 'returns true for manager agents' do
        expect(manager.is_manager?).to be true
        expect(subject.is_manager?).to be false
      end
    end

    describe '#add_subordinate' do
      it 'adds subordinate to manager' do
        manager.add_subordinate(subordinate)
        expect(manager.subordinates).to include(subordinate)
      end

      it 'does not add subordinates to non-manager agents' do
        subject.add_subordinate(subordinate)
        expect(subject.subordinates).to be_empty
      end

      it 'does not add duplicate subordinates' do
        manager.add_subordinate(subordinate)
        manager.add_subordinate(subordinate)
        expect(manager.subordinates.size).to eq(1)
      end
    end

    describe '#delegate_task' do
      let(:task) { create_test_task }

      before do
        manager.add_subordinate(subordinate)
        allow(mock_llm_client).to receive(:chat).and_return(mock_llm_response(content: 'Delegation instructions'))
        allow(subordinate).to receive(:execute_delegated_task).and_return('Delegated task completed')
      end

      it 'delegates task to subordinate' do
        expect(subordinate).to receive(:execute_delegated_task)
          .with(task, 'Delegation instructions', manager)

        manager.delegate_task(task, subordinate)
      end

      it 'does not delegate if not a manager' do
        expect(subordinate).not_to receive(:execute_delegated_task)
        subject.delegate_task(task, subordinate)
      end

      it 'does not delegate to non-subordinates without delegation permission' do
        restricted_manager = create_test_agent(
          name: 'restricted_manager',
          role: 'Restricted Manager',
          goal: 'Manage with restrictions',
          manager: true,
          allow_delegation: false
        )
        other_agent = create_test_agent(name: 'other')
        expect(other_agent).not_to receive(:execute_delegated_task)
        restricted_manager.delegate_task(task, other_agent)
      end
    end
  end

  describe 'human interaction' do
    before do
      subject.enable_human_input(
        require_approval_for_tools: true,
        require_approval_for_final_answer: true
      )
    end

    describe '#enable_human_input' do
      it 'enables human input capabilities' do
        subject.disable_human_input # Start with disabled state
        subject.enable_human_input(
          require_approval_for_tools: true,
          require_approval_for_final_answer: true
        )

        expect(subject.human_input_enabled?).to be true
        expect(subject.instance_variable_get(:@require_approval_for_tools)).to be true
        expect(subject.instance_variable_get(:@require_approval_for_final_answer)).to be true
      end
    end

    describe '#disable_human_input' do
      it 'disables human input capabilities' do
        subject.disable_human_input
        expect(subject.human_input_enabled?).to be false
        expect(subject.instance_variable_get(:@require_approval_for_tools)).to be false
        expect(subject.instance_variable_get(:@require_approval_for_final_answer)).to be false
      end
    end
  end

  describe '#build_context' do
    let(:task) { create_test_task(agent: subject) }

    it 'builds comprehensive context' do
      context = subject.send(:build_context, task)

      expect(context).to include(
        agent_role: 'Test Agent',
        agent_goal: 'Test things effectively',
        agent_backstory: 'An agent created for testing purposes',
        task_description: task.description,
        task_expected_output: task.expected_output,
        available_tools: subject.available_tools_description
      )
    end

    it 'includes delegation note when allowed' do
      subject.allow_delegation = true
      context = subject.send(:build_context, task)
      expect(context[:delegation_note]).to include('delegate subtasks')
    end
  end

  describe 'runner selection' do
    let(:task) { create_test_task(agent: subject) }

    it 'extracts FINAL_ANSWER content from LegacyReactRunner output' do
      allow(mock_llm_client).to receive(:supports_native_tools?).and_return(false)
      allow(mock_llm_client).to receive(:chat).and_return(
        mock_llm_response(content: 'FINAL_ANSWER[Task completed successfully]')
      )
      result = subject.execute_task(task)
      expect(result[:content]).to eq('Task completed successfully')
    end

    it 'respects max iterations limit via runner' do
      allow(mock_llm_client).to receive(:supports_native_tools?).and_return(false)
      allow(mock_llm_client).to receive(:chat).and_return(
        mock_llm_response(content: 'Still working on it...')
      )

      result = subject.execute_task(task, max_iterations: 2)
      expect(result[:iterations]).to eq(2)
      expect(result[:finish_reason]).to eq(:max_iterations)
    end
  end
end

RSpec.describe RCrewAI::Agent do
  describe 'per-agent llm override' do
    before do
      configure_test_llm(provider: :openai, model: 'gpt-4')
    end

    it 'defaults to the global provider when llm is omitted' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g')

      expect(agent.llm_client).to be_a(RCrewAI::LLMClients::OpenAI)
    end

    it 'accepts a provider symbol' do
      RCrewAI.configuration.anthropic_api_key = 'test-key'
      agent = described_class.new(name: 'a', role: 'r', goal: 'g', llm: :anthropic)

      expect(agent.llm_client).to be_a(RCrewAI::LLMClients::Anthropic)
    end

    it 'accepts a provider + model hash' do
      RCrewAI.configuration.anthropic_api_key = 'test-key'
      agent = described_class.new(
        name: 'a', role: 'r', goal: 'g',
        llm: { provider: :anthropic, model: 'claude-3-opus-20240229' }
      )

      expect(agent.llm_client).to be_a(RCrewAI::LLMClients::Anthropic)
      expect(agent.llm_client.config.model).to eq('claude-3-opus-20240229')
    end

    it 'does not mutate the global configuration' do
      RCrewAI.configuration.anthropic_api_key = 'test-key'
      described_class.new(name: 'a', role: 'r', goal: 'g', llm: :anthropic)

      expect(RCrewAI.configuration.llm_provider).to eq(:openai)
    end

    it 'accepts a pre-built client instance' do
      custom = instance_double(RCrewAI::LLMClients::Base, chat: nil)
      agent = described_class.new(name: 'a', role: 'r', goal: 'g', llm: custom)

      expect(agent.llm_client).to eq(custom)
    end

    it 'lets agents in the same crew use different models' do
      RCrewAI.configuration.anthropic_api_key = 'test-key'
      worker  = described_class.new(name: 'w', role: 'r', goal: 'g',
                                    llm: { provider: :openai, model: 'gpt-4o-mini' })
      manager = described_class.new(name: 'm', role: 'r', goal: 'g',
                                    llm: { provider: :anthropic, model: 'claude-3-opus-20240229' })

      expect(worker.llm_client).to be_a(RCrewAI::LLMClients::OpenAI)
      expect(worker.llm_client.config.model).to eq('gpt-4o-mini')
      expect(manager.llm_client).to be_a(RCrewAI::LLMClients::Anthropic)
      expect(manager.llm_client.config.model).to eq('claude-3-opus-20240229')
    end
  end
end

RSpec.describe RCrewAI::Agent do
  let(:mock_llm_client) { double('LLMClient') }

  before do
    configure_test_llm
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(mock_llm_client)
    allow(mock_llm_client).to receive(:supports_native_tools?).and_return(false)
  end

  describe 'reasoning' do
    it 'defaults reasoning off' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g')

      expect(agent.reasoning?).to be false
    end

    it 'accepts reasoning: true' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g', reasoning: true)

      expect(agent.reasoning?).to be true
    end

    # The LegacyReactRunner stops when the content contains FINAL_ANSWER[...],
    # so answer responses use that form to keep chat-call counts deterministic.
    def answer(text)
      mock_llm_response(content: "FINAL_ANSWER[#{text}]")
    end

    it 'runs a reasoning pass before answering and exposes the trace' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g', reasoning: true)
      task = create_test_task(agent: agent)

      # First chat = reasoning pass, second = the actual answer.
      allow(mock_llm_client).to receive(:chat).and_return(
        mock_llm_response(content: 'Step 1: gather data. Step 2: summarize.'),
        answer('The final answer.')
      )

      result = agent.execute_task(task)

      expect(result[:reasoning]).to include('Step 1: gather data')
      expect(result[:content]).to eq('The final answer.')
      expect(task.result).to eq('The final answer.') # trace does not pollute result
    end

    it 'does not run a reasoning pass when disabled' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g')
      task = create_test_task(agent: agent)

      allow(mock_llm_client).to receive(:chat).and_return(answer('The final answer.'))

      result = agent.execute_task(task)

      expect(result[:reasoning]).to be_nil
      expect(mock_llm_client).to have_received(:chat).once
    end

    it 'retries the reasoning pass up to max_reasoning_attempts on empty output' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g',
                                  reasoning: true, max_reasoning_attempts: 3)
      task = create_test_task(agent: agent)

      # Two empty reasoning attempts, then a good one, then the answer.
      allow(mock_llm_client).to receive(:chat).and_return(
        mock_llm_response(content: ''),
        mock_llm_response(content: '   '),
        mock_llm_response(content: 'A solid plan.'),
        answer('The final answer.')
      )

      result = agent.execute_task(task)

      expect(result[:reasoning]).to eq('A solid plan.')
      expect(result[:content]).to eq('The final answer.')
    end

    it 'proceeds without reasoning if all attempts fail' do
      agent = described_class.new(name: 'a', role: 'r', goal: 'g',
                                  reasoning: true, max_reasoning_attempts: 2)
      task = create_test_task(agent: agent)

      allow(mock_llm_client).to receive(:chat).and_return(
        mock_llm_response(content: ''),
        mock_llm_response(content: ''),
        answer('The final answer.')
      )

      result = agent.execute_task(task)

      expect(result[:reasoning]).to be_nil
      expect(result[:content]).to eq('The final answer.')
    end
  end
end
