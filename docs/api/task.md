---
layout: api
title: RCrewAI::Task
description: API documentation for the Task class
---

# RCrewAI::Task

The Task class represents individual units of work that agents execute. Tasks define what needs to be done, expected outputs, dependencies, and execution parameters.

## Constructor

### `new(name:, description:, **options)`

Creates a new task instance.

**Required Parameters:**
- `name` (String) - Unique identifier for the task
- `description` (String) - Detailed description of what the task should accomplish

**Optional Parameters:**
- `agent` (RCrewAI::Agent) - Agent assigned to execute this task
- `expected_output` (String) - Description of expected result format/content
- `context` (Array) - Array of tasks this task depends on
- `tools` (Array) - Specific tools available for this task (in addition to agent tools)
- `callback` (Proc) - Callback function called after task completion
- `max_retries` (Integer) - Maximum retry attempts on failure (default: 3)
- `retry_delay` (Integer) - Delay between retries in seconds (default: 5)
- `timeout` (Integer) - Task execution timeout in seconds (default: 300)
- `human_input` (Boolean) - Enable human interaction for this task (default: false)
- `require_confirmation` (Boolean) - Require human confirmation before starting
- `allow_guidance` (Boolean) - Allow human guidance during execution
- `human_review_points` (Array) - Points where human review is requested ([:completion, :error])
- `async` (Boolean) - Whether task can be executed asynchronously (default: false)

**Returns:** `RCrewAI::Task` instance

**Example:**
```ruby
task = RCrewAI::Task.new(
  name: "market_research",
  description: "Research competitor landscape and pricing strategies for our new AI product",
  agent: research_agent,
  expected_output: "Comprehensive market analysis report with competitor pricing matrix and strategic recommendations",
  context: [data_collection_task],  # Depends on data collection
  tools: [RCrewAI::Tools::WebSearch.new(max_results: 15)],  # Task-specific tools
  max_retries: 2,
  timeout: 600,
  human_input: true,
  require_confirmation: true,
  callback: ->(task, result) { 
    puts "Market research completed: #{result.length} characters"
    NotificationService.notify("Research completed for #{task.name}")
  }
)
```

## Instance Methods

### `#execute`

Executes the task with the assigned agent.

**Returns:** String containing the task result

**Raises:** 
- `RCrewAI::TaskExecutionError` - If task execution fails
- `RCrewAI::TaskDependencyError` - If dependencies are not met

**Example:**
```ruby
begin
  result = task.execute
  puts "Task completed successfully: #{result[0..100]}..."
rescue RCrewAI::TaskExecutionError => e
  puts "Task failed: #{e.message}"
  puts "Retry count: #{task.retry_count}"
rescue RCrewAI::TaskDependencyError => e
  puts "Dependencies not met: #{e.message}"
end
```

### `#add_context_task(task)`

Adds a dependency task to this task's context.

**Parameters:**
- `task` (RCrewAI::Task) - Task to add as dependency

**Returns:** `self`

**Example:**
```ruby
research_task = RCrewAI::Task.new(name: "research", description: "Research topic")
analysis_task = RCrewAI::Task.new(name: "analysis", description: "Analyze research")

analysis_task.add_context_task(research_task)
# Now analysis_task will wait for research_task to complete
```

### `#add_tool(tool)`

Adds a tool specific to this task.

**Parameters:**
- `tool` (RCrewAI::Tools::Base) - Tool instance to add

**Returns:** `self`

**Example:**
```ruby
custom_api_tool = MyCustomAPITool.new(api_key: ENV['API_KEY'])
task.add_tool(custom_api_tool)
```

### `#dependencies_met?`

Checks if all dependency tasks are completed.

**Returns:** Boolean

**Example:**
```ruby
if task.dependencies_met?
  result = task.execute
else
  puts "Waiting for dependencies: #{task.pending_dependencies.map(&:name)}"
end
```

### `#context_data`

Returns formatted context data from dependency tasks.

**Returns:** String containing context from completed dependency tasks

**Example:**
```ruby
puts task.context_data
# Output includes results from all completed context tasks
```

### `#enable_human_input(**options)`

Enables human interaction for this task.

**Parameters:**
- `require_confirmation` (Boolean) - Require confirmation before starting
- `allow_guidance` (Boolean) - Allow guidance during execution
- `human_review_points` (Array) - Review points ([:completion, :error, :midpoint])

**Returns:** `self`

**Example:**
```ruby
task.enable_human_input(
  require_confirmation: true,
  allow_guidance: true,
  human_review_points: [:completion, :error]
)
```

### `#disable_human_input`

Disables human interaction for this task.

**Returns:** `self`

## Attributes

### `name` (readonly)
The task's unique name.

**Type:** String

### `description` (readonly)
Detailed description of the task.

**Type:** String

### `expected_output` (readonly)
Description of expected output format/content.

**Type:** String

### `agent`
The agent assigned to execute this task.

**Type:** RCrewAI::Agent

### `context`
Array of dependency tasks.

**Type:** Array<RCrewAI::Task>

### `tools`
Task-specific tools (in addition to agent tools).

**Type:** Array

### `status`
Current execution status.

**Type:** Symbol (`:pending`, `:running`, `:completed`, `:failed`)

### `result`
The task execution result.

**Type:** String

### `start_time`
When task execution started.

**Type:** Time

### `end_time`
When task execution completed.

**Type:** Time

### `execution_time`
Total execution time in seconds.

**Type:** Float

### `retry_count`
Number of retry attempts made.

**Type:** Integer

### `error_message`
Error message if task failed.

**Type:** String

### `human_input`
Whether human input is enabled.

**Type:** Boolean

### `async`
Whether task supports async execution.

**Type:** Boolean

## Task States and Lifecycle

Tasks progress through several states:

1. **`:pending`** - Initial state, waiting to be executed
2. **`:running`** - Currently being executed by an agent  
3. **`:completed`** - Successfully completed with result
4. **`:failed`** - Failed after all retry attempts

```ruby
# Check task status
case task.status
when :pending
  puts "Task is waiting to be executed"
when :running
  puts "Task is currently being executed"
when :completed
  puts "Task completed successfully"
  puts "Result: #{task.result}"
  puts "Execution time: #{task.execution_time}s"
when :failed
  puts "Task failed: #{task.error_message}"
  puts "Retry attempts: #{task.retry_count}"
end
```

## Task Dependencies

Tasks can depend on other tasks, creating execution order:

```ruby
# Create task chain
data_collection = RCrewAI::Task.new(
  name: "collect_data",
  description: "Collect raw data from various sources",
  agent: data_collector
)

data_processing = RCrewAI::Task.new(
  name: "process_data", 
  description: "Clean and process collected data",
  agent: data_processor,
  context: [data_collection]  # Depends on data collection
)

analysis = RCrewAI::Task.new(
  name: "analyze_data",
  description: "Analyze processed data for insights", 
  agent: data_analyst,
  context: [data_processing]  # Depends on data processing
)

report_generation = RCrewAI::Task.new(
  name: "generate_report",
  description: "Generate final report with visualizations",
  agent: report_generator,
  context: [analysis]  # Depends on analysis
)

# Tasks will execute in dependency order:
# data_collection → data_processing → analysis → report_generation
```

## Task-Specific Tools

Tasks can have their own tools in addition to agent tools:

```ruby
# Task with specialized tools
api_integration_task = RCrewAI::Task.new(
  name: "integrate_api",
  description: "Integrate with external API and process data",
  agent: integration_agent,
  tools: [
    CustomAPIClient.new(base_url: ENV['API_URL'], api_key: ENV['API_KEY']),
    DataValidator.new(schema_path: './schemas/api_response.json'),
    RCrewAI::Tools::FileWriter.new(allowed_extensions: ['.json', '.csv'])
  ]
)

# Agent will have access to both its own tools and task-specific tools
```

## Human-in-the-Loop Tasks

Tasks can integrate human oversight at various points:

```ruby
critical_task = RCrewAI::Task.new(
  name: "deploy_model",
  description: "Deploy ML model to production environment",
  agent: deployment_agent,
  human_input: true,
  require_confirmation: true,  # Human must approve before starting
  allow_guidance: true,        # Human can provide guidance during execution
  human_review_points: [:completion],  # Human reviews final result
  callback: ->(task, result) {
    if result.include?("DEPLOYED SUCCESSFULLY")
      SlackNotifier.notify("🚀 Model deployed successfully!")
    end
  }
)

# Execution flow with human interaction:
# 1. Human confirms task start
# 2. Agent begins deployment process
# 3. Human provides guidance if needed
# 4. Human reviews deployment result
# 5. Callback notifies team of success
```

## Async Task Execution

Tasks can be marked for asynchronous execution:

```ruby
# Tasks that can run in parallel
parallel_tasks = [
  RCrewAI::Task.new(
    name: "market_research",
    description: "Research market trends",
    agent: researcher,
    async: true  # Can run concurrently
  ),
  
  RCrewAI::Task.new(
    name: "competitor_analysis", 
    description: "Analyze competitor strategies",
    agent: analyst,
    async: true  # Can run concurrently
  ),
  
  RCrewAI::Task.new(
    name: "technical_review",
    description: "Review technical specifications",
    agent: tech_reviewer,
    async: true  # Can run concurrently
  )
]

# These tasks can execute simultaneously
crew.add_task(parallel_tasks)
results = crew.execute(async: true, max_concurrency: 3)
```

## Task Callbacks and Events

Tasks can execute callbacks at various lifecycle events:

```ruby
task = RCrewAI::Task.new(
  name: "data_analysis",
  description: "Analyze customer data for insights",
  agent: analyst,
  
  # Callbacks for different events
  on_start: ->(task) {
    puts "Starting analysis: #{task.name}"
    MetricsTracker.task_started(task.name)
  },
  
  on_progress: ->(task, progress) {
    puts "Progress: #{progress}% complete"
    ProgressBar.update(task.name, progress)
  },
  
  on_completion: ->(task, result) {
    puts "Analysis completed: #{result.length} chars"
    ResultStore.save(task.name, result)
    EmailNotifier.send_completion_notice(task.name)
  },
  
  on_error: ->(task, error) {
    puts "Task failed: #{error.message}"
    ErrorTracker.log_error(task.name, error)
    AlertSystem.notify_failure(task.name)
  }
)
```

## Retry Logic and Error Handling

Tasks have built-in retry capabilities:

```ruby
resilient_task = RCrewAI::Task.new(
  name: "api_data_sync",
  description: "Sync data with external API",
  agent: sync_agent,
  max_retries: 5,           # Try up to 5 times
  retry_delay: 10,          # Wait 10 seconds between retries
  timeout: 120,             # Timeout after 2 minutes
  
  # Custom retry logic
  retry_if: ->(error) {
    # Retry on network errors, but not on authentication errors
    error.is_a?(Net::TimeoutError) || error.is_a?(Net::ReadTimeout)
  }
)

# Task will automatically retry on transient failures
result = resilient_task.execute
```

## Task Monitoring and Metrics

```ruby
# Task execution with monitoring
task = RCrewAI::Task.new(
  name: "report_generation",
  description: "Generate monthly performance report", 
  agent: report_agent,
  
  # Built-in metrics
  track_metrics: true,
  
  # Custom monitoring
  callback: ->(task, result) {
    # Record performance metrics
    TaskMetrics.record(
      task_name: task.name,
      execution_time: task.execution_time,
      result_size: result.length,
      agent_name: task.agent.name,
      success: task.status == :completed
    )
  }
)

# After execution
puts "Task metrics:"
puts "- Execution time: #{task.execution_time}s"
puts "- Retry attempts: #{task.retry_count}"
puts "- Result size: #{task.result.length} characters"
puts "- Agent used: #{task.agent.name}"
```

## Best Practices

1. **Clear Descriptions**: Write detailed, specific task descriptions
2. **Expected Outputs**: Define what the result should look like
3. **Proper Dependencies**: Use context to establish task execution order
4. **Appropriate Tools**: Provide task-specific tools when needed
5. **Human Oversight**: Enable human input for critical tasks
6. **Error Handling**: Set appropriate retry limits and timeouts
7. **Async Where Possible**: Mark independent tasks as async for performance
8. **Monitoring**: Use callbacks to track task performance and results
9. **Resource Limits**: Set reasonable timeouts to prevent hanging
10. **Result Validation**: Validate task outputs match expected format