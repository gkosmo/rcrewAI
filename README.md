# RCrewAI

![Ruby](https://img.shields.io/badge/ruby-%23CC342D.svg?style=for-the-badge&logo=ruby&logoColor=white)
![AI](https://img.shields.io/badge/AI-Agents-blue?style=for-the-badge)
![Production Ready](https://img.shields.io/badge/Production-Ready-green?style=for-the-badge)

Build powerful AI agent crews in Ruby that work together to accomplish complex tasks.

RCrewAI is a Ruby implementation of the CrewAI framework, allowing you to create autonomous AI agents that collaborate to solve problems and complete tasks with human oversight and enterprise-grade features.

## 🚀 Features

- **🤖 Intelligent Agents**: AI agents with reasoning loops, memory, and tool usage capabilities
- **🔗 Multi-LLM Support**: OpenAI, Anthropic (Claude), Google (Gemini), Azure OpenAI, and Ollama
- **🛠️ Rich Tool Ecosystem**: Web search, file operations, SQL, email, code execution, PDF processing, and custom tools
- **🧠 Agent Memory**: Short-term and long-term memory for learning from past executions
- **🤝 Human-in-the-Loop**: Interactive approval workflows, human guidance, and collaborative decision making
- **⚡ Advanced Task System**: Dependencies, retries, async/concurrent execution, and context sharing
- **🏗️ Hierarchical Teams**: Manager agents that coordinate and delegate tasks to specialist agents
- **🔒 Production Ready**: Security controls, error handling, logging, monitoring, and sandboxing
- **🎯 Flexible Orchestration**: Sequential, hierarchical, and concurrent execution modes
- **💎 Ruby-First Design**: Built specifically for Ruby developers with idiomatic patterns

## 📦 Installation

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

## 🏃‍♂️ Quick Start

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

## 🎯 Key Capabilities

### 🧠 Advanced Agent Intelligence
- **Multi-step Reasoning**: Complex problem decomposition and solving
- **Tool Selection**: Intelligent tool usage based on task requirements  
- **Context Awareness**: Memory-driven decision making from past executions
- **Learning Capability**: Short-term and long-term memory systems

### 🛠️ Comprehensive Tool Ecosystem
- **Web Search**: DuckDuckGo integration for research
- **File Operations**: Read/write files with security controls
- **SQL Database**: Secure database querying with connection management
- **Email Integration**: SMTP email sending with attachment support
- **Code Execution**: Sandboxed code execution environment
- **PDF Processing**: Text extraction and document processing
- **Custom Tools**: Extensible framework for building specialized tools

### 🤝 Human-in-the-Loop Integration
- **Interactive Approval**: Human confirmation for sensitive operations
- **Real-time Guidance**: Human input during agent reasoning processes
- **Task Confirmation**: Human approval before executing critical tasks
- **Result Validation**: Human review and revision of agent outputs
- **Error Recovery**: Human intervention when agents encounter failures

### 🏗️ Enterprise-Grade Orchestration  
- **Hierarchical Teams**: Manager agents coordinate and delegate to specialists
- **Async Execution**: Parallel task processing with intelligent dependency management
- **Delegation Systems**: Automatic task assignment based on agent capabilities
- **Process Types**: Sequential, hierarchical, and consensual execution modes

## 🔧 LLM Provider Support

```ruby
# OpenAI (GPT-4, GPT-3.5, etc.)
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.model = 'gpt-4'
end

# Anthropic Claude
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY'] 
  config.model = 'claude-3-sonnet-20240229'
end

# Google Gemini
RCrewAI.configure do |config|
  config.llm_provider = :google
  config.google_api_key = ENV['GOOGLE_API_KEY']
  config.model = 'gemini-pro'
end

# Azure OpenAI
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.azure_api_key = ENV['AZURE_OPENAI_API_KEY']
  config.azure_endpoint = ENV['AZURE_OPENAI_ENDPOINT']
  config.model = 'gpt-4'
end

# Local Ollama
RCrewAI.configure do |config|
  config.llm_provider = :ollama
  config.ollama_url = 'http://localhost:11434'
  config.model = 'llama2'
end
```

### Per-agent LLM

The `RCrewAI.configure` block sets the crew-wide default. Any agent can override
it with the `llm:` option, so a single crew can mix providers and models — for
example a cheap model for workers and a stronger one for the manager:

```ruby
# Provider only (uses that provider's configured model + key)
researcher = RCrewAI::Agent.new(name: 'researcher', role: '...', goal: '...',
                                llm: :anthropic)

# Provider + model (and optionally api_key / temperature)
manager = RCrewAI::Agent.new(name: 'manager', role: '...', goal: '...',
                             llm: { provider: :anthropic, model: 'claude-3-opus-20240229' })

worker = RCrewAI::Agent.new(name: 'worker', role: '...', goal: '...',
                            llm: { provider: :openai, model: 'gpt-4o-mini' })

# Or pass a pre-built client instance
worker = RCrewAI::Agent.new(name: 'worker', role: '...', goal: '...',
                            llm: my_client)
```

Omit `llm:` to use the global `RCrewAI.configure` settings. Overrides never
mutate the global configuration.

## 📤 Structured Output, Guardrails & File Output

Tasks can validate, transform, and persist their output:

```ruby
task = RCrewAI::Task.new(
  name: 'extract',
  description: 'Extract the article title and word count as JSON',
  agent: analyst,

  # Structured output — validated & coerced against a JSON schema.
  # Non-conforming output re-runs the agent with the error fed back.
  output_schema: {
    type: 'object',
    properties: { title: { type: 'string' }, words: { type: 'integer' } },
    required: ['title']
  },

  # Guardrail — ->(output) { [ok, value_or_error] }. On rejection the agent
  # re-runs (up to guardrail_max_retries) with the reason appended.
  guardrail: ->(out) { [out.length < 5000, 'must be under 5000 chars'] },
  guardrail_max_retries: 3,

  # Persist the result. Parent dirs are created unless create_directory: false.
  output_file: 'out/report.md',
  markdown: true
)

task.execute
task.structured_output  # => { "title" => "...", "words" => 1234 }
task.raw_result         # => the unprocessed string the agent produced
```

## 🗺️ Planning

Enable `planning:` on a crew to run a planner pass before execution. The planner
drafts a short plan for each task and folds it into the task description, giving
the executing agent a head start:

```ruby
crew = RCrewAI::Crew.new('research_crew', planning: true)
# Optionally use a dedicated (e.g. stronger) planner model:
crew = RCrewAI::Crew.new('research_crew', planning: true,
                         planning_llm: { provider: :anthropic, model: 'claude-3-opus-20240229' })
```

Planning is best-effort: if the planner errors or returns unparseable output,
the crew runs with the original tasks unchanged.

## 🏋️ Training & Testing

Iterate on a crew by training it with feedback or scoring repeated runs:

```ruby
# Train: run N times, collect feedback after each run, persist to JSON.
crew.train(n_iterations: 3, filename: 'training.json')

# Provide feedback programmatically instead of prompting a human:
crew.train(n_iterations: 3, filename: 'training.json',
           feedback: ->(iteration, result) { "run #{iteration}: #{result[:success_rate]}%" })

# Test: run N times and score each run (defaults to success_rate).
crew.test(n_iterations: 5)
# => { iterations: 5, scores: [...], average_score: 92.0 }
```

## 📚 Knowledge (RAG)

Ground agents in your own documents. Sources are chunked, embedded, and stored
in an in-memory vector store; the most relevant chunks are injected into each
task's prompt automatically.

```ruby
kb = RCrewAI::Knowledge::Base.new(sources: [
  RCrewAI::Knowledge::StringSource.new('Our refund window is 30 days.'),
  RCrewAI::Knowledge::FileSource.new('docs/policy.txt'),
  RCrewAI::Knowledge::PdfSource.new('handbook.pdf'),
  RCrewAI::Knowledge::UrlSource.new('https://example.com/faq')
])

# Agent-level (role-specific) knowledge:
support = RCrewAI::Agent.new(name: 'support', role: '...', goal: '...', knowledge: kb)

# Or pass raw sources and let the agent build the base:
support = RCrewAI::Agent.new(name: 'support', role: '...', goal: '...',
                             knowledge_sources: [RCrewAI::Knowledge::StringSource.new('...')])

# Crew-level knowledge is shared with every agent:
crew = RCrewAI::Crew.new('support_crew', knowledge: kb)
```

Embeddings default to OpenAI's `text-embedding-3-small`; pass a custom
`embedder:` (anything responding to `embed(texts)`) or vector store to swap the
backend.

## 💡 Examples

### Hierarchical Team with Human Oversight

```ruby
# Create a hierarchical crew with manager coordination
crew = RCrewAI::Crew.new("enterprise_team", process: :hierarchical)

# Manager agent coordinates the team
manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Senior Project Manager", 
  goal: "Coordinate team execution efficiently",
  manager: true,
  allow_delegation: true
)

# Specialist agents with human-in-the-loop capabilities
data_analyst = RCrewAI::Agent.new(
  name: "data_analyst",
  role: "Senior Data Analyst",
  goal: "Analyze data with human validation",
  tools: [RCrewAI::Tools::SqlDatabase.new],
  human_input: true,                      # Enable human interaction
  require_approval_for_tools: true,       # Human approves SQL queries
  require_approval_for_final_answer: true # Human validates analysis
)

crew.add_agent(manager)
crew.add_agent(data_analyst)

# Execute with async/hierarchical coordination
results = crew.execute(async: true, max_concurrency: 2)
```

### Async/Concurrent Execution

```ruby
# Tasks that can run in parallel
research_task = RCrewAI::Task.new(
  name: "market_research",
  description: "Research market trends",
  async: true
)

analysis_task = RCrewAI::Task.new(
  name: "competitive_analysis", 
  description: "Analyze competitors",
  async: true
)

crew.add_task(research_task)
crew.add_task(analysis_task)

# Execute with parallel processing
results = crew.execute(
  async: true,
  max_concurrency: 4,
  timeout: 300
)
```

## 🛠️ CLI Usage

```bash
# Create a new crew
$ rcrewai new my_research_crew --process sequential

# Create agents with tools
$ rcrewai agent new researcher \
  --role "Senior Research Analyst" \
  --tools web_search,file_writer \
  --human-input

# Create tasks with dependencies  
$ rcrewai task new research \
  --description "Research latest AI developments" \
  --agent researcher \
  --async

# Run crews
$ rcrewai run --crew my_research_crew --async
```

## 📚 Examples & Documentation

- **[Getting Started Guide](docs/tutorials/getting-started.md)**: Learn the basics
- **[Human-in-the-Loop Example](examples/human_in_the_loop_example.rb)**: Interactive AI workflows
- **[Hierarchical Teams](examples/hierarchical_crew_example.rb)**: Manager coordination
- **[Async Execution](examples/async_execution_example.rb)**: Performance optimization
- **[API Documentation](docs/api/)**: Complete API reference

## 🎯 Use Cases

RCrewAI excels in scenarios requiring:

- **🔍 Research & Analysis**: Multi-source research with data correlation
- **📝 Content Creation**: Collaborative content development workflows  
- **🏢 Business Intelligence**: Data analysis and strategic planning
- **🛠️ Development Workflows**: Code analysis, testing, and documentation
- **📊 Data Processing**: ETL workflows with validation
- **🤖 Customer Support**: Intelligent routing and response generation
- **🎯 Decision Making**: Multi-criteria analysis with human oversight

## 🏗️ Architecture

RCrewAI provides a flexible, production-ready architecture:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Crew Layer    │    │  Human Layer    │    │   Tool Layer    │
│                 │    │                 │    │                 │
│ • Orchestration │    │ • Approvals     │    │ • Web Search    │
│ • Process Types │    │ • Guidance      │    │ • File Ops      │
│ • Async Exec    │    │ • Reviews       │    │ • SQL Database  │
│ • Dependencies  │    │ • Interventions │    │ • Email         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                        │                        │
         └──────────────┬─────────────────┬─────────────────┘
                        │                 │
              ┌─────────────────┐    ┌─────────────────┐
              │   Agent Layer   │    │   LLM Layer     │
              │                 │    │                 │
              │ • Reasoning     │    │ • OpenAI        │
              │ • Memory        │    │ • Anthropic     │
              │ • Tool Usage    │    │ • Google        │
              │ • Delegation    │    │ • Azure         │
              └─────────────────┘    └─────────────────┘
```

## 🚀 Rails Integration

### rcrew RAILS

For Rails applications, use the **rcrew RAILS** gem (`rcrewai-rails`) [(repo here)](https://github.com/gkosmo/rcrewai-rails) which provides:

- **🏗️ Rails Engine**: Mountable engine with web UI for managing crews
- **💾 ActiveRecord Integration**: Database persistence for agents, tasks, and executions
- **⚡ Background Jobs**: ActiveJob integration for async crew execution
- **🎯 Rails Generators**: Scaffolding for crews, agents, and tasks
- **🌐 Web Dashboard**: Monitor and manage your AI crews through a web interface
- **🔧 Rails Configuration**: Seamless integration with Rails configuration patterns

```ruby
# Gemfile
gem 'rcrewai-rails'

# config/routes.rb
Rails.application.routes.draw do
  mount RcrewAI::Rails::Engine, at: '/rcrewai'
end

# Generate a new crew
rails generate rcrew_ai:crew marketing_crew

# Create persistent agents and tasks through Rails models
crew = RcrewAI::Rails::Crew.create!(name: "Content Team", description: "AI content generation")
agent = crew.agents.create!(name: "writer", role: "Content Writer", goal: "Create engaging content")
```

Install rcrew RAILS: `gem install rcrewai-rails`

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## 📄 License

RCrewAI is released under the [MIT License](LICENSE).

## 📞 Support

- **Documentation**: [https://gkosmo.github.io/rcrewAI/](https://gkosmo.github.io/rcrewAI/)
- **Issues**: [GitHub Issues](https://github.com/gkosmo/rcrewAI/issues)
- **Discussions**: [GitHub Discussions](https://github.com/gkosmo/rcrewAI/discussions)

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=gkosmo/rcrewAI&type=Date)](https://star-history.com/#gkosmo/rcrewAI&Date)

---

Made with ❤️ by the RCrewAI community
