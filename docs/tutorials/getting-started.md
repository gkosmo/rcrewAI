---
layout: tutorial
title: Getting Started with RCrewAI
description: Learn how to install and use RCrewAI to build your first AI crew
---

# Getting Started with RCrewAI

This tutorial will walk you through installing RCrewAI and creating your first AI crew.

## Prerequisites

Before you begin, ensure you have:
- Ruby 3.0 or higher installed
- Bundler gem installed (`gem install bundler`) 
- Access to a model through one of the supported providers:
  - **OpenAI**: get a key from [platform.openai.com](https://platform.openai.com)
  - **Anthropic (Claude)**: get a key from [console.anthropic.com](https://console.anthropic.com)
  - **Google (Gemini)**: get a key from [ai.google.dev](https://ai.google.dev)
  - **Azure OpenAI**: set up through the Azure portal
  - **Ollama**: runs locally, with no key
  - **Others**: AWS Bedrock, Snowflake Cortex, or any OpenAI-compatible endpoint

## Installation

### Method 1: Add to your Gemfile

Add RCrewAI to your application's Gemfile:

```ruby
gem 'rcrewai'
```

Then run:

```bash
bundle install
```

### Method 2: Direct Installation

Install the gem directly:

```bash
gem install rcrewai
```

## Configuration

Choose a provider. API keys are read from environment variables, and `config.model`
selects the model.

### OpenAI

```bash
export OPENAI_API_KEY="your-openai-key-here"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.model = 'gpt-4o'
end
```

### Anthropic (Claude)

```bash
export ANTHROPIC_API_KEY="your-anthropic-key-here"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.model = 'claude-opus-5-5'
end
```

### Google (Gemini)

```bash
export GOOGLE_API_KEY="your-google-key-here"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :google
  config.model = 'gemini-3.8-flash'
end
```

### Azure OpenAI

```bash
export AZURE_OPENAI_API_KEY="your-azure-key"
export AZURE_API_VERSION="2024-10-21"
export AZURE_DEPLOYMENT_NAME="your-deployment"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.base_url = "https://your-resource.openai.azure.com/"
end
```

### Ollama (local)

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :ollama
  config.model = 'llama3.1'  # no API key needed
end
```

For more configuration options, see the [Configuration Documentation]({{ site.baseurl }}/api/configuration).

## Creating Your First Crew

Let's create an intelligent research crew that can actually search the web, analyze information, and write reports.

### Step 1: Create the Crew and Configure

```ruby
require 'rcrewai'

# Configure RCrewAI with your chosen provider
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.model = 'gpt-4o'
  # API keys are loaded from environment variables automatically
end

# Create a new crew
crew = RCrewAI::Crew.new("ai_research_crew")
```

### Step 2: Create Intelligent Agents with Tools

Create specialized agents with actual capabilities:

```ruby
# Research Agent with web search capabilities
researcher = RCrewAI::Agent.new(
  name: "alex_researcher",
  role: "Senior Research Analyst", 
  goal: "Uncover cutting-edge developments in AI and data science",
  backstory: "You are a seasoned researcher with a knack for uncovering the latest trends and technologies in AI and data science. You excel at finding reliable sources and extracting key insights.",
  tools: [RCrewAI::Tools::WebSearch.new],  # Can search the web!
  verbose: true,  # Logs each step
  max_iterations: 5  # Limit LLM turns per task
)

# Writer Agent with file writing capabilities  
writer = RCrewAI::Agent.new(
  name: "emma_writer",
  role: "Tech Content Strategist",
  goal: "Craft compelling content on tech advancements", 
  backstory: "You are a renowned Content Strategist, known for your insightful and engaging articles on technology and innovation. You transform complex research into compelling narratives.",
  tools: [
    RCrewAI::Tools::FileWriter.new,  # Can write files!
    RCrewAI::Tools::FileReader.new   # Can read reference materials
  ],
  verbose: true,
  allow_delegation: false
)

# Add agents to the crew
crew.add_agent(researcher)
crew.add_agent(writer)
```

### Step 3: Create Advanced Tasks with Dependencies

Define tasks with specific outputs and dependencies:

```ruby
# Research Task - The agent can search the web
research_task = RCrewAI::Task.new(
  name: "research_ai_trends",
  description: "Research the latest AI developments and breakthroughs. Focus on identifying key trends, major companies involved, and potential impacts on different industries.",
  agent: researcher,
  expected_output: "A comprehensive research report covering: 1) Top 5 AI trends, 2) Key companies and their innovations, 3) Industry impact analysis, 4) Future predictions",
  max_retries: 2  # Retry if the task raises an error
)

# Writing Task - Agent uses the research results, and the output is saved to a file
writing_task = RCrewAI::Task.new(
  name: "write_ai_trends_article", 
  description: "Write a compelling, informative article about AI trends based on the research. Make it engaging for a tech-savvy audience.",
  agent: writer,
  expected_output: "A well-structured 1000-1500 word article covering the research findings",
  output_file: "ai_trends.md",  # Writes the result here when the task finishes
  context: [research_task],  # Uses research results as input
  callback: ->(task, result) { puts "Article completed: #{result.length} characters written!" }
)

# Add tasks to the crew
crew.add_task(research_task)
crew.add_task(writing_task)
```

### Step 4: Execute and Monitor

Run the crew and monitor the intelligent agents at work:

```ruby
puts "🚀 Starting AI Research Crew..."
puts "The agents will now research and write about AI trends!"

# Runs the tasks in order, passing the research to the writer as context
result = crew.execute
puts "Success rate: #{result[:success_rate]}% (#{result[:completed_tasks]}/#{result[:total_tasks]} tasks)"

# Check results and status
puts "\n" + "="*50
puts "📊 EXECUTION SUMMARY"
puts "="*50

puts "Research Task Status: #{research_task.status}"
puts "Research Execution Time: #{research_task.execution_time&.round(2)}s"
puts "Research Result Preview:"
puts research_task.result[0..200] + "..." if research_task.result

puts "\nWriting Task Status: #{writing_task.status}" 
puts "Writing Execution Time: #{writing_task.execution_time&.round(2)}s"
puts "Article Preview:"
puts writing_task.result[0..200] + "..." if writing_task.result

# Check if file was actually created
if File.exist?('ai_trends.md')
  puts "\n✅ Article successfully saved to ai_trends.md"
  puts "File size: #{File.size('ai_trends.md')} bytes"
else
  puts "\n❌ Article file not found"
end

# Check agent memory stats
puts "\n🧠 Agent Memory Stats:"
puts "Researcher memory: #{researcher.memory.stats}"
puts "Writer memory: #{writer.memory.stats}"
```

### What Just Happened?

When you run this code with a valid API key:

1. **The researcher** gets its task plus its tools. The model decides whether and how
   often to call `web_search`, which uses DuckDuckGo, and writes a report from the results.
2. **The writer** gets the researcher's result as context, because the task lists it in
   `context:`, and writes the article. RCrewAI saves the result to `ai_trends.md`
   because of `output_file:`.
3. **Each agent** records its work in memory. By default this lasts only as long as the
   process. See [Cognitive Memory]({{ site.baseurl }}/tutorials/memory) to persist it.

A task that raises an error is retried up to `max_retries` times. If it still fails,
the crew moves on, and `result[:failed_tasks]` tells you how many failed. Any task that
depends on a failed one through `context:` fails too.

## Using the CLI

RCrewAI also installs an `rcrewai` command. Its most useful job today is inspecting
saved checkpoints with `rcrewai checkpoint list`, `info`, and `delete`.

```bash
$ rcrewai version
$ rcrewai checkpoint list --dir .rcrewai/checkpoints
```

The `new`, `list`, and `run` commands are placeholders. They don't save crew definitions
between invocations, so `rcrewai run --crew NAME` starts an empty crew, and `rcrewai list`
prints fixed example names. Define your crews in Ruby, as in this tutorial.

## Working with Tools

Agents can be equipped with tools to enhance their capabilities:

```ruby
# Create a web search tool
search_tool = RCrewAI::Tools::WebSearch.new

# Create an agent with tools
analyst = RCrewAI::Agent.new(
  name: "data_analyst",
  role: "Data Analyst",
  goal: "Analyze data and provide insights",
  tools: [search_tool]
)
```

## Best Practices

1. **Define Clear Roles**: Give each agent a specific, well-defined role
2. **Set Specific Goals**: Make agent goals measurable and achievable
3. **Create Detailed Tasks**: Provide clear descriptions and expected outputs
4. **Use Task Dependencies**: Link related tasks using the context parameter
5. **Leverage Tools**: Equip agents with appropriate tools for their tasks

## Next Steps

Now that you've created your first crew, explore these topics:

- [Advanced Agent Configuration]({{ site.baseurl }}/tutorials/advanced-agents)
- [Custom Tools Development]({{ site.baseurl }}/tutorials/custom-tools)
- [Working with Multiple Crews]({{ site.baseurl }}/tutorials/multiple-crews)
- [Cognitive Memory]({{ site.baseurl }}/tutorials/memory)
- [Production Deployment]({{ site.baseurl }}/tutorials/deployment)

## Troubleshooting

### Common Issues

**Issue**: `API key must be set for openai`
**Solution**: Set the provider's environment variable, such as `OPENAI_API_KEY`, or assign it in `RCrewAI.configure`.

**Issue**: A model-not-found error from the provider
**Solution**: Set `config.model` to a model your account can use. Some built-in defaults are old, and providers retire models over time.

**Issue**: A 400 error mentioning `temperature` on Claude
**Solution**: Remove `config.temperature`, or set `temperature: nil` in that agent's `llm:`. Current Claude models reject this parameter.

**Issue**: A task has status `failed`
**Solution**: Check `task.result`, which holds the error message, and the log output. A task also fails if a task in its `context:` failed.

## Get Help

- [GitHub Issues](https://github.com/gkosmo/rcrewAI/issues)
- [API Documentation]({{ site.baseurl }}/api/)
- [Examples]({{ site.baseurl }}/examples/)