---
layout: api
title: RCrewAI::Crew
description: API documentation for the Crew class
---

# RCrewAI::Crew

The Crew class is the main orchestrator in RCrewAI. It manages a collection of agents and tasks, coordinating their execution to achieve complex goals.

## Class Methods

### `.new(name)`

Creates a new crew instance.

**Parameters:**
- `name` (String) - The name of the crew

**Returns:** `RCrewAI::Crew` instance

**Example:**
```ruby
crew = RCrewAI::Crew.new("research_team")
```

### `.create(name)`

Creates and saves a new crew.

**Parameters:**
- `name` (String) - The name of the crew

**Returns:** `RCrewAI::Crew` instance

**Example:**
```ruby
crew = RCrewAI::Crew.create("marketing_crew")
```

### `.load(name)`

Loads an existing crew from storage.

**Parameters:**
- `name` (String) - The name of the crew to load

**Returns:** `RCrewAI::Crew` instance

**Example:**
```ruby
crew = RCrewAI::Crew.load("existing_crew")
```

### `.list`

Lists all available crews.

**Returns:** Array of crew names

**Example:**
```ruby
crews = RCrewAI::Crew.list
# => ["research_crew", "marketing_crew", "development_crew"]
```

## Instance Methods

### `#add_agent(agent)`

Adds an agent to the crew.

**Parameters:**
- `agent` (RCrewAI::Agent) - The agent to add

**Returns:** `self`

**Example:**
```ruby
researcher = RCrewAI::Agent.new(name: "researcher", role: "Research Analyst", goal: "Find information")
crew.add_agent(researcher)
```

### `#add_task(task)`

Adds a task to the crew's workflow.

**Parameters:**
- `task` (RCrewAI::Task) - The task to add

**Returns:** `self`

**Example:**
```ruby
task = RCrewAI::Task.new(name: "research", description: "Research AI trends", agent: researcher)
crew.add_task(task)
```

### `#execute`

Executes all tasks in the crew's workflow.

**Returns:** Hash with execution results

**Example:**
```ruby
results = crew.execute
puts results[:status]  # => "completed"
puts results[:tasks]   # => Array of task results
```

### `#execute_async`

Executes tasks asynchronously.

**Returns:** Future object with execution results

**Example:**
```ruby
future = crew.execute_async
# Do other work...
results = future.value  # Block until complete
```

### `#save`

Saves the crew configuration to storage.

**Returns:** Boolean indicating success

**Example:**
```ruby
if crew.save
  puts "Crew saved successfully"
end
```

### `#agents`

Returns all agents in the crew.

**Returns:** Array of `RCrewAI::Agent` instances

**Example:**
```ruby
crew.agents.each do |agent|
  puts "Agent: #{agent.name} - Role: #{agent.role}"
end
```

### `#tasks`

Returns all tasks in the crew's workflow.

**Returns:** Array of `RCrewAI::Task` instances

**Example:**
```ruby
crew.tasks.each do |task|
  puts "Task: #{task.name} - Assigned to: #{task.agent.name}"
end
```

### `#clear_agents`

Removes all agents from the crew.

**Returns:** `self`

**Example:**
```ruby
crew.clear_agents
```

### `#clear_tasks`

Removes all tasks from the crew's workflow.

**Returns:** `self`

**Example:**
```ruby
crew.clear_tasks
```

## Attributes

### `name` (readonly)

The name of the crew.

**Type:** String

**Example:**
```ruby
puts crew.name  # => "research_team"
```

### `process`

The execution process type for the crew.

**Type:** Symbol (`:sequential`, `:hierarchical`, `:consensual`)

**Default:** `:sequential`

**Example:**
```ruby
crew.process = :hierarchical
```

### `verbose`

Whether to output detailed execution logs.

**Type:** Boolean

**Default:** `false`

**Example:**
```ruby
crew.verbose = true
```

### `max_iterations`

Maximum number of iterations for task execution.

**Type:** Integer

**Default:** `10`

**Example:**
```ruby
crew.max_iterations = 20
```

## Configuration Options

Crews can be configured with various options:

```ruby
crew = RCrewAI::Crew.new("advanced_crew") do |c|
  c.process = :hierarchical
  c.verbose = true
  c.max_iterations = 15
  c.memory = true  # Enable memory between tasks
  c.cache = true   # Enable result caching
end
```

## Events

Crews emit events during execution that can be hooked into:

```ruby
crew.on(:task_started) do |task|
  puts "Starting task: #{task.name}"
end

crew.on(:task_completed) do |task, result|
  puts "Completed task: #{task.name}"
  puts "Result: #{result}"
end

crew.on(:execution_complete) do |results|
  puts "All tasks completed!"
end
```

## Error Handling

```ruby
begin
  results = crew.execute
rescue RCrewAI::ExecutionError => e
  puts "Execution failed: #{e.message}"
  puts "Failed task: #{e.task.name}"
rescue RCrewAI::ConfigurationError => e
  puts "Configuration error: #{e.message}"
end
```

## Examples

### Basic Crew Setup

```ruby
# Create a crew
crew = RCrewAI::Crew.new("content_team")

# Add agents
writer = RCrewAI::Agent.new(
  name: "writer",
  role: "Content Writer",
  goal: "Write engaging content"
)
editor = RCrewAI::Agent.new(
  name: "editor",
  role: "Content Editor",
  goal: "Ensure content quality"
)

crew.add_agent(writer)
crew.add_agent(editor)

# Add tasks
writing_task = RCrewAI::Task.new(
  name: "write_article",
  description: "Write an article about Ruby",
  agent: writer
)
editing_task = RCrewAI::Task.new(
  name: "edit_article",
  description: "Edit and polish the article",
  agent: editor,
  context: [writing_task]
)

crew.add_task(writing_task)
crew.add_task(editing_task)

# Execute
results = crew.execute
```

### Hierarchical Process

```ruby
crew = RCrewAI::Crew.new("management_team")
crew.process = :hierarchical

# Add a manager agent
manager = RCrewAI::Agent.new(
  name: "manager",
  role: "Project Manager",
  goal: "Coordinate team efforts",
  allow_delegation: true
)

crew.add_agent(manager)
# Add other agents...

crew.execute
```