# frozen_string_literal: true

require_relative 'process'
require_relative 'async_executor'

module RCrewAI
  class Crew
    include AsyncExtensions
    attr_reader :name, :agents, :tasks, :process_type
    attr_accessor :verbose, :max_iterations

    def initialize(name, **options)
      @name = name
      @agents = []
      @tasks = []
      @process_type = options.fetch(:process, :sequential)
      @verbose = options.fetch(:verbose, false)
      @max_iterations = options.fetch(:max_iterations, 10)
      @process_instance = nil
      validate_process_type!
    end

    def add_agent(agent)
      @agents << agent
    end

    def add_task(task)
      @tasks << task
    end

    def execute(async: false, **async_options)
      if async
        execute_async(**async_options)
      else
        execute_sync
      end
    end

    def execute_async(**options)
      puts "Executing crew: #{name} (async #{process_type} process)"
      
      case process_type
      when :sequential
        execute_sequential_async(**options)
      when :hierarchical
        execute_hierarchical_async(**options)
      when :consensual
        execute_consensual_async(**options)
      else
        raise ConfigurationError, "Async execution not implemented for #{process_type} process"
      end
    end

    def execute_sync
      puts "Executing crew: #{name} (#{process_type} process)"
      
      # Create appropriate process instance
      @process_instance = create_process_instance
      
      # Execute using the process
      results = @process_instance.execute
      
      # Return formatted results
      format_execution_results(results)
    end

    def process=(new_process)
      @process_type = new_process.to_sym
      validate_process_type!
      @process_instance = nil  # Reset process instance
    end

    def self.create(name)
      crew = new(name)
      crew.save
      puts "Crew '#{name}' created successfully!"
      crew
    end

    def self.load(name)
      # Load crew configuration from file
      new(name)
    end

    def self.list
      # List all available crews
      ["example_crew", "research_crew", "development_crew"]
    end

    def save
      # Save crew configuration to file
      true
    end

    private

    def validate_process_type!
      valid_processes = [:sequential, :hierarchical, :consensual]
      unless valid_processes.include?(process_type)
        raise ConfigurationError, "Invalid process type: #{process_type}. Valid types: #{valid_processes.join(', ')}"
      end
    end

    def create_process_instance
      case process_type
      when :sequential
        Process::Sequential.new(self)
      when :hierarchical
        Process::Hierarchical.new(self)
      when :consensual
        Process::Consensual.new(self)
      else
        raise ConfigurationError, "Unsupported process type: #{process_type}"
      end
    end

    def execute_sequential_async(**options)
      executor = AsyncExecutor.new(**options)
      
      begin
        dependency_graph = build_dependency_graph
        results = executor.execute_tasks_async(tasks, dependency_graph)
        
        # Add crew metadata
        results.merge(
          crew: name,
          process: :async_sequential
        )
      ensure
        executor.shutdown
      end
    end

    def execute_hierarchical_async(**options)
      # For hierarchical async, we need to coordinate through the manager
      manager_agent = find_manager_agent
      unless manager_agent
        raise Process::ProcessError, "Hierarchical async execution requires a manager agent"
      end

      puts "Manager #{manager_agent.name} coordinating async execution"
      
      executor = AsyncExecutor.new(**options)
      
      begin
        # Build execution phases respecting dependencies
        dependency_graph = build_dependency_graph
        phases = organize_tasks_into_phases(tasks, dependency_graph)
        
        results = []
        phases.each_with_index do |phase_tasks, phase_index|
          puts "Manager delegating phase #{phase_index + 1}: #{phase_tasks.length} tasks"
          
          # Create delegation contexts for each task
          phase_tasks.each do |task|
            unless task.agent
              # Manager assigns best agent for the task
              task.instance_variable_set(:@agent, find_best_agent_for_task(task))
            end
            
            # Add delegation context
            add_delegation_context(task, manager_agent)
          end
          
          # Execute phase concurrently
          phase_results = executor.execute_tasks_async(phase_tasks, {})
          results.concat(phase_results[:results])
          
          # Check if we should abort
          failed_count = phase_results[:results].count { |r| r[:status] == :failed }
          if failed_count > phase_tasks.length * 0.5
            puts "Manager aborting execution due to high failure rate in phase #{phase_index + 1}"
            break
          end
        end
        
        {
          crew: name,
          process: :async_hierarchical,
          manager: manager_agent.name,
          total_tasks: tasks.length,
          completed_tasks: results.count { |r| r[:status] == :completed },
          failed_tasks: results.count { |r| r[:status] == :failed },
          results: results,
          success_rate: results.empty? ? 0 : (results.count { |r| r[:status] == :completed }.to_f / results.length * 100).round(1)
        }
      ensure
        executor.shutdown
      end
    end

    def execute_consensual_async(**options)
      # Simplified consensual async - execute in parallel with result aggregation
      executor = AsyncExecutor.new(**options)
      
      begin
        # All tasks can potentially run in parallel for consensual
        results = executor.execute_tasks_async(tasks, {})
        
        results.merge(
          crew: name,
          process: :async_consensual
        )
      ensure
        executor.shutdown
      end
    end

    def build_dependency_graph
      graph = {}
      tasks.each do |task|
        graph[task] = task.context || []
      end
      graph
    end

    def organize_tasks_into_phases(tasks, dependency_graph)
      phases = []
      remaining_tasks = tasks.dup
      completed_task_names = Set.new

      while remaining_tasks.any?
        ready_tasks = remaining_tasks.select do |task|
          dependencies = dependency_graph[task] || []
          dependencies.all? { |dep| completed_task_names.include?(dep.name) }
        end

        if ready_tasks.empty?
          phases << remaining_tasks
          break
        end

        phases << ready_tasks
        remaining_tasks -= ready_tasks
        ready_tasks.each { |task| completed_task_names.add(task.name) }
      end

      phases
    end

    def find_manager_agent
      agents.find { |agent| agent.is_manager? } ||
      agents.find { |agent| agent.allow_delegation }
    end

    def find_best_agent_for_task(task)
      # Simple heuristic: match keywords
      task_keywords = extract_keywords(task.description.downcase)
      
      # Filter out manager agents first
      non_manager_agents = agents.reject(&:is_manager?)
      return nil if non_manager_agents.empty?
      
      best_agent = non_manager_agents.max_by do |agent|
        agent_keywords = extract_keywords("#{agent.role} #{agent.goal}".downcase)
        common_keywords = (task_keywords & agent_keywords).length
        tool_bonus = agent.tools.any? ? 0.5 : 0
        common_keywords + tool_bonus
      end

      best_agent
    end

    def extract_keywords(text)
      stopwords = %w[the a an and or but in on at to for of with by is are was were be been being have has had do does did will would could should]
      text.split(/\W+/).reject { |w| w.length < 3 || stopwords.include?(w) }
    end

    def add_delegation_context(task, manager_agent)
      delegation_context = {
        manager: manager_agent.name,
        delegation_reason: "Assigned by #{manager_agent.role} for optimal task execution",
        coordination_notes: "Part of async hierarchical execution",
        async_execution: true
      }
      
      task.instance_variable_set(:@delegation_context, delegation_context)
    end

    def format_execution_results(results)
      {
        crew: name,
        process: process_type,
        total_tasks: results.length,
        completed_tasks: results.count { |r| r[:status] == :completed },
        failed_tasks: results.count { |r| r[:status] == :failed },
        results: results,
        success_rate: results.empty? ? 0.0 : (results.count { |r| r[:status] == :completed }.to_f / results.length * 100).round(1)
      }
    end
  end
end