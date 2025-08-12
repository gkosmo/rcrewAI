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
- An API key from one of the supported providers:
  - **OpenAI** (recommended for beginners): Get from [platform.openai.com](https://platform.openai.com)
  - **Anthropic (Claude)**: Get from [console.anthropic.com](https://console.anthropic.com)
  - **Google (Gemini)**: Get from [ai.google.dev](https://ai.google.dev)
  - **Azure OpenAI**: Set up through Azure portal

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

RCrewAI supports multiple LLM providers. Choose the one that works best for you:

### OpenAI (Recommended for beginners)

Set your API key as an environment variable:
```bash
export OPENAI_API_KEY="your-openai-key-here"
```

Configure RCrewAI:
```ruby
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_model = 'gpt-4'  # or 'gpt-3.5-turbo' for lower cost
end
```

### Anthropic (Claude)

```bash
export ANTHROPIC_API_KEY="your-anthropic-key-here"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.anthropic_model = 'claude-3-sonnet-20240229'
end
```

### Google (Gemini)

```bash
export GOOGLE_API_KEY="your-google-key-here"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :google
  config.google_model = 'gemini-pro'
end
```

### Azure OpenAI

```bash
export AZURE_OPENAI_API_KEY="your-azure-key"
export AZURE_API_VERSION="2023-05-15"
export AZURE_DEPLOYMENT_NAME="your-deployment"
```

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.base_url = "https://your-resource.openai.azure.com/"
  config.azure_model = 'gpt-4'
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
  config.llm_provider = :openai  # or :anthropic, :google, :azure
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
  verbose: true,  # Shows reasoning process
  max_iterations: 5  # Limit reasoning loops
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
# Research Task - Agent will actually search the web!
research_task = RCrewAI::Task.new(
  name: "research_ai_trends_2024",
  description: "Research the latest AI developments and breakthroughs in 2024. Focus on identifying key trends, major companies involved, and potential impacts on different industries.",
  agent: researcher,
  expected_output: "A comprehensive research report covering: 1) Top 5 AI trends in 2024, 2) Key companies and their innovations, 3) Industry impact analysis, 4) Future predictions",
  max_retries: 2  # Retry if web search fails
)

# Writing Task - Agent will use research results and save to file!
writing_task = RCrewAI::Task.new(
  name: "write_ai_trends_article", 
  description: "Write a compelling, informative article about AI trends based on the research. Make it engaging for a tech-savvy audience. Save the final article to a file named 'ai_trends_2024.md'.",
  agent: writer,
  expected_output: "A well-structured 1000-1500 word article covering the research findings, saved to ai_trends_2024.md file",
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

# Execute the crew - this will:
# 1. Research agent searches web for AI trends
# 2. Research agent analyzes and summarizes findings  
# 3. Writer agent receives research context
# 4. Writer agent creates article and saves to file
result = crew.execute

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
if File.exist?('ai_trends_2024.md')
  puts "\n✅ Article successfully saved to ai_trends_2024.md"
  puts "File size: #{File.size('ai_trends_2024.md')} bytes"
else
  puts "\n❌ Article file not found"
end

# Check agent memory stats
puts "\n🧠 Agent Memory Stats:"
puts "Researcher memory: #{researcher.memory.stats}"
puts "Writer memory: #{writer.memory.stats}"
```

### What Just Happened?

When you run this code with a valid API key, here's what actually happens:

1. **Researcher Agent**:
   - Uses reasoning loops to plan the research approach
   - Executes web searches using DuckDuckGo  
   - Analyzes search results to identify key trends
   - Synthesizes findings into a comprehensive report
   - Stores successful strategies in memory

2. **Writer Agent**:
   - Receives research findings as context
   - Plans article structure and key points
   - Creates engaging, well-structured content
   - Saves the final article to a markdown file
   - Learns from successful writing patterns

3. **System Features**:
   - Automatic retry if web search fails
   - Security controls on file operations
   - Memory persistence between executions  
   - Comprehensive logging and monitoring

## Using the CLI

RCrewAI also provides a command-line interface for managing crews:

### Create a New Crew

```bash
$ rcrewai new research_team
Creating new crew: research_team
Crew 'research_team' created successfully!
```

### List Available Crews

```bash
$ rcrewai list
Available crews:
  - research_team
  - marketing_crew
  - development_crew
```

### Run a Crew

```bash
$ rcrewai run --crew research_team
Running crew: research_team
Executing tasks...
```

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
- [Production Deployment]({{ site.baseurl }}/tutorials/deployment)

## Troubleshooting

### Common Issues

**Issue**: "No API key configured"
**Solution**: Ensure your API key is set in the environment variables or configuration file.

**Issue**: "Agent not found"
**Solution**: Make sure the agent is added to the crew before creating tasks that reference it.

**Issue**: "Task execution failed"
**Solution**: Check that all task dependencies are properly defined and agents have necessary tools.

## Get Help

- [GitHub Issues](https://github.com/gkosmo/rcrewAI/issues)
- [API Documentation]({{ site.baseurl }}/api/)
- [Examples]({{ site.baseurl }}/examples/)