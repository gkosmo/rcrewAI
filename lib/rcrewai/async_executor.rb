# frozen_string_literal: true

require 'concurrent'
require 'logger'

module RCrewAI
  class AsyncExecutor
    attr_reader :thread_pool, :logger, :max_concurrency

    def initialize(**options)
      @max_concurrency = options.fetch(:max_concurrency, Concurrent.processor_count)
      @timeout = options.fetch(:timeout, 300) # 5 minutes default
      @logger = Logger.new($stdout)
      @logger.level = options.fetch(:verbose, false) ? Logger::DEBUG : Logger::INFO
      
      # Create thread pool for task execution
      @thread_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: @max_concurrency,
        max_queue: @max_concurrency * 2,
        fallback_policy: :caller_runs
      )
      
      @futures = {}
      @task_dependencies = {}
      @completed_tasks = Concurrent::Set.new
      @failed_tasks = Concurrent::Set.new
    end

    def execute_tasks_async(tasks, dependency_graph = {})
      @logger.info "Starting async execution of #{tasks.length} tasks with max #{@max_concurrency} concurrent threads"
      
      @task_dependencies = dependency_graph
      execution_phases = organize_tasks_by_dependencies(tasks)
      
      start_time = Time.now
      results = []
      
      execution_phases.each_with_index do |phase_tasks, phase_index|
        @logger.info "Executing phase #{phase_index + 1}: #{phase_tasks.length} tasks"
        
        phase_results = execute_phase_concurrently(phase_tasks, phase_index + 1)
        results.concat(phase_results)
        
        # Check if we should continue
        failed_in_phase = phase_results.count { |r| r[:status] == :failed }
        if failed_in_phase > 0 && should_abort_after_failures?(failed_in_phase, phase_tasks.length)
          @logger.error "Aborting execution due to #{failed_in_phase} failures in phase #{phase_index + 1}"
          break
        end
      end
      
      total_time = Time.now - start_time
      @logger.info "Async execution completed in #{total_time.round(2)}s"
      
      format_async_results(results, total_time)
    end

    def execute_single_task_async(task)
      future = Concurrent::Future.execute(executor: @thread_pool) do
        execute_task_with_monitoring(task)
      end
      
      @futures[task] = future
      future
    end

    def wait_for_completion(futures, timeout = nil)
      timeout ||= @timeout
      
      results = []
      futures.each do |task, future|
        begin
          result = future.value(timeout)
          results << { task: task, result: result, status: :completed }
        rescue Concurrent::TimeoutError
          @logger.error "Task #{task.name} timed out after #{timeout}s"
          results << { task: task, result: "Task timed out", status: :timeout }
        rescue => e
          @logger.error "Task #{task.name} failed: #{e.message}"
          results << { task: task, result: e.message, status: :failed }
        end
      end
      
      results
    end

    def shutdown
      @logger.info "Shutting down async executor..."
      @thread_pool.shutdown
      unless @thread_pool.wait_for_termination(30)
        @logger.warn "Thread pool did not shut down gracefully, forcing shutdown"
        @thread_pool.kill
      end
    end

    def stats
      {
        max_concurrency: @max_concurrency,
        active_threads: @thread_pool.length,
        queue_length: @thread_pool.queue_length,
        completed_task_count: @completed_tasks.size,
        failed_task_count: @failed_tasks.size,
        pool_shutdown: @thread_pool.shutdown?
      }
    end

    private

    def organize_tasks_by_dependencies(tasks)
      phases = []
      remaining_tasks = tasks.dup
      completed_task_names = Set.new

      while remaining_tasks.any?
        # Find tasks with no unmet dependencies
        ready_tasks = remaining_tasks.select do |task|
          dependencies = @task_dependencies[task] || task.context || []
          dependencies.all? { |dep| completed_task_names.include?(dep.name) }
        end

        if ready_tasks.empty?
          # Handle circular dependencies by running remaining tasks in parallel
          @logger.warn "Circular dependency detected, executing remaining #{remaining_tasks.length} tasks in parallel"
          phases << remaining_tasks
          break
        end

        phases << ready_tasks
        remaining_tasks -= ready_tasks
        ready_tasks.each { |task| completed_task_names.add(task.name) }
      end

      phases
    end

    def execute_phase_concurrently(phase_tasks, phase_number)
      @logger.debug "Phase #{phase_number}: Launching #{phase_tasks.length} concurrent tasks"
      
      # Launch all tasks in this phase concurrently
      phase_futures = {}
      phase_tasks.each do |task|
        future = execute_single_task_async(task)
        phase_futures[task] = future
      end

      # Wait for all tasks in this phase to complete
      phase_results = wait_for_completion(phase_futures)
      
      # Update tracking sets
      phase_results.each do |result|
        case result[:status]
        when :completed
          @completed_tasks.add(result[:task])
        when :failed, :timeout
          @failed_tasks.add(result[:task])
        end
      end
      
      @logger.info "Phase #{phase_number} completed: #{phase_results.count { |r| r[:status] == :completed }}/#{phase_tasks.length} successful"
      
      phase_results.map { |r| r.merge(phase: phase_number) }
    end

    def execute_task_with_monitoring(task)
      thread_id = Thread.current.object_id
      @logger.debug "Task #{task.name} starting on thread #{thread_id}"
      
      start_time = Time.now
      
      begin
        # Add async context to task
        task.instance_variable_set(:@async_execution, true)
        task.instance_variable_set(:@thread_id, thread_id)
        
        # Execute the task
        result = task.execute
        
        execution_time = Time.now - start_time
        @logger.debug "Task #{task.name} completed in #{execution_time.round(2)}s on thread #{thread_id}"
        
        result
      rescue => e
        execution_time = Time.now - start_time
        @logger.error "Task #{task.name} failed after #{execution_time.round(2)}s on thread #{thread_id}: #{e.message}"
        raise e
      end
    end

    def should_abort_after_failures?(failed_count, total_count)
      failure_rate = failed_count.to_f / total_count
      
      # Abort if more than 50% of tasks in a phase fail
      failure_rate > 0.5
    end

    def format_async_results(results, total_time)
      completed = results.count { |r| r[:status] == :completed }
      failed = results.count { |r| r[:status] == :failed }
      timed_out = results.count { |r| r[:status] == :timeout }
      
      {
        execution_mode: :async,
        total_time: total_time,
        max_concurrency: @max_concurrency,
        total_tasks: results.length,
        completed_tasks: completed,
        failed_tasks: failed,
        timed_out_tasks: timed_out,
        success_rate: (completed.to_f / results.length * 100).round(1),
        results: results,
        thread_pool_stats: {
          max_threads: @thread_pool.max_length,
          current_threads: @thread_pool.length,
          largest_length: @thread_pool.largest_length
        }
      }
    end
  end

  # Extensions to existing classes for async support
  module AsyncExtensions
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def execute_async(tasks, **options)
        executor = AsyncExecutor.new(**options)
        
        begin
          results = executor.execute_tasks_async(tasks)
          results
        ensure
          executor.shutdown
        end
      end
    end

    def async_execution?
      @async_execution || false
    end

    def thread_id
      @thread_id
    end
  end
end