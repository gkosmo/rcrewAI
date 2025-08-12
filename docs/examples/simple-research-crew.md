---
layout: example
title: Simple Research Crew
description: A basic research crew example with researcher and writer agents
---

# Simple Research Crew

This example demonstrates how to create a basic research crew with two agents: a researcher who gathers information and a writer who creates content based on that research.

## Overview

We'll create a crew that:
1. Researches a given topic
2. Writes an informative article based on the research
3. Returns both the research findings and the final article

## Complete Code

```ruby
require 'rcrewai'

# Configure RCrewAI - supports multiple providers
RCrewAI.configure do |config|
  config.llm_provider = :openai  # or :anthropic, :google, :azure
  # API keys are loaded automatically from environment variables
  config.openai_model = 'gpt-4'  # or 'gpt-3.5-turbo' for lower cost
  config.temperature = 0.1       # Lower = more consistent, Higher = more creative
end

# Create the crew
research_crew = RCrewAI::Crew.new("research_crew")

# Define the research agent
researcher = RCrewAI::Agent.new(
  name: "senior_researcher",
  role: "Senior Research Analyst",
  goal: "Uncover cutting-edge developments in AI and technology",
  backstory: "You work at a leading tech think tank. Your expertise lies in identifying emerging trends in AI and technology. You have a knack for dissecting complex topics and presenting clear insights.",
  verbose: true,
  allow_delegation: false
)

# Define the writer agent
writer = RCrewAI::Agent.new(
  name: "tech_writer",
  role: "Tech Content Strategist", 
  goal: "Craft compelling content on tech advancements",
  backstory: "You are a renowned Content Strategist, known for your insightful and engaging articles on technology and innovation. With a deep understanding of the tech industry, you transform complex concepts into compelling narratives.",
  verbose: true,
  allow_delegation: true
)

# Add agents to the crew
research_crew.add_agent(researcher)
research_crew.add_agent(writer)

# Define the research task
research_task = RCrewAI::Task.new(
  name: "research_ai_advancements",
  description: "Conduct a comprehensive analysis of the latest advancements in AI in 2024. Identify key trends, breakthrough technologies, and their potential impact on various industries. Your final report should be detailed and well-structured.",
  agent: researcher,
  expected_output: "A comprehensive research report with key findings, trends, and implications of AI advancements in 2024"
)

# Define the writing task
writing_task = RCrewAI::Task.new(
  name: "write_ai_article",
  description: "Using the research provided, write a compelling blog article about the latest AI advancements. Make it engaging but informative, suitable for a tech-savvy audience. Include an introduction, main content with key points, and a conclusion.",
  agent: writer,
  expected_output: "A well-written, engaging blog article about AI advancements (800-1000 words)",
  context: [research_task]  # This task depends on the research task
)

# Add tasks to the crew
research_crew.add_task(research_task)
research_crew.add_task(writing_task)

# Execute the crew
puts "Starting research crew execution..."
results = research_crew.execute

# Display results
puts "\n" + "="*50
puts "RESEARCH RESULTS:"
puts "="*50
puts research_task.result

puts "\n" + "="*50  
puts "FINAL ARTICLE:"
puts "="*50
puts writing_task.result

# Optional: Save results to files
File.write("research_findings.md", research_task.result)
File.write("ai_article.md", writing_task.result)

puts "\nResults saved to research_findings.md and ai_article.md"
```

## Step-by-Step Explanation

### 1. Setup and Configuration

```ruby
require 'rcrewai'

RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.api_key = ENV['OPENAI_API_KEY']
  config.model = 'gpt-4'
end
```

First, we require the RCrewAI gem and configure it with our LLM provider. The API key should be stored in an environment variable for security.

### 2. Create the Crew

```ruby
research_crew = RCrewAI::Crew.new("research_crew")
```

We create a new crew instance that will coordinate our agents and tasks.

### 3. Define Agents

#### Research Agent
```ruby
researcher = RCrewAI::Agent.new(
  name: "senior_researcher",
  role: "Senior Research Analyst", 
  goal: "Uncover cutting-edge developments in AI and technology",
  backstory: "You work at a leading tech think tank...",
  verbose: true,
  allow_delegation: false
)
```

The researcher agent is designed to gather and analyze information. Key attributes:
- **Role**: Defines what the agent does
- **Goal**: Specific objective for the agent
- **Backstory**: Provides context that influences the agent's behavior
- **verbose**: Enables detailed logging
- **allow_delegation**: Controls whether this agent can delegate tasks

#### Writer Agent
```ruby
writer = RCrewAI::Agent.new(
  name: "tech_writer",
  role: "Tech Content Strategist",
  goal: "Craft compelling content on tech advancements", 
  backstory: "You are a renowned Content Strategist...",
  verbose: true,
  allow_delegation: true
)
```

The writer transforms research into engaging content.

### 4. Define Tasks

#### Research Task
```ruby
research_task = RCrewAI::Task.new(
  name: "research_ai_advancements",
  description: "Conduct a comprehensive analysis...",
  agent: researcher,
  expected_output: "A comprehensive research report..."
)
```

Tasks define what work needs to be done. The `expected_output` helps guide the agent's work quality.

#### Writing Task
```ruby
writing_task = RCrewAI::Task.new(
  name: "write_ai_article", 
  description: "Using the research provided...",
  agent: writer,
  expected_output: "A well-written, engaging blog article...",
  context: [research_task]  # Dependencies
)
```

The `context` parameter creates dependencies - the writing task will have access to the research task's results.

### 5. Execute and Handle Results

```ruby
results = research_crew.execute

puts research_task.result
puts writing_task.result
```

The crew executes tasks in order, respecting dependencies. Results are accessible through each task's `result` attribute.

## Running the Example

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Set environment variables (choose your provider):**
   ```bash
   # OpenAI
   export OPENAI_API_KEY="your-openai-key"
   
   # Or Anthropic
   export ANTHROPIC_API_KEY="your-anthropic-key"
   
   # Or Google
   export GOOGLE_API_KEY="your-google-key"
   
   # Or Azure
   export AZURE_OPENAI_API_KEY="your-azure-key"
   ```

3. **Run the script:**
   ```bash
   ruby research_crew_example.rb
   ```

## Expected Output

The script will produce:
- Research findings about AI advancements
- A well-structured blog article based on the research
- Saved files with the results

## Customization Options

### Different Topics
Change the task descriptions to research different topics:

```ruby
research_task = RCrewAI::Task.new(
  name: "research_blockchain",
  description: "Research the latest developments in blockchain technology...",
  # ... rest of configuration
)
```

### Adding Tools
Equip agents with tools for enhanced capabilities:

```ruby
web_search_tool = RCrewAI::Tools::WebSearch.new

researcher = RCrewAI::Agent.new(
  name: "senior_researcher",
  # ... other config
  tools: [web_search_tool]
)
```

### Multiple Output Formats
Create additional tasks for different output formats:

```ruby
# Add a summarizer agent
summarizer = RCrewAI::Agent.new(
  name: "content_summarizer",
  role: "Content Summarizer",
  goal: "Create concise summaries"
)

# Summary task
summary_task = RCrewAI::Task.new(
  name: "create_summary",
  description: "Create a 200-word summary of the research and article",
  agent: summarizer,
  context: [research_task, writing_task]
)
```

## Troubleshooting

### Common Issues

1. **API Key Issues**: Ensure your OpenAI API key is correctly set
2. **Agent Confusion**: Make sure agent roles and goals are specific and clear
3. **Task Dependencies**: Verify that dependent tasks are added to the crew before dependent tasks

### Debugging Tips

- Set `verbose: true` on agents to see detailed execution logs
- Use `crew.verbose = true` for crew-level logging
- Check individual task results with `task.result` after execution

## Next Steps

- Try modifying the agent roles and backstories
- Add more agents for specialized tasks (fact-checker, SEO optimizer)
- Experiment with different task dependencies
- Add custom tools for specific capabilities