#!/usr/bin/env ruby

require_relative '../lib/rcrewai'
require 'benchmark'

puts "⚡ Async Execution Example"
puts "=" * 50

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai  # Change as needed
  config.temperature = 0.1
end

puts "🔧 Setting up crew for async vs sync performance comparison..."

# Create a crew with multiple tasks that can benefit from parallelization
crew = RCrewAI::Crew.new("data_processing_crew")

# Create specialized agents
data_collector = RCrewAI::Agent.new(
  name: "data_collector",
  role: "Data Collection Specialist",
  goal: "Gather data from various sources efficiently",
  backstory: "You specialize in collecting and organizing data from multiple sources.",
  tools: [RCrewAI::Tools::WebSearch.new],
  verbose: true,
  max_iterations: 3
)

data_analyst = RCrewAI::Agent.new(
  name: "data_analyst",
  role: "Data Analyst", 
  goal: "Analyze collected data and extract insights",
  backstory: "You excel at finding patterns and insights in datasets.",
  tools: [RCrewAI::Tools::FileWriter.new],
  verbose: true,
  max_iterations: 4
)

report_writer = RCrewAI::Agent.new(
  name: "report_writer",
  role: "Technical Writer",
  goal: "Create comprehensive reports from analysis",
  backstory: "You transform complex analysis into clear, actionable reports.",
  tools: [RCrewAI::Tools::FileWriter.new, RCrewAI::Tools::FileReader.new],
  verbose: true,
  max_iterations: 3
)

code_reviewer = RCrewAI::Agent.new(
  name: "code_reviewer",
  role: "Code Quality Specialist", 
  goal: "Review and analyze code quality",
  backstory: "You ensure code meets quality standards and best practices.",
  tools: [RCrewAI::Tools::CodeExecutor.new, RCrewAI::Tools::FileReader.new],
  verbose: true,
  max_iterations: 4
)

# Add agents to crew
crew.add_agent(data_collector)
crew.add_agent(data_analyst) 
crew.add_agent(report_writer)
crew.add_agent(code_reviewer)

puts "👥 Created crew with #{crew.agents.length} specialized agents"

# Create tasks that can run independently (parallel execution potential)
data_collection_task1 = RCrewAI::Task.new(
  name: "collect_market_data",
  description: "Research current market trends in AI and machine learning for 2024",
  agent: data_collector,
  expected_output: "Market research summary with key trends and statistics",
  async: true
)

data_collection_task2 = RCrewAI::Task.new(
  name: "collect_tech_data", 
  description: "Research emerging technologies in software development",
  agent: data_collector,
  expected_output: "Technology research summary with key developments",
  async: true
)

# Analysis tasks that depend on data collection
analysis_task1 = RCrewAI::Task.new(
  name: "analyze_market_trends",
  description: "Analyze the collected market data to identify opportunities and threats",
  agent: data_analyst,
  expected_output: "Market analysis report with actionable insights saved to market_analysis.md",
  context: [data_collection_task1],
  async: true
)

analysis_task2 = RCrewAI::Task.new(
  name: "analyze_tech_trends",
  description: "Analyze emerging technology data to predict future developments",
  agent: data_analyst, 
  expected_output: "Technology trend analysis saved to tech_analysis.md",
  context: [data_collection_task2],
  async: true
)

# Code review task (independent)
code_review_task = RCrewAI::Task.new(
  name: "review_sample_code",
  description: "Review this Python code for best practices: 'def calculate(x, y): return x + y if x > 0 else 0'",
  agent: code_reviewer,
  expected_output: "Code review with suggestions for improvement",
  async: true
)

# Final report task (depends on all analysis)
final_report_task = RCrewAI::Task.new(
  name: "create_comprehensive_report",
  description: "Combine all analysis into a comprehensive business report with recommendations",
  agent: report_writer,
  expected_output: "Executive business report combining all insights saved to executive_report.md",
  context: [analysis_task1, analysis_task2, code_review_task],
  async: true
)

# Add all tasks to crew
crew.add_task(data_collection_task1)
crew.add_task(data_collection_task2) 
crew.add_task(analysis_task1)
crew.add_task(analysis_task2)
crew.add_task(code_review_task)
crew.add_task(final_report_task)

puts "📋 Created #{crew.tasks.length} tasks with dependency chains"

# Demonstrate both sync and async execution
puts "\n🔄 Comparing Synchronous vs Asynchronous Execution"
puts "-" * 60

# First: Synchronous execution
puts "\n1️⃣ SYNCHRONOUS EXECUTION"
puts "Tasks will execute sequentially, one at a time..."

sync_time = Benchmark.measure do
  sync_results = crew.execute
  
  puts "\n📊 Synchronous Results:"
  puts "  Process: #{sync_results[:process]}"
  puts "  Success Rate: #{sync_results[:success_rate]}%"
  puts "  Completed: #{sync_results[:completed_tasks]}/#{sync_results[:total_tasks]}"
  puts "  Failed: #{sync_results[:failed_tasks]}"
end

puts "⏱️  Synchronous execution time: #{sync_time.real.round(2)} seconds"

# Clear any previous results
crew.tasks.each do |task|
  task.instance_variable_set(:@result, nil)
  task.instance_variable_set(:@status, :pending)
end

puts "\n2️⃣ ASYNCHRONOUS EXECUTION" 
puts "Tasks will execute in parallel where possible..."

async_time = Benchmark.measure do
  async_results = crew.execute(
    async: true,
    max_concurrency: 4,  # Allow up to 4 concurrent tasks
    timeout: 300,        # 5 minute timeout
    verbose: true        # Show detailed async logs
  )
  
  puts "\n📊 Asynchronous Results:"
  puts "  Process: #{async_results[:process]}"
  puts "  Execution Mode: #{async_results[:execution_mode]}"
  puts "  Max Concurrency: #{async_results[:max_concurrency]}"
  puts "  Success Rate: #{async_results[:success_rate]}%"
  puts "  Completed: #{async_results[:completed_tasks]}/#{async_results[:total_tasks]}"
  puts "  Failed: #{async_results[:failed_tasks]}"
  puts "  Timeouts: #{async_results[:timed_out_tasks]}"
  
  if async_results[:thread_pool_stats]
    puts "  Thread Pool Stats:"
    puts "    Max Threads: #{async_results[:thread_pool_stats][:max_threads]}"
    puts "    Peak Usage: #{async_results[:thread_pool_stats][:largest_length]} threads"
  end
end

puts "⚡ Asynchronous execution time: #{async_time.real.round(2)} seconds"

# Performance comparison
puts "\n🏆 PERFORMANCE COMPARISON"
puts "=" * 40
speedup = sync_time.real / async_time.real
puts "Speedup: #{speedup.round(2)}x faster with async execution"
puts "Time saved: #{(sync_time.real - async_time.real).round(2)} seconds"

if speedup > 1.5
  puts "🚀 Significant performance improvement with async execution!"
elsif speedup > 1.2
  puts "✅ Good performance improvement with async execution"
else
  puts "ℹ️  Minimal performance difference (tasks may be I/O bound or have dependencies)"
end

# Show task execution patterns
puts "\n📈 TASK EXECUTION ANALYSIS"
puts "-" * 30

# Demonstrate hierarchical async execution
puts "\n3️⃣ HIERARCHICAL ASYNC EXECUTION"
puts "Manager will coordinate parallel task delegation..."

# Create a new crew with manager for hierarchical async
hierarchical_crew = RCrewAI::Crew.new("async_hierarchical_crew", process: :hierarchical)

# Add a manager
project_manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Project Coordinator",
  goal: "Coordinate team efforts efficiently",
  backstory: "You excel at managing parallel workstreams and ensuring optimal resource utilization.",
  manager: true,
  allow_delegation: true,
  verbose: true
)

hierarchical_crew.add_agent(project_manager)
hierarchical_crew.add_agent(data_collector)
hierarchical_crew.add_agent(data_analyst)
hierarchical_crew.add_agent(code_reviewer)

# Create simpler tasks for hierarchical demo
quick_tasks = [
  RCrewAI::Task.new(
    name: "quick_research",
    description: "Quick research on Ruby vs Python performance",
    expected_output: "Brief comparison summary"
  ),
  RCrewAI::Task.new(
    name: "quick_analysis", 
    description: "Analyze a simple dataset: [1,2,3,4,5]",
    expected_output: "Basic statistical analysis"
  ),
  RCrewAI::Task.new(
    name: "quick_code_check",
    description: "Review this Ruby code: 'arr.map(&:to_i).sum'",
    expected_output: "Code quality assessment"
  )
]

quick_tasks.each { |task| hierarchical_crew.add_task(task) }

hierarchical_time = Benchmark.measure do
  hierarchical_results = hierarchical_crew.execute(
    async: true,
    max_concurrency: 3,
    verbose: true
  )
  
  puts "\n📊 Hierarchical Async Results:"
  puts "  Manager: #{hierarchical_results[:manager]}"
  puts "  Process: #{hierarchical_results[:process]}" 
  puts "  Success Rate: #{hierarchical_results[:success_rate]}%"
  puts "  Tasks Completed: #{hierarchical_results[:completed_tasks]}/#{hierarchical_results[:total_tasks]}"
end

puts "🏗️  Hierarchical async execution time: #{hierarchical_time.real.round(2)} seconds"

# Check generated files
puts "\n📄 GENERATED FILES"
output_files = [
  'market_analysis.md',
  'tech_analysis.md', 
  'executive_report.md'
]

output_files.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file} (#{File.size(file)} bytes)"
  else
    puts "  ❌ #{file} (not generated)"
  end
end

puts "\n🎯 ASYNC EXECUTION BENEFITS DEMONSTRATED:"
puts "  • Parallel task processing where dependencies allow"
puts "  • Efficient resource utilization with thread pooling"
puts "  • Manager coordination in hierarchical async mode"
puts "  • Automatic dependency resolution across phases"
puts "  • Timeout and error handling for robust execution"
puts "  • Detailed performance metrics and monitoring"

puts "\n" + "=" * 50
puts "⚡ Async Execution Demo Complete!"
puts "=" * 50