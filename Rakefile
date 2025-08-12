# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

# Default task
task default: [:spec, :rubocop]

# RSpec task
RSpec::Core::RakeTask.new(:spec) do |task|
  task.rspec_opts = "--color --format documentation"
end

# RuboCop task
RuboCop::RakeTask.new do |task|
  task.options = ["--display-cop-names", "--display-style-guide"]
end

# Test with coverage
desc "Run specs with coverage report"
task :spec_coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end

# Clean coverage files
desc "Clean coverage files"
task :clean_coverage do
  FileUtils.rm_rf("coverage/")
end

# Build and install gem locally
desc "Build and install gem locally"
task :install_local do
  sh "gem build rcrewai.gemspec"
  sh "gem install rcrewai-*.gem"
  FileUtils.rm(Dir.glob("rcrewai-*.gem"))
end

# Run all tests and checks
desc "Run all tests and code quality checks"
task :ci do
  puts "Running RSpec tests..."
  Rake::Task[:spec].invoke
  
  puts "\nRunning RuboCop..."
  Rake::Task[:rubocop].invoke
  
  puts "\nAll checks passed! ✅"
end

# Console task for development
desc "Start interactive console with gem loaded"
task :console do
  require "irb"
  require_relative "lib/rcrewai"
  IRB.start
end

# Generate documentation
desc "Generate documentation"
task :docs do
  sh "yard doc lib/**/*.rb"
  puts "Documentation generated in doc/ directory"
end

# Benchmark task
desc "Run performance benchmarks"
task :benchmark do
  require_relative "lib/rcrewai"
  
  # Simple benchmark example
  require "benchmark"
  
  RCrewAI.configure do |config|
    config.llm_provider = :openai
    config.api_key = "test-key"
  end
  
  agent = RCrewAI::Agent.new(
    name: "benchmark_agent",
    role: "Test Agent",
    goal: "Run benchmarks"
  )
  
  task = RCrewAI::Task.new(
    name: "benchmark_task",
    description: "Test task",
    agent: agent
  )
  
  crew = RCrewAI::Crew.new("benchmark_crew")
  crew.add_agent(agent)
  crew.add_task(task)
  
  puts "\nBenchmarking crew creation and setup..."
  result = Benchmark.measure do
    100.times do
      test_crew = RCrewAI::Crew.new("test_#{rand(1000)}")
      test_agent = RCrewAI::Agent.new(
        name: "test_agent",
        role: "Test Agent",
        goal: "Test performance"
      )
      test_crew.add_agent(test_agent)
    end
  end
  
  puts "Created 100 crews with agents in: #{result.real.round(4)}s"
end

# Development setup
desc "Set up development environment"
task :setup do
  puts "Setting up development environment..."
  
  # Install dependencies
  sh "bundle install"
  
  # Create necessary directories
  FileUtils.mkdir_p("spec/vcr_cassettes") unless Dir.exist?("spec/vcr_cassettes")
  FileUtils.mkdir_p("coverage") unless Dir.exist?("coverage")
  FileUtils.mkdir_p("doc") unless Dir.exist?("doc")
  
  puts "\n✅ Development environment set up successfully!"
  puts "\nRun 'rake spec' to run tests"
  puts "Run 'rake console' to start an interactive session"
  puts "Run 'rake ci' to run all checks"
end