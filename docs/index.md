---
layout: default
title: RCrewAI - Build AI Agent Crews in Ruby
---

# RCrewAI

Build powerful AI agent crews in Ruby that work together to accomplish complex tasks.

<div class="hero-section">
  <p class="lead">RCrewAI is a Ruby implementation of the CrewAI framework, allowing you to create autonomous AI agents that collaborate to solve problems and complete tasks.</p>
  
  <div class="cta-buttons">
    <a href="{{ site.baseurl }}/tutorials/getting-started" class="btn btn-primary">Get Started</a>
    <a href="https://github.com/gkosmo/rcrewAI" class="btn btn-secondary">View on GitHub</a>
  </div>
</div>

## Features

- **🤖 Intelligent Agents**: AI agents with reasoning loops, memory, and tool usage capabilities
- **🔗 Multi-LLM Support**: OpenAI, Anthropic (Claude), Google (Gemini), Azure OpenAI, and Ollama — configurable per agent
- **🛠️ Rich Tool Ecosystem**: Native function calling, MCP servers, web search, file operations, SQL, email, code execution, PDF processing, and custom tools
- **🌊 Flows**: Event-driven workflows (`start`/`listen`/`router`) with branching and persistent state
- **📚 Knowledge (RAG)**: Ground agents in your own documents (string/file/PDF/CSV/URL) with built-in retrieval
- **🧠 Cognitive Memory**: Semantic recall (embeddings + cosine) with optional SQLite persistence and short-term/long-term/entity/tool memory types
- **📤 Structured Output & Guardrails**: Schema-validated task output and validate/transform guardrails
- **🗳️ Flexible Orchestration**: Sequential, hierarchical, and consensual (propose → vote → pick) processes, plus async execution
- **🤝 Human-in-the-Loop**: Interactive approval workflows, human guidance, and collaborative decision making
- **⚡ Advanced Task System**: Dependencies, retries, async/concurrent execution, planning, and context sharing
- **🎛️ Production Controls**: Rate limiting (`max_rpm`), context-window management, reasoning passes, multimodal input, and streaming events with cost tracking
- **💎 Ruby-First Design**: Built specifically for Ruby developers with idiomatic patterns

## What's new (0.4 – 0.7)

RCrewAI has expanded well beyond the classic crew model. Recent releases added:

- **[Flows]({{ site.baseurl }}/tutorials/flows)** — a second orchestration pillar for event-driven, stateful workflows
- **[Knowledge / RAG]({{ site.baseurl }}/tutorials/knowledge)** — retrieval-augmented grounding from your own documents
- **[Cognitive Memory]({{ site.baseurl }}/tutorials/memory)** — semantic, persistent, multi-type agent memory
- **[Consensual process]({{ site.baseurl }}/tutorials/consensual-process)** — multi-agent voting to pick the best answer
- **[Advanced agent options]({{ site.baseurl }}/tutorials/agent-options)** — per-agent LLM, reasoning, rate limiting, context-window management, multimodal, structured output, guardrails, and lifecycle hooks

See the [CHANGELOG](https://github.com/gkosmo/rcrewAI/blob/main/CHANGELOG.md) and the
per-release upgrade guides (e.g. [upgrading to 0.7](https://github.com/gkosmo/rcrewAI/blob/main/docs/upgrading-to-0.7.md)) for details.

## What's new (0.8 – 0.10)

- **[Providers]({{ site.baseurl }}/tutorials/providers)**: AWS Bedrock, Snowflake Cortex, OpenAI-compatible endpoints and the Responses API
- **[Checkpointing]({{ site.baseurl }}/tutorials/checkpointing)**: resume a failed run without repeating finished tasks
- **[Interceptors and events]({{ site.baseurl }}/tutorials/interceptors-and-events)**: hook into LLM calls and rebuild a run into a trace
- **[Concurrency]({{ site.baseurl }}/tutorials/concurrency)**: parallel tool calls, consensus rounds and embeddings, each with a limit
- **[Live streaming]({{ site.baseurl }}/tutorials/live-streaming)**: cancellable Anthropic streams with connection reuse

Upgrading? See [what to check]({{ site.baseurl }}/upgrading-to-0.10).

## Quick Start

### Basic Agent Collaboration

```ruby
require 'rcrewai'

# Configure your LLM provider
RCrewAI.configure do |config|
  config.llm_provider = :openai  # or :anthropic, :google, :azure, :ollama
  config.temperature = 0.1
end

# Create intelligent agents with specialized tools
researcher = RCrewAI::Agent.new(
  name: "researcher",
  role: "Senior Research Analyst",
  goal: "Uncover cutting-edge developments in AI",
  backstory: "Expert at finding and analyzing the latest tech trends",
  tools: [RCrewAI::Tools::WebSearch.new],
  verbose: true
)

writer = RCrewAI::Agent.new(
  name: "writer", 
  role: "Tech Content Strategist",
  goal: "Create compelling technical content",
  backstory: "Skilled at transforming research into engaging articles",
  tools: [RCrewAI::Tools::FileWriter.new]
)

# Create crew with sequential process
crew = RCrewAI::Crew.new("ai_research_crew")
crew.add_agent(researcher)
crew.add_agent(writer)

# Define tasks with dependencies
research_task = RCrewAI::Task.new(
  name: "research_ai_trends",
  description: "Research the latest developments in AI for 2024",
  agent: researcher,
  expected_output: "Comprehensive report on AI trends with key insights"
)

writing_task = RCrewAI::Task.new(
  name: "write_article",
  description: "Write an engaging 1000-word article about AI trends",
  agent: writer,
  context: [research_task],  # Uses research results as context
  expected_output: "Publication-ready article saved as ai_trends.md"
)

crew.add_task(research_task)
crew.add_task(writing_task)

# Execute - agents will reason, search, and produce real results!
results = crew.execute
puts "✅ Crew completed #{results[:completed_tasks]}/#{results[:total_tasks]} tasks"
```

### Advanced: Hierarchical Team with Human Oversight

```ruby
# Create a hierarchical crew with manager coordination
crew = RCrewAI::Crew.new("enterprise_team", process: :hierarchical)

# Manager agent coordinates the team
manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Senior Project Manager", 
  goal: "Coordinate team execution efficiently",
  backstory: "Experienced manager with expertise in AI project coordination",
  manager: true,
  allow_delegation: true,
  verbose: true
)

# Specialist agents with human-in-the-loop capabilities
data_analyst = RCrewAI::Agent.new(
  name: "data_analyst",
  role: "Senior Data Analyst",
  goal: "Analyze data with human validation", 
  backstory: "Expert at extracting insights from complex datasets",
  tools: [RCrewAI::Tools::SqlDatabase.new, RCrewAI::Tools::FileWriter.new],
  human_input: true,                      # Enable human interaction
  require_approval_for_tools: true,       # Human approves SQL queries
  require_approval_for_final_answer: true # Human validates analysis
)

# Add agents to hierarchical crew
crew.add_agent(manager)
crew.add_agent(data_analyst)
crew.add_agent(researcher)

# Tasks with different execution modes
analysis_task = RCrewAI::Task.new(
  name: "customer_analysis",
  description: "Analyze customer behavior patterns from database",
  expected_output: "Customer segmentation analysis with actionable insights",
  human_input: true,
  require_confirmation: true,  # Human confirms before starting
  async: true                  # Can run concurrently
)

research_task = RCrewAI::Task.new(
  name: "market_research", 
  description: "Research competitive landscape",
  expected_output: "Competitive analysis report",
  async: true
)

crew.add_task(analysis_task)
crew.add_task(research_task)

# Execute with async/hierarchical coordination
results = crew.execute(async: true, max_concurrency: 2)
puts "🚀 Hierarchical execution completed with #{results[:success_rate]}% success rate"
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rcrewai'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install rcrewai
```

## CLI Usage

```bash
# Create and list crews
$ rcrewai new my_research_crew
$ rcrewai list

# Create agents and tasks
$ rcrewai agent new researcher \
  --role "Senior Research Analyst" \
  --goal "Find reliable sources"

$ rcrewai task new research \
  --description "Research latest AI developments" \
  --agent researcher \
  --async

# Run a crew
$ rcrewai run --crew my_research_crew

# Inspect saved checkpoints
$ rcrewai checkpoint list
$ rcrewai checkpoint info RUN_ID
$ rcrewai checkpoint delete RUN_ID
```

`checkpoint` and `version` are fully working. The `new`, `list`, `run`, `agent` and `task` commands are placeholders: they don't save anything, the lists are sample names, and `run` executes an empty crew. For now, define crews in Ruby.

## Key Capabilities

### 🧠 **Advanced Agent Intelligence**
Agents use sophisticated reasoning with your chosen LLM provider:
- **Multi-step Reasoning**: Complex problem decomposition and solving
- **Tool Selection**: Intelligent tool usage based on task requirements  
- **Context Awareness**: Memory-driven decision making from past executions
- **Learning Capability**: Short-term and long-term memory systems

### 🛠️ **Comprehensive Tool Ecosystem**
Production-ready tools for real-world tasks:
- **Web Search**: DuckDuckGo integration for research and information gathering
- **File Operations**: Read/write files with security controls and validation
- **SQL Database**: Secure database querying with connection management
- **Email Integration**: SMTP email sending with attachment support
- **Code Execution**: Sandboxed code execution environment
- **PDF Processing**: Text extraction and document processing
- **Custom Tools**: Extensible framework for building specialized tools

### 🤝 **Human-in-the-Loop Integration**
Seamless human-AI collaboration for critical workflows:
- **Interactive Approval**: Human confirmation for sensitive operations
- **Real-time Guidance**: Human input during agent reasoning processes
- **Task Confirmation**: Human approval before executing critical tasks
- **Result Validation**: Human review and revision of agent outputs
- **Error Recovery**: Human intervention when agents encounter failures
- **Strategic Input**: Human guidance for complex decision making

### 🏗️ **Enterprise-Grade Orchestration**  
Sophisticated coordination patterns for complex workflows:
- **Hierarchical Teams**: Manager agents coordinate and delegate to specialists
- **Async Execution**: Parallel task processing with intelligent dependency management
- **Delegation Systems**: Automatic task assignment based on agent capabilities
- **Process Types**: Sequential, hierarchical, and consensual execution modes
- **Cross-Agent Communication**: Context sharing and collaborative problem solving

### ⚡ **Advanced Task Management**
Powerful task system with production features:
- **Smart Dependencies**: Tasks automatically wait for prerequisite completion
- **Context Propagation**: Results flow seamlessly between dependent tasks
- **Retry Logic**: Exponential backoff with configurable retry strategies
- **Concurrent Execution**: Multi-threaded execution with resource management
- **Task Monitoring**: Real-time progress tracking and performance metrics

### 🔒 **Production-Ready Architecture**
Built for enterprise deployment and reliability:
- **Security**: Sandboxing, access controls, input sanitization
- **Monitoring**: Comprehensive logging, metrics, and observability
- **Error Handling**: Graceful failure recovery and detailed error reporting
- **Resource Management**: Memory optimization, connection pooling
- **Configuration**: Flexible configuration with environment variable support

## LLM Provider Support

RCrewAI works with all major LLM providers through a unified interface:

```ruby
# OpenAI
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.openai_model = 'gpt-4o'
end

# Anthropic
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.anthropic_model = 'claude-opus-5-5'
  config.temperature = nil # current Claude models reject temperature
end

# Google Gemini
RCrewAI.configure do |config|
  config.llm_provider = :google
  config.google_api_key = ENV['GOOGLE_API_KEY']
  config.google_model = 'gemini-2.5-flash'
end

# Azure OpenAI
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.azure_api_key = ENV['AZURE_OPENAI_API_KEY']
  config.base_url = ENV['AZURE_OPENAI_ENDPOINT']
  config.deployment_name = 'your-deployment'
  config.api_version = '2024-10-21'
end

# Local Ollama (no API key)
RCrewAI.configure do |config|
  config.llm_provider = :ollama
  config.base_url = 'http://localhost:11434'
  config.model = 'llama3.1'
end

# Any OpenAI-compatible endpoint: Together, Groq, Fireworks, vLLM, LiteLLM, OpenRouter
RCrewAI.configure do |config|
  config.llm_provider = :openai_compatible
  config.base_url = 'https://api.groq.com/openai/v1'
  config.api_key = ENV['GROQ_API_KEY']
  config.model = 'your-model'
end

# AWS Bedrock (bearer token; SigV4 signing isn't built in)
RCrewAI.configure do |config|
  config.llm_provider = :bedrock
  config.aws_region = 'us-east-1'
  config.api_key = ENV['BEDROCK_API_KEY']
  config.model = 'your-bedrock-model-id'
end

# Snowflake Cortex
RCrewAI.configure do |config|
  config.llm_provider = :snowflake
  config.snowflake_account = 'your-account'
  config.api_key = ENV['SNOWFLAKE_TOKEN']
  config.model = 'your-cortex-model'
end
```

There's also `:openai_responses`, which uses OpenAI's Responses API (no streaming) with your OpenAI model and key settings.

## Use Cases

RCrewAI excels in scenarios requiring:

- **🔍 Research & Analysis**: Multi-source research with data correlation and insight generation
- **📝 Content Creation**: Collaborative content development with research, writing, and editing
- **🏢 Business Intelligence**: Data analysis, report generation, and strategic planning
- **🛠️ Development Workflows**: Code analysis, documentation, and quality assurance
- **📊 Data Processing**: ETL workflows with validation and transformation
- **🤖 Customer Support**: Intelligent routing, response generation, and escalation
- **🎯 Decision Making**: Multi-criteria analysis with human oversight and approval

## Learn More

<div class="feature-grid">
  <div class="feature-card">
    <h3>📚 Tutorials</h3>
    <p>Step-by-step guides to get you started with RCrewAI</p>
    <a href="{{ site.baseurl }}/tutorials/">View Tutorials →</a>
  </div>
  
  <div class="feature-card">
    <h3>📖 API Reference</h3>
    <p>Complete documentation of all classes and methods</p>
    <a href="{{ site.baseurl }}/api/">API Docs →</a>
  </div>
  
  <div class="feature-card">
    <h3>💡 Examples</h3>
    <p>Real-world examples and use cases</p>
    <a href="{{ site.baseurl }}/examples/">View Examples →</a>
  </div>
</div>

## Contributing

We welcome contributions! Please see our [contributing guidelines](https://github.com/gkosmo/rcrewAI/blob/main/CONTRIBUTING.md) for details.

## License

RCrewAI is released under the [MIT License](https://github.com/gkosmo/rcrewAI/blob/main/LICENSE).