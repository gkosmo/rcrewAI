# frozen_string_literal: true

require 'logger'
require_relative 'llm_client'
require_relative 'memory'
require_relative 'tools/base'
require_relative 'tool_runner'
require_relative 'legacy_react_runner'
require_relative 'human_input'

module RCrewAI
  class Agent
    include HumanInteractionExtensions
    attr_reader :name, :role, :goal, :backstory, :tools, :memory, :llm_client
    attr_accessor :verbose, :allow_delegation, :max_iterations, :max_execution_time, :manager

    def initialize(name:, role:, goal:, backstory: nil, tools: [], **options)
      @name = name
      @role = role
      @goal = goal
      @backstory = backstory
      @tools = tools
      @verbose = options.fetch(:verbose, false)
      @allow_delegation = options.fetch(:allow_delegation, false)
      @manager = options.fetch(:manager, false) # New manager flag
      @max_iterations = options.fetch(:max_iterations, 10)
      @max_execution_time = options.fetch(:max_execution_time, 300) # 5 minutes
      @human_input_enabled = options.fetch(:human_input, false)
      @require_approval_for_tools = options.fetch(:require_approval_for_tools, false)
      @require_approval_for_final_answer = options.fetch(:require_approval_for_final_answer, false)
      @logger = Logger.new($stdout)
      @logger.level = verbose ? Logger::DEBUG : Logger::INFO
      @memory = Memory.new
      @llm_client = LLMClient.for_provider
      @subordinates = [] # For manager agents
    end

    def execute_task(task, stream: nil, **opts)
      @logger.info "Agent #{name} starting task: #{task.name}"
      start_time = Time.now

      begin
        initial_messages = build_initial_messages(task)
        sink = stream || ->(_) {}

        runner_class = pick_runner_class
        @logger.info "[rcrewai] agent=#{name} runner=#{runner_class.name.split('::').last}"

        runner = runner_class.new(
          agent: self, llm: @llm_client, tools: @tools,
          max_iterations: opts.fetch(:max_iterations, max_iterations),
          event_sink: sink
        )

        runner_result = runner.run(messages: initial_messages)
        execution_time = Time.now - start_time
        @logger.info "Task completed in #{execution_time.round(2)}s"

        result_string = runner_result[:content].to_s
        memory.add_execution(task, result_string, execution_time)
        task.result = result_string

        build_task_result(task, runner_result)
      rescue StandardError => e
        @logger.error "Task execution failed: #{e.message}"
        task.result = "Task failed: #{e.message}"
        raise AgentError, "Agent #{name} failed to execute task: #{e.message}"
      end
    end

    def require_approval_for_tools?
      @require_approval_for_tools && @human_input_enabled
    end

    def available_tools_description
      return 'No tools available.' if tools.empty?

      tools.map do |tool|
        "- #{tool.name}: #{tool.description}"
      end.join("\n")
    end

    def use_tool(tool_name, **params)
      tool = tools.find { |t| t.name == tool_name || t.class.name.split('::').last.downcase == tool_name.downcase }
      raise ToolNotFoundError, "Tool '#{tool_name}' not found" unless tool

      # Request human approval for tool usage if required
      if @require_approval_for_tools && @human_input_enabled
        approval_result = request_tool_approval(tool_name, params)
        unless approval_result[:approved]
          @logger.info "Tool usage rejected by human: #{tool_name}"
          return "Tool usage was rejected by human reviewer: #{approval_result[:reason]}"
        end
      end

      @logger.debug "Using tool: #{tool_name} with params: #{params}"

      begin
        result = tool.execute(**params)

        # Store tool usage in memory
        memory.add_tool_usage(tool_name, params, result)

        result
      rescue StandardError => e
        @logger.error "Tool execution failed: #{e.message}"

        # Offer human intervention if tool fails and human input is enabled
        raise e unless @human_input_enabled

        handle_tool_failure(tool_name, params, e)
      end
    end

    # Manager-specific methods
    def is_manager?
      @manager
    end

    def add_subordinate(agent)
      return unless is_manager?

      @subordinates << agent unless @subordinates.include?(agent)
    end

    attr_reader :subordinates

    def delegate_task(task, target_agent)
      return unless is_manager?
      return unless @subordinates.include?(target_agent) || allow_delegation

      @logger.info "Manager #{name} delegating task '#{task.name}' to #{target_agent.name}"

      # Create delegation context
      delegation_prompt = build_delegation_prompt(task, target_agent)

      # Use LLM to create proper delegation
      response = llm_client.chat(
        messages: [{ role: 'user', content: delegation_prompt }],
        temperature: 0.2,
        max_tokens: 1000
      )

      delegation_instructions = response[:content]
      @logger.debug "Delegation instructions: #{delegation_instructions}"

      # Execute delegated task
      target_agent.execute_delegated_task(task, delegation_instructions, self)
    end

    def execute_delegated_task(task, delegation_instructions, manager_agent)
      @logger.info "Receiving delegation from manager #{manager_agent.name}"
      @logger.debug "Delegation instructions: #{delegation_instructions}"

      # Store delegation context in task
      original_description = task.description
      enhanced_description = "#{original_description}\n\nDelegation Instructions from #{manager_agent.name}:\n#{delegation_instructions}"

      # Temporarily modify task
      task.instance_variable_set(:@description, enhanced_description)
      task.instance_variable_set(:@manager, manager_agent)

      begin
        result = execute_task(task)

        # Report back to manager
        report_to_manager(task, result, manager_agent)

        result
      ensure
        # Restore original task description
        task.instance_variable_set(:@description, original_description)
      end
    end

    # Human input methods (public)
    def enable_human_input(**options)
      @human_input_enabled = true
      @require_approval_for_tools = options.fetch(:require_approval_for_tools, false)
      @require_approval_for_final_answer = options.fetch(:require_approval_for_final_answer, false)
      @logger.info "Human input enabled for agent #{name}"
    end

    def disable_human_input
      @human_input_enabled = false
      @require_approval_for_tools = false
      @require_approval_for_final_answer = false
      @logger.info "Human input disabled for agent #{name}"
    end

    def human_input_enabled?
      @human_input_enabled
    end

    private

    def build_context(task)
      context = {
        agent_role: role,
        agent_goal: goal,
        agent_backstory: backstory,
        task_description: task.description,
        task_expected_output: task.expected_output,
        available_tools: available_tools_description,
        previous_executions: memory.relevant_executions(task),
        context_data: task.context_data
      }

      # Add delegation capabilities if allowed
      context[:delegation_note] = 'You can delegate subtasks to other agents if needed.' if allow_delegation

      context
    end

    def build_initial_messages(task)
      ctx = build_context(task)
      system = +"You are #{ctx[:agent_role]}. Goal: #{ctx[:agent_goal]}."
      system << " #{ctx[:agent_backstory]}" if ctx[:agent_backstory]
      if @tools.any?
        system << "\nAvailable Tools:\n#{ctx[:available_tools]}"
        system << "\nYou may call tools by name when needed."
      end
      system << "\n#{ctx[:delegation_note]}" if ctx[:delegation_note]

      user = +"Task: #{task.description}"
      user << "\nExpected Output: #{task.expected_output}" if task.expected_output
      user << "\nAdditional Context:\n#{ctx[:context_data]}" if ctx[:context_data] && !ctx[:context_data].to_s.empty?

      [
        { role: 'system', content: system },
        { role: 'user', content: user }
      ]
    end

    def build_task_result(task, runner_result)
      {
        task: task.name,
        agent: name,
        content: runner_result[:content],
        tool_calls_history: runner_result[:tool_calls_history] || [],
        usage: runner_result[:usage] || {},
        iterations: runner_result[:iterations],
        finish_reason: runner_result[:finish_reason]
      }
    end

    def pick_runner_class
      schemas_ok = @tools.empty? || @tools.all? { |t| t.respond_to?(:json_schema) && t.json_schema }
      native = @llm_client.respond_to?(:supports_native_tools?) &&
               safe_supports_native?(@llm_client)
      schemas_ok && native ? ToolRunner : LegacyReactRunner
    end

    def safe_supports_native?(llm)
      model = llm.respond_to?(:config) && llm.config.respond_to?(:model) ? llm.config.model : nil
      llm.supports_native_tools?(model: model)
    rescue StandardError
      false
    end

    # Manager-specific private methods
    def build_delegation_prompt(task, target_agent)
      <<~PROMPT
        You are #{name}, a #{role}.

        You need to delegate the following task to #{target_agent.name} (#{target_agent.role}):

        Task: #{task.name}
        Description: #{task.description}
        Expected Output: #{task.expected_output || 'Not specified'}

        Target Agent Profile:
        - Role: #{target_agent.role}
        - Goal: #{target_agent.goal}
        - Available Tools: #{target_agent.available_tools_description}

        Create clear, specific delegation instructions that:
        1. Explain why this agent is the right choice for this task
        2. Provide any additional context or requirements
        3. Set clear expectations for deliverables
        4. Include any coordination notes with other team members

        Keep instructions concise but comprehensive.
      PROMPT
    end

    def report_to_manager(task, result, manager_agent)
      @logger.info "Reporting task completion to manager #{manager_agent.name}"

      # Store the delegation result in manager's memory
      manager_agent.memory.add_execution(
        task,
        "Delegated to #{name}: #{result}",
        task.execution_time || 0
      )

      # Could enhance with formal reporting mechanism
    end

    # Human interaction methods
    def request_tool_approval(tool_name, params)
      message = "Agent #{name} wants to use tool '#{tool_name}'"
      context = "Parameters: #{params.inspect}"
      consequences = "This will execute the #{tool_name} tool with the specified parameters."

      request_human_approval(message,
                             context: context,
                             consequences: consequences,
                             timeout: 60)
    end

    def handle_tool_failure(tool_name, params, error)
      @logger.warn 'Requesting human intervention for tool failure'

      choices = [
        'Retry with same parameters',
        'Retry with different parameters',
        'Skip this tool and continue',
        'Abort task execution'
      ]

      choice_result = request_human_choice(
        "Tool '#{tool_name}' failed with error: #{error.message}. How should I proceed?",
        choices,
        timeout: 120
      )

      case choice_result[:choice_index]
      when 0
        # Retry with same parameters
        @logger.info 'Human requested retry with same parameters'
        tool = tools.find { |t| t.name == tool_name }
        tool.execute(**params)
      when 1
        # Retry with different parameters
        new_params_result = request_human_input(
          "Please provide new parameters for #{tool_name} (JSON format):",
          type: :json,
          help_text: 'Enter parameters as JSON, e.g. {"param1": "value1"}'
        )

        if new_params_result[:valid]
          @logger.info 'Human provided new parameters, retrying tool'
          tool = tools.find { |t| t.name == tool_name }
          tool.execute(**new_params_result[:processed_input])
        else
          "Invalid parameters provided: #{new_params_result[:reason]}"
        end
      when 2
        # Skip tool
        @logger.info 'Human requested to skip failed tool'
        'Tool execution skipped by human intervention'
      else
        # Abort
        @logger.error 'Human requested task abortion due to tool failure'
        raise AgentError, "Task aborted by human due to tool failure: #{error.message}"
      end
    end

    def request_final_answer_approval(proposed_answer)
      return proposed_answer unless @require_approval_for_final_answer && @human_input_enabled

      review_result = request_human_review(
        proposed_answer,
        review_criteria: %w[Accuracy Completeness Clarity Relevance],
        timeout: 180
      )

      if review_result[:approved]
        @logger.info 'Final answer approved by human'
        proposed_answer
      else
        @logger.info 'Human provided feedback on final answer'

        if review_result[:suggested_changes].any?
          @logger.info "Suggested changes: #{review_result[:suggested_changes].join('; ')}"

          # Ask human what to do with the feedback
          choice_result = request_human_choice(
            'How should I handle your feedback?',
            [
              'Revise the answer based on feedback',
              'Use the answer as-is despite feedback',
              'Let me provide a completely new answer'
            ]
          )

          case choice_result[:choice_index]
          when 0
            # Revise based on feedback
            revision_context = "Original answer: #{proposed_answer}\n\nFeedback: #{review_result[:feedback]}"
            revise_answer_with_feedback(revision_context)
          when 1
            # Use as-is
            proposed_answer
          when 2
            # Get new answer from human
            new_answer_result = request_human_input(
              'Please provide the final answer:',
              help_text: 'Provide the complete answer for this task'
            )
            new_answer_result[:input] || proposed_answer
          else
            proposed_answer
          end
        else
          # Generic feedback without specific suggestions
          revise_answer_with_feedback("Original answer: #{proposed_answer}\n\nFeedback: #{review_result[:feedback]}")
        end
      end
    end

    def revise_answer_with_feedback(feedback_context)
      @logger.info 'Revising answer based on human feedback'

      revision_prompt = <<~PROMPT
        You are #{name}, a #{role}.

        You need to revise your previous answer based on human feedback.

        #{feedback_context}

        Please provide a revised answer that addresses the feedback while maintaining accuracy and completeness.

        Revised answer:
      PROMPT

      response = llm_client.chat(
        messages: [{ role: 'user', content: revision_prompt }],
        temperature: 0.2,
        max_tokens: 1000
      )

      revised_answer = response[:content]
      @logger.debug "Revised answer based on feedback: #{revised_answer[0..100]}..."

      revised_answer
    end

    def request_reasoning_review(task, context, iteration)
      return nil unless @human_input_enabled

      review_content = <<~CONTENT
        Task: #{task.name}
        Description: #{task.description}

        Current Iteration: #{iteration}

        Agent Analysis:
        - Role: #{role}
        - Current Progress: #{context[:previous_result] || 'Starting task'}
        - Previous Reasoning: #{context[:previous_reasoning] || 'No previous reasoning'}

        The agent is about to continue reasoning for this task.
      CONTENT

      request_human_review(
        review_content,
        review_criteria: ['Task approach', 'Progress assessment', 'Strategic guidance'],
        timeout: 30,
        optional: true
      )
    rescue StandardError => e
      @logger.warn "Failed to get human reasoning review: #{e.message}"
      nil
    end

    class CLI < Thor
      desc 'new NAME', 'Create a new agent'
      option :role, type: :string, required: true
      option :goal, type: :string, required: true
      option :backstory, type: :string
      option :verbose, type: :boolean, default: false
      def new(name)
        Agent.new(
          name: name,
          role: options[:role],
          goal: options[:goal],
          backstory: options[:backstory],
          verbose: options[:verbose]
        )
        puts "Agent '#{name}' created with role: #{options[:role]}"
      end

      desc 'list', 'List all agents'
      def list
        puts 'Available agents:'
        puts '  - researcher (Role: Research Specialist)'
        puts '  - writer (Role: Content Writer)'
        puts '  - analyst (Role: Data Analyst)'
      end
    end
  end

  class AgentError < Error; end
  class ToolNotFoundError < AgentError; end
end
