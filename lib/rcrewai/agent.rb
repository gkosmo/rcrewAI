# frozen_string_literal: true

require 'logger'
require_relative 'llm_client'
require_relative 'memory'
require_relative 'tools/base'
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
      @manager = options.fetch(:manager, false)  # New manager flag
      @max_iterations = options.fetch(:max_iterations, 10)
      @max_execution_time = options.fetch(:max_execution_time, 300) # 5 minutes
      @human_input_enabled = options.fetch(:human_input, false)
      @require_approval_for_tools = options.fetch(:require_approval_for_tools, false)
      @require_approval_for_final_answer = options.fetch(:require_approval_for_final_answer, false)
      @logger = Logger.new($stdout)
      @logger.level = verbose ? Logger::DEBUG : Logger::INFO
      @memory = Memory.new
      @llm_client = LLMClient.for_provider
      @subordinates = []  # For manager agents
    end

    def execute_task(task)
      @logger.info "Agent #{name} starting task: #{task.name}"
      start_time = Time.now

      begin
        # Build context for the agent
        context = build_context(task)
        
        # Execute task with reasoning loop
        result = reasoning_loop(task, context)
        
        execution_time = Time.now - start_time
        @logger.info "Task completed in #{execution_time.round(2)}s"
        
        # Store in memory
        memory.add_execution(task, result, execution_time)
        
        task.result = result
        result

      rescue => e
        @logger.error "Task execution failed: #{e.message}"
        task.result = "Task failed: #{e.message}"
        raise AgentError, "Agent #{name} failed to execute task: #{e.message}"
      end
    end

    def available_tools_description
      return "No tools available." if tools.empty?

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
      rescue => e
        @logger.error "Tool execution failed: #{e.message}"
        
        # Offer human intervention if tool fails and human input is enabled
        if @human_input_enabled
          handle_tool_failure(tool_name, params, e)
        else
          raise e
        end
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

    def subordinates
      @subordinates
    end

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
      if allow_delegation
        context[:delegation_note] = "You can delegate subtasks to other agents if needed."
      end

      context
    end

    def reasoning_loop(task, context)
      iteration = 0
      start_time = Time.now

      loop do
        iteration += 1
        current_time = Time.now

        # Check limits
        if iteration > max_iterations
          @logger.warn "Max iterations (#{max_iterations}) reached"
          break
        end

        if current_time - start_time > max_execution_time
          @logger.warn "Max execution time (#{max_execution_time}s) reached"
          break
        end

        # Human review of reasoning at key points
        if @human_input_enabled && (iteration == 1 || iteration % 3 == 0)
          review_result = request_reasoning_review(task, context, iteration)
          if review_result && review_result[:feedback]
            context[:human_guidance] = review_result[:feedback]
            @logger.info "Incorporating human guidance into reasoning"
          end
        end

        # Generate reasoning prompt
        prompt = build_reasoning_prompt(context, iteration)
        
        # Get LLM response
        @logger.debug "Iteration #{iteration}: Sending prompt to LLM"
        response = llm_client.chat(
          messages: [{ role: 'user', content: prompt }],
          temperature: 0.1,
          max_tokens: 2000
        )

        reasoning = response[:content]
        @logger.debug "LLM Response: #{reasoning[0..200]}..." if verbose

        # Parse and execute actions
        action_result = parse_and_execute_actions(reasoning, task)
        
        # Check if task is complete
        if task_complete?(reasoning, action_result)
          final_result = extract_final_result(reasoning, action_result)
          
          # Human approval of final result if required
          if @require_approval_for_final_answer && @human_input_enabled
            final_result = request_final_answer_approval(final_result)
          end
          
          @logger.info "Task completed successfully in #{iteration} iterations"
          return final_result
        end

        # Update context with new information
        context[:previous_reasoning] = reasoning
        context[:previous_result] = action_result
        context[:iteration] = iteration
      end

      # If we exit the loop without completion, return best effort result
      final_result = extract_final_result(context[:previous_reasoning], context[:previous_result]) || 
        "Task execution reached limits without clear completion"
      
      # Human approval even for incomplete results if required
      if @require_approval_for_final_answer && @human_input_enabled
        final_result = request_final_answer_approval(final_result)
      end
      
      final_result
    end

    def build_reasoning_prompt(context, iteration)
      prompt = <<~PROMPT
        You are #{context[:agent_role]}.
        
        Your goal: #{context[:agent_goal]}
        
        Background: #{context[:agent_backstory]}
        
        Current Task: #{context[:task_description]}
        Expected Output: #{context[:task_expected_output]}
        
        Available Tools:
        #{context[:available_tools]}
        
        #{context[:delegation_note] if context[:delegation_note]}
        
        #{build_context_section(context)}
        
        This is iteration #{iteration}. Think step by step about how to approach this task.
        
        You can:
        1. Use tools by writing: USE_TOOL[tool_name](param1=value1, param2=value2)
        2. Provide your final answer when ready: FINAL_ANSWER[your complete response]
        3. Continue reasoning if you need more information
        
        What is your next step?
      PROMPT

      prompt
    end

    def build_context_section(context)
      sections = []
      
      if context[:context_data] && !context[:context_data].empty?
        sections << "Additional Context:\n#{context[:context_data]}"
      end
      
      if context[:previous_executions] && !context[:previous_executions].empty?
        sections << "Previous Similar Tasks:\n#{context[:previous_executions]}"
      end
      
      if context[:human_guidance]
        sections << "Human Guidance:\n#{context[:human_guidance]}"
      end
      
      if context[:previous_reasoning]
        sections << "Previous Reasoning:\n#{context[:previous_reasoning]}"
      end
      
      if context[:previous_result]
        sections << "Previous Action Result:\n#{context[:previous_result]}"
      end
      
      sections.join("\n\n")
    end

    def parse_and_execute_actions(reasoning, task)
      results = []

      # Look for tool usage patterns
      tool_matches = reasoning.scan(/USE_TOOL\[(\w+)\]\(([^)]*)\)/)
      tool_matches.each do |tool_name, params_str|
        begin
          params = parse_tool_params(params_str)
          result = use_tool(tool_name, **params)
          results << "Tool #{tool_name} result: #{result}"
        rescue => e
          results << "Tool #{tool_name} failed: #{e.message}"
          @logger.error "Tool execution failed: #{e.message}"
        end
      end

      results.join("\n")
    end

    def parse_tool_params(params_str)
      params = {}
      return params if params_str.strip.empty?

      param_pairs = params_str.split(',').map(&:strip)
      param_pairs.each do |pair|
        key, value = pair.split('=', 2).map(&:strip)
        if key && value
          # Remove quotes if present
          value = value.gsub(/^["']|["']$/, '')
          params[key.to_sym] = value
        end
      end

      params
    end

    def task_complete?(reasoning, action_result)
      reasoning.include?('FINAL_ANSWER[') || 
      reasoning.downcase.include?('task complete') ||
      reasoning.downcase.include?('finished')
    end

    def extract_final_result(reasoning, action_result)
      # Look for FINAL_ANSWER pattern
      if match = reasoning.match(/FINAL_ANSWER\[(.*?)\]$/m)
        return match[1].strip
      end

      # Otherwise try to extract meaningful result from reasoning
      lines = reasoning.split("\n").map(&:strip).reject(&:empty?)
      final_lines = lines.last(3).join(" ")
      
      return final_lines if final_lines.length > 20
      
      # Fallback to action result
      action_result
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
        timeout: 60
      )
    end

    def handle_tool_failure(tool_name, params, error)
      @logger.warn "Requesting human intervention for tool failure"
      
      choices = [
        "Retry with same parameters",
        "Retry with different parameters", 
        "Skip this tool and continue",
        "Abort task execution"
      ]
      
      choice_result = request_human_choice(
        "Tool '#{tool_name}' failed with error: #{error.message}. How should I proceed?",
        choices,
        timeout: 120
      )
      
      case choice_result[:choice_index]
      when 0
        # Retry with same parameters
        @logger.info "Human requested retry with same parameters"
        tool = tools.find { |t| t.name == tool_name }
        tool.execute(**params)
      when 1
        # Retry with different parameters
        new_params_result = request_human_input(
          "Please provide new parameters for #{tool_name} (JSON format):",
          type: :json,
          help_text: "Enter parameters as JSON, e.g. {\"param1\": \"value1\"}"
        )
        
        if new_params_result[:valid]
          @logger.info "Human provided new parameters, retrying tool"
          tool = tools.find { |t| t.name == tool_name }
          tool.execute(**new_params_result[:processed_input])
        else
          "Invalid parameters provided: #{new_params_result[:reason]}"
        end
      when 2
        # Skip tool
        @logger.info "Human requested to skip failed tool"
        "Tool execution skipped by human intervention"
      else
        # Abort
        @logger.error "Human requested task abortion due to tool failure"
        raise AgentError, "Task aborted by human due to tool failure: #{error.message}"
      end
    end

    def request_final_answer_approval(proposed_answer)
      return proposed_answer unless @require_approval_for_final_answer && @human_input_enabled
      
      review_result = request_human_review(
        proposed_answer,
        review_criteria: ["Accuracy", "Completeness", "Clarity", "Relevance"],
        timeout: 180
      )
      
      if review_result[:approved]
        @logger.info "Final answer approved by human"
        proposed_answer
      else
        @logger.info "Human provided feedback on final answer"
        
        if review_result[:suggested_changes].any?
          @logger.info "Suggested changes: #{review_result[:suggested_changes].join('; ')}"
          
          # Ask human what to do with the feedback
          choice_result = request_human_choice(
            "How should I handle your feedback?",
            [
              "Revise the answer based on feedback",
              "Use the answer as-is despite feedback",
              "Let me provide a completely new answer"
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
              "Please provide the final answer:",
              help_text: "Provide the complete answer for this task"
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
      @logger.info "Revising answer based on human feedback"
      
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
        review_criteria: ["Task approach", "Progress assessment", "Strategic guidance"],
        timeout: 30,
        optional: true
      )
    rescue => e
      @logger.warn "Failed to get human reasoning review: #{e.message}"
      nil
    end

    class CLI < Thor
      desc "new NAME", "Create a new agent"
      option :role, type: :string, required: true
      option :goal, type: :string, required: true
      option :backstory, type: :string
      option :verbose, type: :boolean, default: false
      def new(name)
        agent = Agent.new(
          name: name,
          role: options[:role],
          goal: options[:goal],
          backstory: options[:backstory],
          verbose: options[:verbose]
        )
        puts "Agent '#{name}' created with role: #{options[:role]}"
      end

      desc "list", "List all agents"
      def list
        puts "Available agents:"
        puts "  - researcher (Role: Research Specialist)"
        puts "  - writer (Role: Content Writer)"
        puts "  - analyst (Role: Data Analyst)"
      end
    end
  end

  class AgentError < Error; end
  class ToolNotFoundError < AgentError; end
end