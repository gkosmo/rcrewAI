---
layout: api
title: RCrewAI::Agent
description: API documentation for the Agent class
---

# RCrewAI::Agent

The Agent class represents an individual AI agent with specific roles, capabilities, and tools. Agents are the core workers in RCrewAI that execute tasks using reasoning loops and specialized tools.

## Constructor

### `new(name:, role:, goal:, **options)`

Creates a new agent instance.

**Parameters:**
- `name` (String, required) - Unique identifier for the agent
- `role` (String, required) - The agent's role (e.g., "Research Analyst", "Content Writer")
- `goal` (String, required) - The agent's primary objective
- `backstory` (String, optional) - Background context that influences behavior
- `tools` (Array, optional) - Array of tool instances available to the agent
- `verbose` (Boolean, optional) - Enable detailed logging (default: false)
- `allow_delegation` (Boolean, optional) - Allow agent to delegate tasks (default: false)
- `manager` (Boolean, optional) - Designate as manager agent (default: false)
- `max_iterations` (Integer, optional) - Maximum reasoning iterations (default: 10)
- `max_execution_time` (Integer, optional) - Maximum execution time in seconds (default: 300)
- `human_input` (Boolean, optional) - Enable human-in-the-loop interactions (default: false)
- `require_approval_for_tools` (Boolean, optional) - Require human approval for tool usage
- `require_approval_for_final_answer` (Boolean, optional) - Require human approval for final results

**Returns:** `RCrewAI::Agent` instance

**Example:**
```ruby
agent = RCrewAI::Agent.new(
  name: "research_specialist",
  role: "Senior Research Analyst",
  goal: "Uncover cutting-edge developments in AI and technology",
  backstory: "You work at a leading tech think tank with 10+ years experience in emerging technology analysis.",
  tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileWriter.new],
  verbose: true,
  max_iterations: 15,
  max_execution_time: 600
)
```

## Instance Methods

### `#execute_task(task)`

Executes a given task using the agent's reasoning capabilities.

**Parameters:**
- `task` (RCrewAI::Task) - The task to execute

**Returns:** String containing the task result

**Example:**
```ruby
task = RCrewAI::Task.new(
  name: "analyze_trends",
  description: "Analyze current AI trends",
  agent: agent
)

result = agent.execute_task(task)
puts result
```

### `#use_tool(tool_name, **params)`

Uses a specific tool with the given parameters.

**Parameters:**
- `tool_name` (String) - Name of the tool to use
- `**params` - Parameters to pass to the tool

**Returns:** String containing the tool's result

**Example:**
```ruby
result = agent.use_tool("websearch", query: "latest AI developments", max_results: 5)
puts result
```

### `#available_tools_description`

Returns a description of all available tools.

**Returns:** String describing available tools

**Example:**
```ruby
puts agent.available_tools_description
# Output: "- websearch: Search the web for information\n- filewriter: Write content to files"
```

### `#enable_human_input(**options)`

Enables human-in-the-loop functionality for the agent.

**Parameters:**
- `require_approval_for_tools` (Boolean, optional) - Require approval for tool usage
- `require_approval_for_final_answer` (Boolean, optional) - Require approval for results

**Returns:** `self`

**Example:**
```ruby
agent.enable_human_input(
  require_approval_for_tools: true,
  require_approval_for_final_answer: true
)
```

### `#disable_human_input`

Disables human-in-the-loop functionality.

**Returns:** `self`

**Example:**
```ruby
agent.disable_human_input
```

### `#human_input_enabled?`

Checks if human input is enabled.

**Returns:** Boolean

**Example:**
```ruby
if agent.human_input_enabled?
  puts "Human input is enabled"
end
```

### `#is_manager?`

Checks if the agent is designated as a manager.

**Returns:** Boolean

**Example:**
```ruby
if agent.is_manager?
  puts "This is a manager agent"
end
```

### `#add_subordinate(agent)`

Adds a subordinate agent (only for manager agents).

**Parameters:**
- `agent` (RCrewAI::Agent) - Agent to add as subordinate

**Returns:** `self`

**Example:**
```ruby
manager = RCrewAI::Agent.new(name: "manager", role: "Team Lead", goal: "Coordinate team", manager: true)
specialist = RCrewAI::Agent.new(name: "specialist", role: "Specialist", goal: "Execute tasks")

manager.add_subordinate(specialist)
```

### `#subordinates`

Returns all subordinate agents.

**Returns:** Array of `RCrewAI::Agent` instances

**Example:**
```ruby
manager.subordinates.each do |subordinate|
  puts "Subordinate: #{subordinate.name}"
end
```

### `#delegate_task(task, target_agent)`

Delegates a task to another agent (manager functionality).

**Parameters:**
- `task` (RCrewAI::Task) - Task to delegate
- `target_agent` (RCrewAI::Agent) - Agent to receive the task

**Returns:** Task result

**Example:**
```ruby
task = RCrewAI::Task.new(name: "analysis", description: "Analyze data", agent: manager)
result = manager.delegate_task(task, data_analyst)
```

## Attributes

### `name` (readonly)
The agent's unique name.

**Type:** String

### `role` (readonly)
The agent's role description.

**Type:** String

### `goal` (readonly)
The agent's primary objective.

**Type:** String

### `backstory` (readonly)
The agent's background context.

**Type:** String

### `tools` (readonly)
Array of available tools.

**Type:** Array

### `memory`
The agent's memory system for learning.

**Type:** RCrewAI::Memory

### `llm_client`
The LLM client used for reasoning.

**Type:** RCrewAI::LLMClient

### `verbose`
Controls detailed logging.

**Type:** Boolean

### `allow_delegation`
Whether agent can delegate tasks.

**Type:** Boolean

### `max_iterations`
Maximum reasoning iterations allowed.

**Type:** Integer

### `max_execution_time`
Maximum execution time in seconds.

**Type:** Integer

## Agent Reasoning Process

Agents follow a sophisticated reasoning loop:

1. **Context Building**: Gather task context, agent background, available tools
2. **Reasoning Loop**: 
   - Generate reasoning about the current situation
   - Decide on actions (tool usage, delegation, completion)
   - Execute chosen actions
   - Evaluate results and continue or finish
3. **Result Generation**: Produce final answer based on reasoning and actions
4. **Memory Storage**: Store successful patterns and learnings

## Manager Agent Capabilities

Manager agents have additional capabilities:

```ruby
# Create manager agent
manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Project Manager",
  goal: "Coordinate team execution efficiently",
  manager: true,
  allow_delegation: true
)

# Add team members
manager.add_subordinate(researcher)
manager.add_subordinate(writer)
manager.add_subordinate(analyst)

# Manager automatically coordinates task delegation
```

## Human-in-the-Loop Features

Agents can work collaboratively with humans:

```ruby
# Enable human collaboration
agent = RCrewAI::Agent.new(
  name: "collaborative_agent",
  role: "Data Analyst",
  goal: "Analyze data with human oversight",
  human_input: true,
  require_approval_for_tools: true,  # Human approves tool usage
  require_approval_for_final_answer: true  # Human validates results
)

# Human will be prompted for:
# - Tool usage approval
# - Strategic guidance during reasoning
# - Final result validation
```

## Agent Memory System

Agents maintain memory across executions:

```ruby
# Agent learns from successful executions
agent.memory.add_execution(task, result, execution_time)

# Memory influences future reasoning
relevant_experience = agent.memory.relevant_executions(current_task)

# Check memory statistics
puts agent.memory.stats
# => { total_executions: 15, successful_patterns: 8, tools_used: ["websearch", "filewriter"] }
```

## Error Handling

```ruby
begin
  result = agent.execute_task(task)
rescue RCrewAI::AgentError => e
  puts "Agent execution failed: #{e.message}"
rescue RCrewAI::ToolNotFoundError => e
  puts "Tool not available: #{e.message}"
end
```

## Examples

### Basic Research Agent

```ruby
researcher = RCrewAI::Agent.new(
  name: "ai_researcher",
  role: "AI Research Specialist",
  goal: "Research and analyze AI developments",
  backstory: "Expert in AI with focus on emerging trends and practical applications",
  tools: [RCrewAI::Tools::WebSearch.new],
  verbose: true
)

task = RCrewAI::Task.new(
  name: "ai_trends_research",
  description: "Research the top 5 AI trends for 2024",
  agent: researcher,
  expected_output: "Comprehensive analysis of AI trends with sources"
)

result = researcher.execute_task(task)
```

### Manager Agent with Team

```ruby
# Create manager
manager = RCrewAI::Agent.new(
  name: "team_lead",
  role: "Technical Team Lead",
  goal: "Coordinate technical projects efficiently",
  backstory: "Experienced engineering manager with expertise in AI project coordination",
  manager: true,
  allow_delegation: true,
  verbose: true
)

# Create specialists
backend_dev = RCrewAI::Agent.new(
  name: "backend_developer",
  role: "Senior Backend Developer", 
  goal: "Build robust backend systems",
  tools: [RCrewAI::Tools::FileReader.new, RCrewAI::Tools::FileWriter.new]
)

frontend_dev = RCrewAI::Agent.new(
  name: "frontend_developer",
  role: "Frontend Developer",
  goal: "Create excellent user interfaces", 
  tools: [RCrewAI::Tools::FileReader.new, RCrewAI::Tools::FileWriter.new]
)

# Build team hierarchy
manager.add_subordinate(backend_dev)
manager.add_subordinate(frontend_dev)

# Manager can now delegate tasks to appropriate specialists
```

### Human-Collaborative Agent

```ruby
analyst = RCrewAI::Agent.new(
  name: "data_analyst", 
  role: "Senior Data Analyst",
  goal: "Perform data analysis with human validation",
  backstory: "Expert at data analysis who collaborates closely with stakeholders",
  tools: [RCrewAI::Tools::FileReader.new, RCrewAI::Tools::FileWriter.new],
  human_input: true,
  require_approval_for_tools: true,
  require_approval_for_final_answer: true
)

# This agent will:
# 1. Ask human approval before reading/writing files
# 2. Request human guidance during complex analysis
# 3. Get human validation of final results
```

## Best Practices

1. **Specific Roles**: Give agents clear, specific roles rather than generic ones
2. **Detailed Backstories**: Provide rich context that influences agent behavior  
3. **Appropriate Tools**: Equip agents with tools relevant to their role
4. **Reasonable Limits**: Set appropriate iteration and time limits
5. **Human Oversight**: Enable human input for critical or sensitive tasks
6. **Manager Delegation**: Use manager agents for coordinating complex workflows
7. **Memory Utilization**: Let agents learn from past executions for better performance