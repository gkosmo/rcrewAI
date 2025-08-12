# frozen_string_literal: true

module RCrewAI
  module Process
    class Base
      attr_reader :crew, :logger

      def initialize(crew)
        @crew = crew
        @logger = Logger.new($stdout)
        @logger.level = crew.verbose ? Logger::DEBUG : Logger::INFO
      end

      def execute
        raise NotImplementedError, "Subclasses must implement #execute method"
      end

      protected

      def log_execution_start
        @logger.info "Starting #{self.class.name.split('::').last.downcase} process execution"
        @logger.info "Crew: #{crew.name} with #{crew.agents.length} agents, #{crew.tasks.length} tasks"
      end

      def log_execution_end(results)
        completed_tasks = results.count { |r| r[:status] == :completed }
        @logger.info "Process execution completed: #{completed_tasks}/#{crew.tasks.length} tasks successful"
      end
    end

    class Sequential < Base
      def execute
        log_execution_start
        results = []

        crew.tasks.each do |task|
          @logger.info "Executing task: #{task.name}"
          begin
            result = task.execute
            results << { task: task, result: result, status: :completed }
          rescue => e
            @logger.error "Task #{task.name} failed: #{e.message}"
            results << { task: task, result: e.message, status: :failed }
          end
        end

        log_execution_end(results)
        results
      end
    end

    class Hierarchical < Base
      attr_reader :manager_agent, :hierarchy

      def initialize(crew)
        super
        @manager_agent = find_or_create_manager
        @hierarchy = build_hierarchy
        validate_hierarchy!
      end

      def execute
        log_execution_start
        @logger.info "Hierarchical execution with manager: #{manager_agent.name}"

        # Manager coordinates all execution
        execution_plan = create_execution_plan
        results = execute_with_manager(execution_plan)

        log_execution_end(results)
        results
      end

      private

      def find_or_create_manager
        # Look for an agent marked as manager
        manager = crew.agents.find { |agent| agent.is_manager? }
        
        # If no explicit manager, find agent with delegation capabilities
        manager ||= crew.agents.find { |agent| agent.allow_delegation }
        
        # Create a default manager if none found
        if manager.nil?
          @logger.warn "No manager agent found, creating default manager"
          manager = create_default_manager
          crew.add_agent(manager)
        end

        manager
      end

      def create_default_manager
        RCrewAI::Agent.new(
          name: "crew_manager",
          role: "Crew Manager",
          goal: "Coordinate team efforts and delegate tasks effectively",
          backstory: "You are an experienced project manager who coordinates team efforts, delegates tasks appropriately, and ensures deliverables meet requirements.",
          allow_delegation: true,
          manager: true,
          verbose: crew.verbose
        )
      end

      def build_hierarchy
        hierarchy = {
          manager: manager_agent,
          subordinates: crew.agents.reject { |agent| agent == manager_agent },
          task_assignments: {},
          delegation_chains: []
        }

        # Assign tasks to appropriate agents
        crew.tasks.each do |task|
          if task.agent && task.agent != manager_agent
            hierarchy[:task_assignments][task] = task.agent
          else
            # Manager will delegate this task
            best_agent = find_best_agent_for_task(task, hierarchy[:subordinates])
            hierarchy[:task_assignments][task] = best_agent
          end
        end

        hierarchy
      end

      def find_best_agent_for_task(task, available_agents)
        # Simple heuristic: match task keywords with agent role/goal
        task_keywords = extract_keywords(task.description.downcase)
        
        best_agent = available_agents.max_by do |agent|
          agent_keywords = extract_keywords("#{agent.role} #{agent.goal}".downcase)
          common_keywords = (task_keywords & agent_keywords).length
          # Boost score for agents with relevant tools
          tool_bonus = agent.tools.any? ? 0.5 : 0
          common_keywords + tool_bonus
        end

        best_agent || available_agents.first
      end

      def extract_keywords(text)
        stopwords = %w[the a an and or but in on at to for of with by is are was were be been being have has had do does did will would could should]
        text.split(/\W+/).reject { |w| w.length < 3 || stopwords.include?(w) }
      end

      def validate_hierarchy!
        raise ProcessError, "No manager agent available" unless manager_agent
        raise ProcessError, "No subordinate agents available" if hierarchy[:subordinates].empty?
        raise ProcessError, "No tasks to execute" if crew.tasks.empty?
      end

      def create_execution_plan
        plan = {
          phases: [],
          total_tasks: crew.tasks.length,
          dependencies: build_dependency_graph
        }

        # Group tasks by dependencies
        phases = organize_tasks_by_dependencies
        plan[:phases] = phases

        @logger.debug "Execution plan: #{phases.length} phases"
        phases.each_with_index do |phase, i|
          @logger.debug "  Phase #{i + 1}: #{phase.map(&:name).join(', ')}"
        end

        plan
      end

      def build_dependency_graph
        graph = {}
        crew.tasks.each do |task|
          graph[task] = task.context || []
        end
        graph
      end

      def organize_tasks_by_dependencies
        phases = []
        remaining_tasks = crew.tasks.dup
        completed_tasks = Set.new

        while remaining_tasks.any?
          # Find tasks with no unmet dependencies
          ready_tasks = remaining_tasks.select do |task|
            dependencies = task.context || []
            dependencies.all? { |dep| completed_tasks.include?(dep) }
          end

          if ready_tasks.empty?
            # Circular dependency or other issue
            @logger.warn "Circular dependency detected, executing remaining tasks in order"
            phases << remaining_tasks
            break
          end

          phases << ready_tasks
          remaining_tasks -= ready_tasks
          completed_tasks.merge(ready_tasks)
        end

        phases
      end

      def execute_with_manager(plan)
        results = []
        
        plan[:phases].each_with_index do |phase_tasks, phase_index|
          @logger.info "Executing phase #{phase_index + 1}: #{phase_tasks.length} tasks"
          
          # Manager delegates tasks in this phase
          phase_results = execute_phase(phase_tasks, phase_index + 1)
          results.concat(phase_results)
          
          # Check if we should continue to next phase
          if phase_results.any? { |r| r[:status] == :failed }
            failed_tasks = phase_results.select { |r| r[:status] == :failed }
            @logger.warn "Phase #{phase_index + 1} had #{failed_tasks.length} failures"
            
            # Manager decides whether to continue
            if should_abort_execution?(failed_tasks, phase_index + 1, plan)
              @logger.error "Manager decided to abort execution due to critical failures"
              break
            end
          end
        end

        results
      end

      def execute_phase(tasks, phase_number)
        phase_results = []
        
        # Manager creates delegation plan for this phase
        delegation_plan = create_delegation_plan(tasks, phase_number)
        
        # Execute delegated tasks
        tasks.each do |task|
          assigned_agent = hierarchy[:task_assignments][task]
          
          @logger.info "Manager delegating '#{task.name}' to #{assigned_agent.name}"
          
          begin
            # Manager provides delegation context
            delegation_context = create_delegation_context(task, assigned_agent, delegation_plan)
            
            # Execute task with delegation
            result = execute_delegated_task(task, assigned_agent, delegation_context)
            
            phase_results << { 
              task: task, 
              result: result, 
              status: :completed,
              assigned_agent: assigned_agent,
              phase: phase_number
            }
            
            @logger.info "Task '#{task.name}' completed successfully"
            
          rescue => e
            @logger.error "Delegated task '#{task.name}' failed: #{e.message}"
            
            phase_results << { 
              task: task, 
              result: e.message, 
              status: :failed,
              assigned_agent: assigned_agent,
              phase: phase_number,
              error: e
            }
          end
        end
        
        phase_results
      end

      def create_delegation_plan(tasks, phase_number)
        {
          phase: phase_number,
          tasks: tasks.map(&:name),
          priorities: assign_task_priorities(tasks),
          coordination_notes: generate_coordination_notes(tasks)
        }
      end

      def assign_task_priorities(tasks)
        # Simple priority assignment based on dependencies and complexity
        priorities = {}
        
        tasks.each do |task|
          priority = :normal
          
          # High priority if other tasks depend on this one
          if crew.tasks.any? { |t| t.context&.include?(task) }
            priority = :high
          end
          
          # Low priority if task is optional or has many dependencies
          if task.context&.length.to_i > 2
            priority = :low
          end
          
          priorities[task] = priority
        end
        
        priorities
      end

      def generate_coordination_notes(tasks)
        notes = []
        
        if tasks.length > 1
          notes << "Multiple tasks in this phase - coordinate timing if needed"
        end
        
        if tasks.any? { |t| t.context&.any? }
          notes << "Some tasks depend on previous results - ensure context is available"
        end
        
        if tasks.any? { |t| t.tools&.any? }
          notes << "Tasks require external tools - monitor for failures"
        end
        
        notes.join(". ") + "."
      end

      def create_delegation_context(task, assigned_agent, delegation_plan)
        {
          delegation_source: "Manager: #{manager_agent.name}",
          assignment_reason: generate_assignment_reason(task, assigned_agent),
          phase_context: delegation_plan,
          expectations: generate_task_expectations(task),
          escalation_notes: "Contact manager if issues arise or guidance needed"
        }
      end

      def generate_assignment_reason(task, agent)
        "Assigned to #{agent.name} based on role '#{agent.role}' and expertise alignment with task requirements"
      end

      def generate_task_expectations(task)
        expectations = []
        expectations << "Expected output: #{task.expected_output}" if task.expected_output
        expectations << "Quality: Professional and thorough"
        expectations << "Communication: Report progress and any blockers"
        expectations.join(". ") + "."
      end

      def execute_delegated_task(task, agent, delegation_context)
        # Enhance task with delegation context
        enhanced_task = task.dup
        enhanced_task.instance_variable_set(:@delegation_context, delegation_context)
        
        # Define method to access delegation context
        def enhanced_task.delegation_context
          @delegation_context
        end
        
        # Execute the task
        agent.execute_task(enhanced_task)
      end

      def should_abort_execution?(failed_tasks, phase_number, plan)
        # Abort if more than 50% of critical tasks failed
        critical_failures = failed_tasks.count { |r| r[:task].context&.any? || r[:task].expected_output }
        
        if critical_failures > (failed_tasks.length * 0.5)
          @logger.error "Too many critical task failures (#{critical_failures}/#{failed_tasks.length})"
          return true
        end
        
        # Abort if we're early in execution and having major issues
        if phase_number <= 2 && failed_tasks.length > 1
          @logger.error "Multiple failures in early phases indicate systemic issues"
          return true
        end
        
        false
      end
    end

    class Consensual < Base
      def execute
        log_execution_start
        @logger.info "Consensual execution - agents collaborate on decisions"
        
        # For now, implement as enhanced sequential with collaboration
        # Full consensual process would involve agent voting/discussion
        results = []
        
        crew.tasks.each do |task|
          @logger.info "Collaborative execution of task: #{task.name}"
          
          # Simple consensus: let multiple agents provide input
          consensus_result = execute_with_consensus(task)
          results << consensus_result
        end
        
        log_execution_end(results)
        results
      end
      
      private
      
      def execute_with_consensus(task)
        # For now, just execute normally
        # Future: implement actual consensus mechanisms
        begin
          result = task.execute
          { task: task, result: result, status: :completed }
        rescue => e
          { task: task, result: e.message, status: :failed }
        end
      end
    end

    class ProcessError < RCrewAI::Error; end
  end
end