---
layout: example
title: Production-Ready Research Crew
description: A comprehensive example showing all features of RCrewAI in a production scenario
---

# Production-Ready Research Crew

This example demonstrates a fully-featured, production-ready crew that showcases all of RCrewAI's advanced capabilities including intelligent agents, tool usage, memory, error handling, and monitoring.

## Scenario

We'll build a comprehensive market research crew that:
1. Researches market trends using web search
2. Analyzes competitor data from files
3. Generates detailed reports with insights
4. Creates presentation materials
5. Monitors performance and handles errors

## Complete Implementation

```ruby
#!/usr/bin/env ruby

require 'rcrewai'
require 'logger'
require 'fileutils'

# Production logging setup
logger = Logger.new('crew_execution.log')
logger.level = Logger::INFO

puts "🚀 Starting Production Market Research Crew"
puts "=" * 50

# Configuration with error handling
begin
  RCrewAI.configure do |config|
    config.llm_provider = :openai  # Switch to :anthropic, :google as needed
    config.temperature = 0.1       # Low temperature for consistent results
    config.max_tokens = 2000       # Reasonable limit
    config.timeout = 120           # 2 minute timeout
  end
  
  puts "✅ LLM Configuration: #{RCrewAI.configuration.llm_provider} (#{RCrewAI.configuration.model})"
rescue RCrewAI::ConfigurationError => e
  puts "❌ Configuration failed: #{e.message}"
  puts "Please check your API key environment variables"
  exit 1
end

# Create output directory
FileUtils.mkdir_p('output/reports')
FileUtils.mkdir_p('output/presentations')

# Production-grade agents with comprehensive toolsets
market_researcher = RCrewAI::Agent.new(
  name: "market_researcher",
  role: "Senior Market Research Analyst",
  goal: "Conduct thorough market research and competitive analysis",
  backstory: "You are a seasoned market researcher with 15 years of experience in technology markets. You excel at finding reliable data sources, identifying market trends, and understanding competitive landscapes.",
  tools: [
    RCrewAI::Tools::WebSearch.new(max_results: 15, timeout: 45),
    RCrewAI::Tools::FileReader.new(
      max_file_size: 50_000_000,
      allowed_extensions: %w[.csv .json .txt .md .pdf]
    )
  ],
  verbose: true,
  max_iterations: 8,
  max_execution_time: 600,  # 10 minutes max
  allow_delegation: false
)

data_analyst = RCrewAI::Agent.new(
  name: "data_analyst", 
  role: "Senior Data Analyst",
  goal: "Analyze market data and extract actionable insights",
  backstory: "You are an expert data analyst specializing in market intelligence. You can identify patterns, trends, and opportunities from complex datasets and research findings.",
  tools: [
    RCrewAI::Tools::FileReader.new(
      allowed_extensions: %w[.csv .json .xlsx .txt]
    ),
    RCrewAI::Tools::FileWriter.new(
      allowed_extensions: %w[.json .csv .md .txt],
      create_directories: true
    )
  ],
  verbose: true,
  max_iterations: 6,
  allow_delegation: false
)

report_writer = RCrewAI::Agent.new(
  name: "report_writer",
  role: "Strategic Business Writer", 
  goal: "Create compelling, professional business reports and presentations",
  backstory: "You are an experienced business writer who creates executive-level reports and presentations. You excel at synthesizing complex information into clear, actionable recommendations.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new(
      max_file_size: 20_000_000,
      create_directories: true
    )
  ],
  verbose: true,
  max_iterations: 5,
  allow_delegation: true
)

# Create production crew
crew = RCrewAI::Crew.new("market_research_crew")
crew.add_agent(market_researcher)
crew.add_agent(data_analyst)
crew.add_agent(report_writer)

puts "👥 Crew created with #{crew.agents.length} agents"

# Define comprehensive tasks with callbacks and error handling

# Task 1: Market Research
market_research_task = RCrewAI::Task.new(
  name: "comprehensive_market_research",
  description: <<~DESC,
    Conduct comprehensive market research on the AI/ML tools market for 2024. 
    Focus on:
    1. Market size and growth projections
    2. Key players and their market share
    3. Emerging trends and technologies
    4. Customer segments and use cases
    5. Pricing models and strategies
    
    Use multiple search queries to gather comprehensive data.
  DESC
  agent: market_researcher,
  expected_output: "Detailed market research report with data sources, key findings, and market insights formatted as structured text with clear sections",
  max_retries: 3,
  callback: ->(task, result) {
    logger.info "Market research completed: #{result.length} characters"
    puts "📊 Market research phase completed"
  }
)

# Task 2: Data Analysis  
data_analysis_task = RCrewAI::Task.new(
  name: "market_data_analysis",
  description: <<~DESC,
    Analyze the market research findings to extract key insights and trends.
    Create structured analysis including:
    1. Market opportunity assessment
    2. Competitive positioning analysis  
    3. Risk and opportunity matrix
    4. Strategic recommendations
    5. Key metrics and KPIs
    
    Save analysis results to output/reports/market_analysis.json
  DESC
  agent: data_analyst,
  expected_output: "Structured market analysis saved to JSON file with clear categories, metrics, and actionable insights",
  context: [market_research_task],
  tools: [RCrewAI::Tools::FileWriter.new],
  callback: ->(task, result) {
    logger.info "Data analysis completed"
    puts "🔍 Data analysis phase completed"
  }
)

# Task 3: Executive Report
executive_report_task = RCrewAI::Task.new(
  name: "executive_report_creation",
  description: <<~DESC,
    Create a comprehensive executive report based on the market research and analysis.
    The report should include:
    1. Executive Summary (key findings and recommendations)
    2. Market Overview (size, growth, trends)
    3. Competitive Analysis (key players, positioning)
    4. Opportunities and Recommendations
    5. Risk Assessment
    6. Next Steps and Action Items
    
    Format as professional markdown and save to output/reports/executive_report.md
  DESC
  agent: report_writer,
  expected_output: "Professional executive report in markdown format, 2000-3000 words, saved to file",
  context: [market_research_task, data_analysis_task],
  callback: ->(task, result) {
    logger.info "Executive report created"
    puts "📝 Executive report completed"
  }
)

# Task 4: Presentation Materials
presentation_task = RCrewAI::Task.new(
  name: "presentation_creation", 
  description: <<~DESC,
    Create presentation slides content based on the executive report.
    Create slide-by-slide content for a 15-20 slide presentation including:
    1. Title slide
    2. Agenda
    3. Key findings (3-4 slides)
    4. Market analysis (3-4 slides)
    5. Competitive landscape (2-3 slides)
    6. Recommendations (2-3 slides)
    7. Next steps
    
    Save as structured markdown to output/presentations/market_research_presentation.md
  DESC
  agent: report_writer,
  expected_output: "Presentation content structured as slides, saved to markdown file with clear slide breaks and bullet points",
  context: [executive_report_task],
  async: false,  # Sequential execution
  callback: ->(task, result) {
    logger.info "Presentation materials created"
    puts "🎯 Presentation materials completed"
  }
)

# Add all tasks to crew
crew.add_task(market_research_task)
crew.add_task(data_analysis_task)  
crew.add_task(executive_report_task)
crew.add_task(presentation_task)

puts "📋 #{crew.tasks.length} tasks defined with dependencies"

# Execute with comprehensive monitoring
start_time = Time.now

begin
  puts "\n🎬 Starting crew execution..."
  puts "This may take several minutes as agents research and analyze..."
  
  # Execute the crew
  results = crew.execute
  
  execution_time = Time.now - start_time
  
  # Comprehensive results reporting
  puts "\n" + "="*60
  puts "🎉 EXECUTION COMPLETED SUCCESSFULLY"
  puts "="*60
  puts "Total execution time: #{execution_time.round(2)} seconds"
  
  # Task-by-task results
  crew.tasks.each do |task|
    puts "\n📌 Task: #{task.name}"
    puts "   Status: #{task.status}"
    puts "   Time: #{task.execution_time&.round(2)}s"
    puts "   Result size: #{task.result&.length || 0} characters"
    
    if task.failed?
      puts "   ❌ Error: #{task.result}"
      logger.error "Task #{task.name} failed: #{task.result}"
    else
      puts "   ✅ Success"
    end
  end
  
  # Memory and performance stats
  puts "\n🧠 Agent Memory Statistics:"
  crew.agents.each do |agent|
    stats = agent.memory.stats
    puts "   #{agent.name}:"
    puts "     Short-term memories: #{stats[:short_term_count]}"
    puts "     Long-term categories: #{stats[:long_term_types]}"
    puts "     Success rate: #{stats[:success_rate]}%"
    puts "     Tool usages: #{stats[:tool_usage_count]}"
  end
  
  # File outputs verification
  puts "\n📁 Generated Files:"
  output_files = [
    'output/reports/market_analysis.json',
    'output/reports/executive_report.md', 
    'output/presentations/market_research_presentation.md'
  ]
  
  output_files.each do |file|
    if File.exist?(file)
      size = File.size(file)
      puts "   ✅ #{file} (#{size} bytes)"
    else
      puts "   ❌ #{file} (not found)"
    end
  end
  
  puts "\n🎯 All deliverables completed successfully!"
  puts "Check the output/ directory for your market research results."
  
rescue RCrewAI::TaskExecutionError => e
  puts "\n❌ Task execution failed: #{e.message}"
  logger.error "Task execution error: #{e.message}"
  
rescue RCrewAI::AgentError => e
  puts "\n❌ Agent error: #{e.message}"
  logger.error "Agent error: #{e.message}"
  
rescue StandardError => e
  puts "\n💥 Unexpected error: #{e.message}"
  puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
  logger.error "Unexpected error: #{e.message}"
  logger.error e.backtrace.join("\n")
  
ensure
  # Cleanup and final logging
  total_time = Time.now - start_time
  logger.info "Crew execution finished in #{total_time.round(2)}s"
  puts "\n📊 Log file: crew_execution.log"
end

# Performance analysis
puts "\n⚡ Performance Analysis:"
puts "   Average task time: #{crew.tasks.map(&:execution_time).compact.sum / crew.tasks.length}s"
puts "   Fastest task: #{crew.tasks.map(&:execution_time).compact.min}s"
puts "   Slowest task: #{crew.tasks.map(&:execution_time).compact.max}s"

puts "\n🔚 Market Research Crew execution complete!"
```

## Running the Production Crew

### Prerequisites

1. **Set up environment variables**:
```bash
export OPENAI_API_KEY="your-openai-key"
# or
export ANTHROPIC_API_KEY="your-anthropic-key"
# or  
export GOOGLE_API_KEY="your-google-key"
```

2. **Install dependencies**:
```bash
bundle install
```

3. **Run the crew**:
```bash
ruby production_crew.rb
```

### Expected Output

The crew will generate:

```
output/
├── reports/
│   ├── market_analysis.json      # Structured data analysis
│   └── executive_report.md       # Professional report
└── presentations/
    └── market_research_presentation.md  # Slide content
```

### Console Output Example

```
🚀 Starting Production Market Research Crew
==================================================
✅ LLM Configuration: openai (gpt-4)
👥 Crew created with 3 agents
📋 4 tasks defined with dependencies

🎬 Starting crew execution...
This may take several minutes as agents research and analyze...

INFO Agent market_researcher starting task: comprehensive_market_research
DEBUG Iteration 1: Sending prompt to LLM
DEBUG Using tool: websearch with params: {:query=>"AI ML tools market 2024", :max_results=>15}
DEBUG Tool websearch result: Search Results:
1. AI/ML Market Size and Growth 2024
   URL: https://example.com/ai-market-report
   The AI/ML tools market is projected to reach $126 billion...

📊 Market research phase completed
📍 Data analysis phase completed  
📝 Executive report completed
🎯 Presentation materials completed

============================================================
🎉 EXECUTION COMPLETED SUCCESSFULLY
============================================================
Total execution time: 342.56 seconds

📌 Task: comprehensive_market_research
   Status: completed
   Time: 156.23s
   Result size: 8,432 characters
   ✅ Success

📌 Task: market_data_analysis
   Status: completed  
   Time: 89.45s
   Result size: 5,221 characters
   ✅ Success

📌 Task: executive_report_creation
   Status: completed
   Time: 67.33s
   Result size: 12,890 characters
   ✅ Success

📌 Task: presentation_creation
   Status: completed
   Time: 29.55s
   Result size: 6,778 characters
   ✅ Success

🧠 Agent Memory Statistics:
   market_researcher:
     Short-term memories: 4
     Long-term categories: 2
     Success rate: 100.0%
     Tool usages: 12

📁 Generated Files:
   ✅ output/reports/market_analysis.json (5,221 bytes)
   ✅ output/reports/executive_report.md (12,890 bytes)
   ✅ output/presentations/market_research_presentation.md (6,778 bytes)

🎯 All deliverables completed successfully!
Check the output/ directory for your market research results.

⚡ Performance Analysis:
   Average task time: 85.64s
   Fastest task: 29.55s
   Slowest task: 156.23s

🔚 Market Research Crew execution complete!
```

## Production Features Demonstrated

### 1. **Robust Configuration**
- Environment variable management
- Error handling for missing API keys
- Multiple LLM provider support

### 2. **Professional Agents**
- Specialized roles and expertise
- Comprehensive tool sets
- Performance limits and timeouts

### 3. **Advanced Task Management**
- Task dependencies and context sharing
- Retry logic with exponential backoff
- Callbacks for monitoring
- File output verification

### 4. **Error Handling & Recovery**
- Graceful error handling at all levels
- Comprehensive logging
- Cleanup procedures

### 5. **Monitoring & Analytics**
- Execution time tracking
- Memory usage statistics
- Performance analysis
- Success rate monitoring

### 6. **File Management**
- Structured output directories
- Multiple file formats (JSON, Markdown)
- File size validation
- Security controls

### 7. **Memory System**
- Agent learning from executions
- Tool usage patterns
- Performance optimization

This example demonstrates how RCrewAI can be used in production environments with proper error handling, monitoring, and output management. The crew produces professional-quality deliverables while maintaining robust performance and reliability.

## Customization Options

You can easily modify this example for different use cases:

- **Change research domain**: Modify task descriptions for different markets
- **Add more agents**: Include specialists like financial analysts, technical writers
- **Different output formats**: JSON reports, CSV data, PDF generation
- **Integration points**: Add database connections, API integrations, email notifications
- **Monitoring**: Add metrics collection, alerting, performance dashboards

The production-ready structure scales to handle complex, multi-agent workflows in enterprise environments.