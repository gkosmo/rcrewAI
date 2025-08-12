# frozen_string_literal: true

require_relative 'async_executor'
require_relative 'human_input'

module RCrewAI
  class Task
    include AsyncExtensions
    include HumanInteractionExtensions
    attr_reader :name, :description, :agent, :context, :expected_output, :tools, :async
    attr_accessor :result, :status, :start_time, :end_time, :execution_time

    def initialize(name:, description:, agent: nil, **options)
      @name = name
      @description = description
      @agent = agent
      @expected_output = options[:expected_output]
      @context = options[:context] || []  # Tasks this task depends on
      @tools = options[:tools] || []      # Additional tools for this specific task
      @async = options[:async] || false   # Whether task can run asynchronously
      @callback = options[:callback]      # Callback function after completion
      
      # Human interaction options
      @human_input_enabled = options[:human_input] || false
      @require_human_confirmation = options[:require_confirmation] || false
      @allow_human_guidance = options[:allow_guidance] || false
      @human_review_points = options[:human_review_points] || []
      
      @result = nil
      @status = :pending
      @start_time = nil
      @end_time = nil
      @execution_time = nil
      @retry_count = 0
      @max_retries = options.fetch(:max_retries, 2)
    end

    def execute
      @start_time = Time.now
      @status = :running

      begin
        # Human confirmation before starting if required
        if @require_human_confirmation
          confirmation_result = confirm_task_execution
          unless confirmation_result[:approved]
            @status = :cancelled
            @result = "Task execution cancelled by human: #{confirmation_result[:reason]}"
            return @result
          end
        end

        if agent
          validate_dependencies!
          provide_context_to_agent
          
          # Enable human input for agent if task allows it
          if @human_input_enabled && agent.respond_to?(:enable_human_input)
            agent.enable_human_input(
              require_approval_for_tools: false,
              require_approval_for_final_answer: @allow_human_guidance
            )
          end
          
          @result = agent.execute_task(self)
          
          # Post-execution human review if configured
          if @human_input_enabled && @human_review_points.include?(:completion)
            review_result = request_task_completion_review
            if review_result && !review_result[:approved]
              @result = handle_completion_review_feedback(review_result)
            end
          end
          
          @status = :completed
        else
          @result = "Task requires an agent"
          @status = :failed
        end

        @end_time = Time.now
        @execution_time = @end_time - @start_time
        
        # Execute callback if provided
        @callback&.call(self, @result)
        
        @result

      rescue TaskDependencyError => e
        # Don't retry dependency errors - they need dependencies to be completed first
        @status = :failed
        @end_time = Time.now
        @execution_time = @end_time - @start_time if @start_time
        @result = "Task dependencies not met: #{e.message}"
        raise e
      rescue => e
        @status = :failed
        @end_time = Time.now
        @execution_time = @end_time - @start_time if @start_time
        
        # Retry logic with human intervention
        if @retry_count < @max_retries
          @retry_count += 1
          puts "Task #{name} failed, retrying (#{@retry_count}/#{@max_retries})"
          
          # Ask human for retry guidance if enabled
          if @human_input_enabled
            retry_decision = request_retry_guidance(e)
            case retry_decision[:choice]
            when 'abort'
              @result = "Task execution aborted by human after failure: #{e.message}"
              raise TaskExecutionError, "Task '#{name}' aborted by human"
            when 'modify'
              # Allow human to modify task parameters
              modification_result = request_task_modification
              if modification_result[:modified]
                apply_task_modifications(modification_result[:changes])
              end
            # 'retry' is the default - continue with retry logic
            end
          end
          
          @status = :pending
          sleep(2 ** @retry_count) # Exponential backoff
          return execute
        end

        @result = "Task failed after #{@max_retries} retries: #{e.message}"
        raise TaskExecutionError, "Task '#{name}' failed: #{e.message}"
      ensure
        # Disable human input for agent after task completion
        if @human_input_enabled && agent.respond_to?(:disable_human_input)
          agent.disable_human_input
        end
      end
    end

    def context_data
      return "" if context.empty?

      context_results = context.map do |task|
        if task.completed?
          "Task: #{task.name}\nResult: #{task.result}\n---"
        else
          "Task: #{task.name}\nStatus: #{task.status}\n---"
        end
      end

      "Context from previous tasks:\n#{context_results.join("\n")}"
    end

    def completed?
      @status == :completed
    end

    def failed?
      @status == :failed
    end

    def running?
      @status == :running
    end

    def pending?
      @status == :pending
    end

    def dependencies_met?
      context.all?(&:completed?)
    end

    def add_context_task(task)
      @context << task unless @context.include?(task)
    end

    def add_tool(tool)
      @tools << tool unless @tools.include?(tool)
    end

    def enable_human_input(**options)
      @human_input_enabled = true
      @require_human_confirmation = options.fetch(:require_confirmation, false)
      @allow_human_guidance = options.fetch(:allow_guidance, false)
      @human_review_points = options.fetch(:review_points, [])
    end

    def disable_human_input
      @human_input_enabled = false
      @require_human_confirmation = false
      @allow_human_guidance = false
      @human_review_points = []
    end

    def human_input_enabled?
      @human_input_enabled
    end

    private

    def confirm_task_execution
      message = "Confirm execution of task: #{name}"
      context = "Description: #{description}\nExpected Output: #{expected_output || 'Not specified'}\nAssigned Agent: #{agent&.name || 'No agent'}"
      consequences = "The task will be executed with the specified agent and may use external tools."
      
      request_human_approval(message,
        context: context,
        consequences: consequences,
        timeout: 60
      )
    end

    def request_task_completion_review
      review_content = <<~CONTENT
        Task: #{name}
        Description: #{description}
        Expected Output: #{expected_output || 'Not specified'}
        
        Actual Result:
        #{result}
        
        Execution Time: #{execution_time&.round(2)} seconds
        Agent: #{agent&.name || 'Unknown'}
      CONTENT

      request_human_review(
        review_content,
        review_criteria: ["Accuracy", "Completeness", "Meets expectations"],
        timeout: 120
      )
    end

    def handle_completion_review_feedback(review_result)
      if review_result[:suggested_changes] && review_result[:suggested_changes].any?
        # Ask human how to handle the feedback
        choice_result = request_human_choice(
          "Task completed but received feedback. How should I proceed?",
          [
            "Accept result as-is despite feedback",
            "Request agent revision based on feedback", 
            "Let me provide the correct result"
          ],
          timeout: 60
        )

        case choice_result[:choice_index]
        when 0
          result # Return original result
        when 1
          # Request agent to revise (simplified)
          revised_result = "#{result}\n\nNote: Human feedback received: #{review_result[:feedback]}"
          revised_result
        when 2
          # Get corrected result from human
          correction_result = request_human_input(
            "Please provide the corrected task result:",
            help_text: "Enter the complete, corrected result for this task"
          )
          correction_result[:input] || result
        else
          result
        end
      else
        result
      end
    end

    def request_retry_guidance(error)
      choices = [
        "Retry with current settings",
        "Modify task parameters and retry",
        "Abort task execution"
      ]

      choice_result = request_human_choice(
        "Task '#{name}' failed with error: #{error.message}. How should I proceed?",
        choices,
        timeout: 120
      )

      {
        choice: case choice_result[:choice_index]
                when 0 then 'retry'
                when 1 then 'modify'
                when 2 then 'abort'
                else 'retry'
                end,
        reason: choice_result[:choice] || 'Default retry'
      }
    end

    def request_task_modification
      modification_input = request_human_input(
        "Please specify task modifications (JSON format):",
        type: :json,
        help_text: "Provide modifications as JSON, e.g. {\"description\": \"new description\", \"expected_output\": \"new output\"}"
      )

      if modification_input[:valid]
        {
          modified: true,
          changes: modification_input[:processed_input]
        }
      else
        {
          modified: false,
          reason: modification_input[:reason]
        }
      end
    end

    def apply_task_modifications(changes)
      changes.each do |key, value|
        case key.to_s
        when 'description'
          @description = value
        when 'expected_output'
          @expected_output = value
        when 'max_retries'
          @max_retries = value.to_i if value.to_i > 0
        end
      end
    end

    def validate_dependencies!
      unless dependencies_met?
        incomplete_deps = context.reject(&:completed?).map(&:name)
        raise TaskDependencyError, "Dependencies not met: #{incomplete_deps.join(', ')}"
      end
    end

    def provide_context_to_agent
      # Temporarily add task-specific tools to agent
      original_tools = agent.tools.dup
      combined_tools = (agent.tools + @tools).uniq
      
      # Use metaprogramming to temporarily extend agent's tools
      agent.instance_variable_set(:@tools, combined_tools)
      
      # Restore original tools after execution (handled by ensure in execute method)
      at_exit { agent.instance_variable_set(:@tools, original_tools) }
    end

    class CLI < Thor
      desc "new NAME", "Create a new task"
      option :description, type: :string, required: true
      option :agent, type: :string
      option :expected_output, type: :string
      option :async, type: :boolean, default: false
      def new(name)
        task = Task.new(
          name: name,
          description: options[:description],
          agent: options[:agent],
          expected_output: options[:expected_output],
          async: options[:async]
        )
        puts "Task '#{name}' created"
        puts "Description: #{options[:description]}"
        puts "Expected Output: #{options[:expected_output] || 'Not specified'}"
        puts "Assigned to: #{options[:agent] || 'No agent assigned'}"
        puts "Async: #{options[:async]}"
      end

      desc "list", "List all tasks"
      def list
        puts "Available tasks:"
        puts "  - research_topic (Agent: researcher)"
        puts "  - write_article (Agent: writer)"
        puts "  - analyze_data (Agent: analyst)"
      end
    end
  end

  class TaskExecutionError < Error; end
  class TaskDependencyError < TaskExecutionError; end
end