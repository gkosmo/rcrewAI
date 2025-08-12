---
layout: example
title: Human-in-the-Loop Integration
description: Learn how to integrate human oversight and collaboration into your AI agent workflows
---

# Human-in-the-Loop Integration

RCrewAI provides comprehensive human-in-the-loop functionality that allows humans to collaborate with AI agents, providing oversight, guidance, and intervention when needed.

## Overview

Human-in-the-loop capabilities include:

- **Task Confirmation**: Human approval before starting critical tasks
- **Tool Approval**: Human confirmation for potentially sensitive tool usage
- **Real-time Guidance**: Human input during agent reasoning processes
- **Result Review**: Human review and feedback on task completion
- **Error Recovery**: Human intervention when agents encounter failures

## Basic Human-in-the-Loop Setup

```ruby
require 'rcrewai'

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai
end

# Create an agent with human interaction enabled
agent = RCrewAI::Agent.new(
  name: "research_agent",
  role: "Research Specialist", 
  goal: "Conduct thorough research with human oversight",
  backstory: "Expert researcher who works closely with humans for quality assurance",
  tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileWriter.new],
  human_input: true,                      # Enable human interaction
  require_approval_for_tools: true,       # Require approval for tool usage
  require_approval_for_final_answer: true # Require approval for final results
)

# Create a task with human interaction points
task = RCrewAI::Task.new(
  name: "sensitive_research", 
  description: "Research confidential market information for our new product",
  agent: agent,
  expected_output: "Market analysis report with strategic insights",
  human_input: true,                # Enable human interaction for this task
  require_confirmation: true,       # Human must confirm before starting
  allow_guidance: true,            # Allow human guidance during execution
  human_review_points: [:completion] # Review when task completes
)

# Execute - human will be prompted for input as needed
result = task.execute
```

## Human Interaction Types

### 1. Task Confirmation

Tasks can require human confirmation before starting:

```ruby
task = RCrewAI::Task.new(
  name: "deploy_changes",
  description: "Deploy the new model to production",
  require_confirmation: true,
  agent: deployment_agent
)

# When executed, human will see:
# 🤝 HUMAN APPROVAL REQUIRED
# ========================================
# Request: Confirm execution of task: deploy_changes
# Context: Description: Deploy the new model to production
# Expected Output: Not specified
# Assigned Agent: deployment_agent
# 
# Consequences: The task will be executed with the specified agent and may use external tools.
# 
# Do you approve this action? (yes/no)
```

### 2. Tool Approval Workflows

Agents can request human approval before using potentially sensitive tools:

```ruby
agent = RCrewAI::Agent.new(
  name: "data_agent",
  role: "Data Processor",
  goal: "Process data safely",
  tools: [RCrewAI::Tools::SqlDatabase.new, RCrewAI::Tools::EmailSender.new],
  require_approval_for_tools: true
)

# When agent wants to use a tool, human will see:
# 🤝 HUMAN APPROVAL REQUIRED  
# ========================================
# Request: Agent data_agent wants to use tool 'SqlDatabase'
# Context: Parameters: {"query": "SELECT * FROM customers", "database": "production"}
# Consequences: This will execute the SqlDatabase tool with the specified parameters.
#
# Do you approve this action? (yes/no)
```

### 3. Real-time Guidance During Reasoning

Humans can provide guidance during agent reasoning loops:

```ruby
agent = RCrewAI::Agent.new(
  name: "strategic_planner",
  role: "Business Strategist",
  goal: "Develop strategic plans with human input",
  human_input: true
)

task = RCrewAI::Task.new(
  name: "market_strategy",
  description: "Develop go-to-market strategy for new product",
  agent: agent,
  allow_guidance: true
)

# During execution, human will periodically see:
# 👀 HUMAN REVIEW REQUESTED
# ========================================
# Content to review:
# Task: market_strategy
# Description: Develop go-to-market strategy for new product
# 
# Current Iteration: 1
# 
# Agent Analysis:
# - Role: Business Strategist
# - Current Progress: Starting task
# - Previous Reasoning: No previous reasoning
# 
# The agent is about to continue reasoning for this task.
# ----------------------------------------
# 
# Review criteria: Task approach, Progress assessment, Strategic guidance
# 
# Please review and provide feedback (or type 'approve' to approve as-is):
```

### 4. Final Answer Review and Revision

Agents can request human review of their final answers:

```ruby
agent = RCrewAI::Agent.new(
  name: "content_creator",
  role: "Content Writer", 
  goal: "Create high-quality content",
  require_approval_for_final_answer: true
)

# When task completes, human will see:
# 👀 HUMAN REVIEW REQUESTED
# ========================================
# Content to review:
# [Agent's final answer/result here]
# ----------------------------------------
# 
# Review criteria: Accuracy, Completeness, Clarity, Relevance
# 
# Please review and provide feedback (or type 'approve' to approve as-is):

# If human provides feedback, agent can:
# 1. Revise the answer based on feedback
# 2. Use the answer as-is despite feedback  
# 3. Let human provide the correct answer
```

### 5. Error Recovery with Human Intervention

When agents encounter failures, humans can guide the recovery process:

```ruby
# If a task fails, human will see:
# 🎯 HUMAN CHOICE REQUIRED
# ========================================
# Question: Task 'data_analysis' failed with error: Connection timeout. How should I proceed?
# 
# Available choices:
#   1. Retry with current settings
#   2. Modify task parameters and retry
#   3. Abort task execution
# 
# Please select a choice (enter number or text):

# If human selects "2. Modify task parameters":
# 💬 HUMAN INPUT REQUESTED
# ========================================
# Prompt: Please specify task modifications (JSON format):
# 
# Help: Provide modifications as JSON, e.g. {"description": "new description", "expected_output": "new output"}
# 
# Please provide your input:
```

## Advanced Human Interaction Patterns

### Multi-Agent Collaboration with Human Oversight

```ruby
# Create crew with manager coordination
crew = RCrewAI::Crew.new("human_assisted_team", process: :hierarchical)

# Manager agent coordinates human interactions
manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Project Coordinator", 
  goal: "Coordinate team with human oversight",
  manager: true,
  human_input: true
)

# Specialist agents with different human interaction needs
researcher = RCrewAI::Agent.new(
  name: "researcher",
  role: "Research Specialist",
  goal: "Conduct research with human guidance",
  human_input: true,
  require_approval_for_tools: true  # Requires approval for web searches
)

analyst = RCrewAI::Agent.new(
  name: "analyst", 
  role: "Data Analyst",
  goal: "Analyze data with human validation",
  human_input: true,
  require_approval_for_final_answer: true  # Human validates analysis results
)

crew.add_agent(manager)
crew.add_agent(researcher) 
crew.add_agent(analyst)

# Tasks with different human interaction requirements
research_task = RCrewAI::Task.new(
  name: "market_research",
  description: "Research competitor landscape",
  human_input: true,
  require_confirmation: true,  # Confirm before starting research
  human_review_points: [:completion]
)

analysis_task = RCrewAI::Task.new(
  name: "competitive_analysis", 
  description: "Analyze research findings for strategic insights",
  context: [research_task],
  human_input: true,
  allow_guidance: true,        # Allow human strategic input
  human_review_points: [:completion]
)

crew.add_task(research_task)
crew.add_task(analysis_task)

# Execute with human collaboration
results = crew.execute
```

### Custom Human Input Utilities

```ruby
# Use HumanInput directly for custom interactions
human_input = RCrewAI::HumanInput.new(verbose: true)

# Request approval with context
approval = human_input.request_approval(
  "Deploy model to production environment",
  context: "Model version: v2.1.4, Environment: Production",
  consequences: "This will update the live model serving production traffic",
  timeout: 120
)

if approval[:approved]
  puts "Deployment approved: #{approval[:reason]}"
else
  puts "Deployment rejected: #{approval[:reason]}"
end

# Request multiple choice input
choice = human_input.request_choice(
  "Which deployment strategy should we use?",
  ["Blue-green deployment", "Rolling deployment", "Canary deployment"],
  timeout: 60
)

puts "Selected strategy: #{choice[:choice]}" if choice[:valid]

# Request text input with validation
input = human_input.request_input(
  "Enter the deployment configuration:",
  type: :json,
  validation: {
    required_keywords: ["environment", "replicas"],
    min_length: 20
  }
)

if input[:valid]
  config = input[:processed_input]
  puts "Configuration: #{config}"
else
  puts "Invalid input: #{input[:reason]}"
end

# Get session summary
summary = human_input.session_summary
puts "Human interactions: #{summary[:total_interactions]}"
puts "Approval rate: #{summary[:approvals] / summary[:total_interactions].to_f * 100}%"
```

## Best Practices

### 1. **Strategic Human Checkpoints**
- Use human approval for irreversible actions (deployments, data modifications)
- Request human guidance for strategic decisions
- Get human validation for critical outputs

### 2. **Balanced Automation**
- Enable human input for high-risk operations only
- Use timeouts to prevent workflow blocking
- Provide meaningful context for human decisions

### 3. **Error Recovery**
- Always offer human intervention options when tasks fail
- Allow humans to modify task parameters for retry
- Provide clear error context and suggested actions

### 4. **User Experience**
- Keep approval requests concise but informative
- Provide reasonable timeout values
- Show consequences of actions clearly

### 5. **Testing and Development**
- Use auto-approval mode for testing workflows
- Test human interaction flows in development
- Monitor interaction patterns and optimize prompts

## Configuration Options

```ruby
# Agent-level human input configuration
agent = RCrewAI::Agent.new(
  name: "agent",
  role: "Specialist",
  goal: "Complete tasks with human collaboration",
  human_input: true,                       # Enable human input
  require_approval_for_tools: true,        # Require approval for all tools
  require_approval_for_final_answer: false # Optional final answer approval
)

# Task-level human input configuration  
task = RCrewAI::Task.new(
  name: "task",
  description: "Complete a complex task",
  agent: agent,
  human_input: true,                       # Enable human input
  require_confirmation: false,             # No confirmation needed to start
  allow_guidance: true,                    # Allow human guidance during execution
  human_review_points: [:completion, :error] # Review at completion and errors
)

# HumanInput utility configuration
human_input = RCrewAI::HumanInput.new(
  timeout: 300,                           # Default timeout in seconds
  verbose: true,                          # Enable verbose logging
  auto_approve: false,                    # Disable auto-approval (for testing)
  approval_keywords: %w[yes y approve],   # Custom approval keywords
  rejection_keywords: %w[no n reject]     # Custom rejection keywords
)
```

Human-in-the-loop integration makes RCrewAI perfect for scenarios requiring human oversight, strategic input, or collaborative decision-making while maintaining the power and efficiency of AI automation.