---
layout: tutorial
title: Working with Multiple Crews
description: Learn how to coordinate multiple AI crews for complex, multi-phase operations and large-scale workflows
---

# Working with Multiple Crews

This tutorial demonstrates how to work with multiple crews to handle complex, multi-phase operations that require different specialized teams working together. You'll learn crew coordination, inter-crew communication, resource sharing, and orchestration patterns.

## Table of Contents
1. [Understanding Multi-Crew Architecture](#understanding-multi-crew-architecture)
2. [Crew Coordination Patterns](#crew-coordination-patterns)
3. [Sequential Crew Execution](#sequential-crew-execution)
4. [Parallel Crew Operations](#parallel-crew-operations)
5. [Resource Sharing Between Crews](#resource-sharing-between-crews)
6. [Cross-Crew Communication](#cross-crew-communication)
7. [Orchestration Strategies](#orchestration-strategies)
8. [Production Multi-Crew Systems](#production-multi-crew-systems)

## Understanding Multi-Crew Architecture

Multiple crews are useful when you have distinct phases or domains that require different specialized teams.

### When to Use Multiple Crews

- **Phase-based workflows**: Development → Testing → Deployment
- **Domain separation**: Research → Engineering → Marketing
- **Scale requirements**: Multiple independent operations
- **Resource optimization**: Different crews need different resources
- **Fault isolation**: Failures in one crew don't affect others

### Basic Multi-Crew Setup

```ruby
require 'rcrewai'

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.temperature = 0.3
end

# ===== RESEARCH CREW =====
research_crew = RCrewAI::Crew.new("research_team")

market_researcher = RCrewAI::Agent.new(
  name: "market_researcher",
  role: "Market Research Analyst",
  goal: "Gather comprehensive market intelligence and consumer insights",
  backstory: "Expert analyst with deep knowledge of market trends and consumer behavior.",
  tools: [RCrewAI::Tools::WebSearch.new]
)

trend_analyst = RCrewAI::Agent.new(
  name: "trend_analyst", 
  role: "Trend Analysis Specialist",
  goal: "Identify emerging trends and forecast market direction",
  backstory: "Specialist in trend analysis with predictive modeling expertise.",
  tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileReader.new]
)

research_crew.add_agent(market_researcher)
research_crew.add_agent(trend_analyst)

# ===== DEVELOPMENT CREW =====
dev_crew = RCrewAI::Crew.new("development_team", process: :hierarchical)

tech_lead = RCrewAI::Agent.new(
  name: "tech_lead",
  role: "Technical Lead",
  goal: "Coordinate development efforts and ensure technical excellence",
  backstory: "Senior technical leader with expertise in system architecture and team coordination.",
  manager: true,
  allow_delegation: true,
  tools: [RCrewAI::Tools::FileWriter.new]
)

senior_developer = RCrewAI::Agent.new(
  name: "senior_developer",
  role: "Senior Software Developer", 
  goal: "Build robust and scalable software solutions",
  backstory: "Experienced developer skilled in multiple programming languages and frameworks.",
  tools: [RCrewAI::Tools::FileWriter.new, RCrewAI::Tools::FileReader.new]
)

dev_crew.add_agent(tech_lead)
dev_crew.add_agent(senior_developer)
```

## Crew Coordination Patterns

### 1. Pipeline Pattern (Sequential)

Crews execute one after another, passing results downstream:

```ruby
class CrewPipeline
  def initialize(*crews)
    @crews = crews
    @pipeline_results = []
  end
  
  def execute(initial_data = {})
    current_data = initial_data
    
    @crews.each_with_index do |crew, index|
      puts "🚀 Executing pipeline stage #{index + 1}: #{crew.name}"
      
      # Pass previous results as context
      if index > 0
        crew.add_shared_context(@pipeline_results[index - 1])
      end
      
      # Execute crew
      stage_result = crew.execute
      @pipeline_results << stage_result
      
      # Transform result for next stage
      current_data = transform_for_next_stage(stage_result, index)
      
      puts "✅ Stage #{index + 1} completed"
    end
    
    {
      pipeline_results: @pipeline_results,
      final_result: current_data,
      success_rate: calculate_success_rate
    }
  end
  
  private
  
  def transform_for_next_stage(result, stage_index)
    # Transform data between pipeline stages
    {
      stage: stage_index + 1,
      previous_result: result,
      timestamp: Time.now
    }
  end
  
  def calculate_success_rate
    successful = @pipeline_results.count { |r| r[:success_rate] > 80 }
    (successful.to_f / @pipeline_results.length * 100).round(1)
  end
end

# Usage
pipeline = CrewPipeline.new(research_crew, dev_crew)
results = pipeline.execute(project_requirements: "Build AI-powered analytics dashboard")
```

### 2. Fan-Out Pattern (Parallel)

Multiple crews work on different aspects simultaneously:

```ruby
class ParallelCrewOrchestrator
  def initialize
    @crews = []
    @execution_threads = []
  end
  
  def add_crew(crew, priority: :normal)
    @crews << { crew: crew, priority: priority }
  end
  
  def execute_parallel(max_concurrency: 3)
    puts "🚀 Starting parallel execution of #{@crews.length} crews"
    
    # Sort by priority
    sorted_crews = @crews.sort_by do |crew_config|
      priority_order = { high: 0, normal: 1, low: 2 }
      priority_order[crew_config[:priority]]
    end
    
    results = {}
    
    # Execute crews in batches
    sorted_crews.each_slice(max_concurrency) do |crew_batch|
      threads = crew_batch.map do |crew_config|
        Thread.new do
          crew = crew_config[:crew]
          
          begin
            puts "   Starting crew: #{crew.name}"
            start_time = Time.now
            
            result = crew.execute
            duration = Time.now - start_time
            
            {
              crew_name: crew.name,
              success: true,
              result: result,
              duration: duration,
              priority: crew_config[:priority]
            }
          rescue => e
            {
              crew_name: crew.name,
              success: false,
              error: e.message,
              duration: Time.now - start_time
            }
          end
        end
      end
      
      # Wait for batch to complete
      threads.each do |thread|
        result = thread.value
        results[result[:crew_name]] = result
        
        status = result[:success] ? "✅" : "❌"
        puts "   #{status} #{result[:crew_name]} completed in #{result[:duration].round(2)}s"
      end
    end
    
    results
  end
end

# Create specialized crews
content_crew = RCrewAI::Crew.new("content_creation")
seo_crew = RCrewAI::Crew.new("seo_optimization") 
social_media_crew = RCrewAI::Crew.new("social_media")

# Setup orchestrator
orchestrator = ParallelCrewOrchestrator.new
orchestrator.add_crew(content_crew, priority: :high)
orchestrator.add_crew(seo_crew, priority: :normal)
orchestrator.add_crew(social_media_crew, priority: :low)

# Execute all crews in parallel
parallel_results = orchestrator.execute_parallel(max_concurrency: 2)
```

## Sequential Crew Execution

Complex workflows often require sequential execution with data flow between crews:

```ruby
# ===== E-COMMERCE LAUNCH PIPELINE =====

# Crew 1: Market Research
research_crew = RCrewAI::Crew.new("market_research")

research_crew.add_agent(RCrewAI::Agent.new(
  name: "market_analyst",
  role: "Market Research Analyst", 
  goal: "Analyze market opportunity and customer segments",
  tools: [RCrewAI::Tools::WebSearch.new]
))

research_task = RCrewAI::Task.new(
  name: "market_analysis",
  description: "Conduct comprehensive market research for new e-commerce platform. Analyze target demographics, competition, pricing strategies, and market size.",
  expected_output: "Detailed market analysis report with customer personas, competitive landscape, and go-to-market recommendations"
)

research_crew.add_task(research_task)

# Crew 2: Product Development  
product_crew = RCrewAI::Crew.new("product_development")

product_crew.add_agent(RCrewAI::Agent.new(
  name: "product_manager",
  role: "Product Manager",
  goal: "Define product requirements based on market research",
  tools: [RCrewAI::Tools::FileWriter.new]
))

product_crew.add_agent(RCrewAI::Agent.new(
  name: "ux_designer", 
  role: "UX Designer",
  goal: "Design user experience based on customer insights",
  tools: [RCrewAI::Tools::FileWriter.new]
))

product_task = RCrewAI::Task.new(
  name: "product_specification",
  description: "Based on market research findings, create detailed product specifications and user experience designs for the e-commerce platform.",
  expected_output: "Product requirements document with feature specifications, user journeys, and design wireframes"
)

product_crew.add_task(product_task)

# Crew 3: Technical Implementation
tech_crew = RCrewAI::Crew.new("technical_team", process: :hierarchical)

tech_lead = RCrewAI::Agent.new(
  name: "tech_lead",
  role: "Technical Lead",
  goal: "Coordinate technical implementation",
  manager: true,
  allow_delegation: true,
  tools: [RCrewAI::Tools::FileWriter.new]
)

backend_dev = RCrewAI::Agent.new(
  name: "backend_developer",
  role: "Backend Developer", 
  goal: "Build scalable backend systems",
  tools: [RCrewAI::Tools::FileWriter.new]
)

tech_crew.add_agent(tech_lead)
tech_crew.add_agent(backend_dev)

tech_task = RCrewAI::Task.new(
  name: "technical_implementation",
  description: "Implement the e-commerce platform based on product specifications. Build API, database, and core functionality.",
  expected_output: "Working e-commerce platform with API documentation and deployment guide"
)

tech_crew.add_task(tech_task)

# Sequential Execution with Data Flow
class ECommerceOrchestrator
  def initialize(research_crew, product_crew, tech_crew)
    @research_crew = research_crew
    @product_crew = product_crew
    @tech_crew = tech_crew
    @execution_log = []
  end
  
  def execute_launch_pipeline
    puts "🚀 Starting E-commerce Launch Pipeline"
    puts "="*50
    
    # Phase 1: Market Research
    log_phase("Market Research Phase")
    research_results = @research_crew.execute
    
    @execution_log << {
      phase: "research",
      crew: @research_crew.name,
      results: research_results,
      timestamp: Time.now
    }
    
    # Phase 2: Product Development (uses research data)
    log_phase("Product Development Phase")
    
    # Pass research context to product crew
    research_context = extract_key_insights(research_results)
    @product_crew.add_shared_context(research_context)
    
    product_results = @product_crew.execute
    
    @execution_log << {
      phase: "product",
      crew: @product_crew.name, 
      results: product_results,
      context_from: "research",
      timestamp: Time.now
    }
    
    # Phase 3: Technical Implementation (uses product specs)
    log_phase("Technical Implementation Phase")
    
    # Pass product specs to tech crew  
    product_context = extract_technical_requirements(product_results)
    @tech_crew.add_shared_context(product_context)
    
    tech_results = @tech_crew.execute
    
    @execution_log << {
      phase: "technical",
      crew: @tech_crew.name,
      results: tech_results,
      context_from: "product",
      timestamp: Time.now
    }
    
    # Generate final report
    generate_launch_report
  end
  
  private
  
  def log_phase(phase_name)
    puts "\n🎯 #{phase_name}"
    puts "-" * phase_name.length
  end
  
  def extract_key_insights(research_results)
    # Extract actionable insights for product team
    {
      target_customers: "Extract customer personas from research",
      market_size: "Extract market opportunity data", 
      competitive_analysis: "Extract competitive insights",
      pricing_strategy: "Extract pricing recommendations"
    }
  end
  
  def extract_technical_requirements(product_results)
    # Extract technical requirements for development team
    {
      feature_list: "Extract feature specifications",
      performance_requirements: "Extract performance criteria",
      integration_needs: "Extract third-party integrations",
      scalability_targets: "Extract scaling requirements"
    }
  end
  
  def generate_launch_report
    puts "\n📊 LAUNCH PIPELINE COMPLETED"
    puts "="*50
    
    total_duration = @execution_log.last[:timestamp] - @execution_log.first[:timestamp]
    
    puts "Total Execution Time: #{total_duration.round(2)} seconds"
    puts "Phases Completed: #{@execution_log.length}"
    
    @execution_log.each_with_index do |phase, index|
      success_rate = phase[:results][:success_rate] || 0
      status = success_rate > 80 ? "✅" : "⚠️"
      
      puts "#{index + 1}. #{status} #{phase[:phase].capitalize} Phase (#{phase[:crew]})"
      puts "   Success Rate: #{success_rate}%"
      puts "   Context: #{phase[:context_from] || 'None'}"
    end
    
    # Save comprehensive report
    save_launch_report
  end
  
  def save_launch_report
    report = {
      pipeline: "E-commerce Launch",
      execution_log: @execution_log,
      summary: {
        phases: @execution_log.length,
        overall_success: @execution_log.all? { |p| p[:results][:success_rate] > 80 },
        total_crews: 3
      }
    }
    
    File.write("ecommerce_launch_report.json", JSON.pretty_generate(report))
    puts "\n💾 Launch report saved: ecommerce_launch_report.json"
  end
end

# Execute the complete pipeline
orchestrator = ECommerceOrchestrator.new(research_crew, product_crew, tech_crew)
orchestrator.execute_launch_pipeline
```

## Parallel Crew Operations

When crews can work independently, parallel execution dramatically improves performance:

```ruby
# ===== CONTENT MARKETING CAMPAIGN =====

# Multiple specialized crews working in parallel
class ContentMarketingCampaign
  def initialize
    @crews = {}
    @shared_resources = {
      brand_guidelines: "Brand voice and style guidelines",
      target_audience: "Target customer personas",
      campaign_theme: "Q4 Holiday Campaign"
    }
  end
  
  def setup_crews
    # Content Creation Crew
    @crews[:content] = create_content_crew
    
    # SEO Optimization Crew  
    @crews[:seo] = create_seo_crew
    
    # Social Media Crew
    @crews[:social] = create_social_crew
    
    # Email Marketing Crew
    @crews[:email] = create_email_crew
    
    # Analytics Crew
    @crews[:analytics] = create_analytics_crew
  end
  
  def execute_campaign
    puts "🚀 Launching Multi-Crew Content Marketing Campaign"
    puts "Crews: #{@crews.keys.join(', ')}"
    puts "="*60
    
    # Execute crews in parallel with different priorities
    parallel_executor = ThreadPoolExecutor.new(max_threads: 3)
    
    futures = {}
    
    @crews.each do |crew_type, crew|
      futures[crew_type] = parallel_executor.submit do
        execute_crew_with_monitoring(crew_type, crew)
      end
    end
    
    # Wait for all crews to complete
    results = {}
    futures.each do |crew_type, future|
      results[crew_type] = future.value
    end
    
    parallel_executor.shutdown
    
    # Analyze cross-crew results
    analyze_campaign_results(results)
  end
  
  private
  
  def create_content_crew
    crew = RCrewAI::Crew.new("content_creation")
    
    content_strategist = RCrewAI::Agent.new(
      name: "content_strategist",
      role: "Content Strategy Lead",
      goal: "Create compelling content that drives engagement and conversions",
      tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileWriter.new]
    )
    
    copywriter = RCrewAI::Agent.new(
      name: "copywriter", 
      role: "Senior Copywriter",
      goal: "Write persuasive copy that connects with target audience",
      tools: [RCrewAI::Tools::FileWriter.new]
    )
    
    crew.add_agent(content_strategist)
    crew.add_agent(copywriter)
    
    # Add shared context
    crew.add_shared_context(@shared_resources)
    
    # Content tasks
    crew.add_task(RCrewAI::Task.new(
      name: "blog_content",
      description: "Create 5 high-quality blog posts for Q4 campaign",
      expected_output: "5 blog posts with SEO optimization and engagement hooks",
      async: true
    ))
    
    crew.add_task(RCrewAI::Task.new(
      name: "landing_pages",
      description: "Create compelling landing page copy for campaign",
      expected_output: "Landing page copy with clear CTAs and value propositions",
      async: true
    ))
    
    crew
  end
  
  def create_seo_crew
    crew = RCrewAI::Crew.new("seo_optimization")
    
    seo_specialist = RCrewAI::Agent.new(
      name: "seo_specialist",
      role: "SEO Specialist",
      goal: "Optimize content for maximum organic visibility",
      tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileReader.new]
    )
    
    crew.add_agent(seo_specialist)
    crew.add_shared_context(@shared_resources)
    
    crew.add_task(RCrewAI::Task.new(
      name: "keyword_research",
      description: "Research high-value keywords for Q4 campaign",
      expected_output: "Keyword strategy with search volumes and competition analysis",
      async: true
    ))
    
    crew.add_task(RCrewAI::Task.new(
      name: "content_optimization",
      description: "Optimize existing content for SEO best practices",
      expected_output: "SEO-optimized content with meta descriptions and schema markup",
      async: true
    ))
    
    crew
  end
  
  def create_social_crew
    crew = RCrewAI::Crew.new("social_media")
    
    social_manager = RCrewAI::Agent.new(
      name: "social_manager",
      role: "Social Media Manager", 
      goal: "Create engaging social content that drives community growth",
      tools: [RCrewAI::Tools::FileWriter.new]
    )
    
    crew.add_agent(social_manager)
    crew.add_shared_context(@shared_resources)
    
    crew.add_task(RCrewAI::Task.new(
      name: "social_content",
      description: "Create 30 days of social media content for multiple platforms",
      expected_output: "Social media calendar with platform-specific content and hashtags",
      async: true
    ))
    
    crew
  end
  
  def create_email_crew
    crew = RCrewAI::Crew.new("email_marketing")
    
    email_specialist = RCrewAI::Agent.new(
      name: "email_specialist",
      role: "Email Marketing Specialist",
      goal: "Create high-converting email campaigns",
      tools: [RCrewAI::Tools::FileWriter.new]
    )
    
    crew.add_agent(email_specialist)
    crew.add_shared_context(@shared_resources)
    
    crew.add_task(RCrewAI::Task.new(
      name: "email_sequence",
      description: "Create automated email sequence for Q4 campaign",
      expected_output: "Email sequence with subject lines, templates, and automation rules",
      async: true
    ))
    
    crew
  end
  
  def create_analytics_crew
    crew = RCrewAI::Crew.new("analytics_tracking")
    
    data_analyst = RCrewAI::Agent.new(
      name: "data_analyst",
      role: "Marketing Data Analyst",
      goal: "Set up tracking and measurement for campaign success",
      tools: [RCrewAI::Tools::FileWriter.new]
    )
    
    crew.add_agent(data_analyst)
    crew.add_shared_context(@shared_resources)
    
    crew.add_task(RCrewAI::Task.new(
      name: "tracking_setup",
      description: "Set up comprehensive tracking for all campaign channels",
      expected_output: "Analytics setup guide with KPIs, tracking codes, and dashboards",
      async: true
    ))
    
    crew
  end
  
  def execute_crew_with_monitoring(crew_type, crew)
    start_time = Time.now
    
    puts "🔄 Starting #{crew_type} crew..."
    
    begin
      results = crew.execute
      duration = Time.now - start_time
      
      puts "✅ #{crew_type} crew completed in #{duration.round(2)}s"
      
      {
        crew_type: crew_type,
        success: true,
        results: results,
        duration: duration,
        crew_name: crew.name
      }
    rescue => e
      duration = Time.now - start_time
      
      puts "❌ #{crew_type} crew failed: #{e.message}"
      
      {
        crew_type: crew_type,
        success: false,
        error: e.message,
        duration: duration,
        crew_name: crew.name
      }
    end
  end
  
  def analyze_campaign_results(results)
    puts "\n📊 CAMPAIGN EXECUTION RESULTS"
    puts "="*50
    
    successful_crews = results.values.count { |r| r[:success] }
    total_duration = results.values.map { |r| r[:duration] }.max
    
    puts "Success Rate: #{successful_crews}/#{results.length} crews (#{(successful_crews.to_f/results.length*100).round(1)}%)"
    puts "Total Duration: #{total_duration.round(2)} seconds (parallel execution)"
    puts "Sequential Duration: #{results.values.sum { |r| r[:duration] }.round(2)} seconds (estimated)"
    puts "Time Saved: #{((results.values.sum { |r| r[:duration] } - total_duration) / results.values.sum { |r| r[:duration] } * 100).round(1)}%"
    
    puts "\nCrew Performance:"
    results.each do |crew_type, result|
      status = result[:success] ? "✅" : "❌"
      puts "  #{status} #{crew_type.to_s.capitalize}: #{result[:duration].round(2)}s"
      
      if result[:success]
        success_rate = result[:results][:success_rate] || 0
        puts "    Success Rate: #{success_rate}%"
        puts "    Tasks: #{result[:results][:completed_tasks] || 0}/#{result[:results][:total_tasks] || 0}"
      else
        puts "    Error: #{result[:error]}"
      end
    end
    
    # Save campaign results
    campaign_report = {
      campaign: "Q4 Content Marketing",
      execution_type: "parallel",
      crews: results,
      summary: {
        success_rate: (successful_crews.to_f/results.length*100).round(1),
        total_duration: total_duration,
        time_saved_percentage: ((results.values.sum { |r| r[:duration] } - total_duration) / results.values.sum { |r| r[:duration] } * 100).round(1)
      }
    }
    
    File.write("campaign_results.json", JSON.pretty_generate(campaign_report))
    puts "\n💾 Campaign report saved: campaign_results.json"
  end
end

# Thread pool executor for parallel crew execution
class ThreadPoolExecutor
  def initialize(max_threads: 5)
    @max_threads = max_threads
    @threads = []
  end
  
  def submit(&block)
    Future.new(&block).tap do |future|
      if @threads.length < @max_threads
        thread = Thread.new { future.execute }
        @threads << thread
      else
        # Wait for a thread to finish
        @threads.first.join
        @threads.shift
        thread = Thread.new { future.execute }
        @threads << thread
      end
    end
  end
  
  def shutdown
    @threads.each(&:join)
  end
end

class Future
  def initialize(&block)
    @block = block
    @executed = false
    @result = nil
    @error = nil
  end
  
  def execute
    return if @executed
    
    begin
      @result = @block.call
    rescue => e
      @error = e
    ensure
      @executed = true
    end
  end
  
  def value
    return @result if @executed && @error.nil?
    raise @error if @error
    @result
  end
end

# Execute the campaign
campaign = ContentMarketingCampaign.new
campaign.setup_crews
campaign.execute_campaign
```

## Resource Sharing Between Crews

Crews can share resources, data, and configurations:

```ruby
class SharedResourceManager
  def initialize
    @shared_data = {}
    @resource_locks = {}
  end
  
  def store_resource(key, value, crew_name)
    @shared_data[key] = {
      value: value,
      created_by: crew_name,
      created_at: Time.now,
      accessed_by: []
    }
    
    puts "📦 Resource '#{key}' stored by #{crew_name}"
  end
  
  def get_resource(key, crew_name)
    return nil unless @shared_data[key]
    
    resource = @shared_data[key]
    resource[:accessed_by] << crew_name unless resource[:accessed_by].include?(crew_name)
    
    puts "📤 Resource '#{key}' accessed by #{crew_name}"
    resource[:value]
  end
  
  def lock_resource(key, crew_name)
    @resource_locks[key] = crew_name
    puts "🔒 Resource '#{key}' locked by #{crew_name}"
  end
  
  def unlock_resource(key, crew_name)
    if @resource_locks[key] == crew_name
      @resource_locks.delete(key)
      puts "🔓 Resource '#{key}' unlocked by #{crew_name}"
    end
  end
  
  def resource_stats
    @shared_data.each do |key, resource|
      puts "Resource: #{key}"
      puts "  Created by: #{resource[:created_by]}"
      puts "  Accessed by: #{resource[:accessed_by].join(', ')}"
      puts "  Created at: #{resource[:created_at]}"
      puts
    end
  end
end

# Global resource manager
$resource_manager = SharedResourceManager.new

# Enhanced crew with resource sharing
class ResourceAwareCrew < RCrewAI::Crew
  def initialize(name, **options)
    super
    @resource_manager = $resource_manager
  end
  
  def share_resource(key, value)
    @resource_manager.store_resource(key, value, @name)
  end
  
  def get_shared_resource(key)
    @resource_manager.get_resource(key, @name)
  end
  
  def execute_with_resources
    puts "🚀 #{@name} starting execution with shared resources"
    
    # Get shared resources before execution
    setup_shared_context
    
    # Execute normally
    results = execute
    
    # Share results with other crews
    share_execution_results(results)
    
    results
  end
  
  private
  
  def setup_shared_context
    # Get available shared resources
    shared_config = get_shared_resource("global_config")
    shared_data = get_shared_resource("processed_data")
    
    if shared_config
      add_shared_context(shared_config)
    end
    
    if shared_data
      add_shared_context({ shared_data: shared_data })
    end
  end
  
  def share_execution_results(results)
    # Share key results with other crews
    share_resource("#{@name}_results", {
      success_rate: results[:success_rate],
      key_outputs: extract_key_outputs(results),
      execution_time: Time.now
    })
  end
  
  def extract_key_outputs(results)
    # Extract the most useful outputs for other crews
    results[:results]&.map { |r| r[:result] }&.join("\n\n")[0..500] || ""
  end
end

# Example: Product Launch with Resource Sharing
research_crew = ResourceAwareCrew.new("market_research")
development_crew = ResourceAwareCrew.new("product_development")
marketing_crew = ResourceAwareCrew.new("marketing_launch")

# Share global configuration
$resource_manager.store_resource("global_config", {
  product_name: "AI Analytics Platform",
  target_market: "B2B SaaS",
  launch_date: "2024-Q2",
  budget: "$500K"
}, "orchestrator")

# Execute crews with resource sharing
puts "🌐 Multi-Crew Product Launch with Resource Sharing"
puts "="*60

# Research phase shares market data
research_results = research_crew.execute_with_resources

# Development phase uses market data
development_results = development_crew.execute_with_resources  

# Marketing phase uses both previous results
marketing_results = marketing_crew.execute_with_resources

# Show resource usage
puts "\n📊 SHARED RESOURCE STATISTICS"
puts "-"*40
$resource_manager.resource_stats
```

## Cross-Crew Communication

Enable crews to communicate and coordinate during execution:

```ruby
class CrewCommunicationHub
  def initialize
    @message_queues = {}
    @subscriptions = {}
    @message_history = []
  end
  
  def register_crew(crew_name)
    @message_queues[crew_name] = []
    @subscriptions[crew_name] = []
  end
  
  def subscribe(subscriber_crew, publisher_crew, message_types: :all)
    @subscriptions[subscriber_crew] << {
      publisher: publisher_crew,
      message_types: message_types
    }
    
    puts "📞 #{subscriber_crew} subscribed to #{publisher_crew}"
  end
  
  def send_message(from_crew, to_crew, message_type, content)
    message = {
      from: from_crew,
      to: to_crew,
      type: message_type,
      content: content,
      timestamp: Time.now,
      id: SecureRandom.uuid[0..8]
    }
    
    @message_queues[to_crew] << message
    @message_history << message
    
    puts "💌 Message sent from #{from_crew} to #{to_crew}: #{message_type}"
    
    # Notify subscribers
    notify_subscribers(message)
  end
  
  def broadcast_message(from_crew, message_type, content)
    @message_queues.keys.each do |crew_name|
      next if crew_name == from_crew
      send_message(from_crew, crew_name, message_type, content)
    end
  end
  
  def get_messages(crew_name)
    messages = @message_queues[crew_name] || []
    @message_queues[crew_name] = []  # Clear after reading
    messages
  end
  
  def get_messages_by_type(crew_name, message_type)
    get_messages(crew_name).select { |m| m[:type] == message_type }
  end
  
  private
  
  def notify_subscribers(message)
    @subscriptions.each do |subscriber, subscriptions|
      subscriptions.each do |sub|
        if sub[:publisher] == message[:from]
          if sub[:message_types] == :all || sub[:message_types].include?(message[:type])
            @message_queues[subscriber] << message.merge(subscription: true)
          end
        end
      end
    end
  end
end

# Global communication hub
$comm_hub = CrewCommunicationHub.new

class CommunicatingCrew < RCrewAI::Crew
  def initialize(name, **options)
    super
    @comm_hub = $comm_hub
    @comm_hub.register_crew(@name)
  end
  
  def send_message(to_crew, message_type, content)
    @comm_hub.send_message(@name, to_crew, message_type, content)
  end
  
  def broadcast(message_type, content)
    @comm_hub.broadcast_message(@name, message_type, content)
  end
  
  def get_messages(type: nil)
    if type
      @comm_hub.get_messages_by_type(@name, type)
    else
      @comm_hub.get_messages(@name)
    end
  end
  
  def subscribe_to(other_crew, message_types: :all)
    @comm_hub.subscribe(@name, other_crew, message_types: message_types)
  end
  
  def execute_with_communication
    puts "🚀 #{@name} starting execution with communication enabled"
    
    # Check for incoming messages before execution
    process_incoming_messages
    
    # Notify others of start
    broadcast(:status, "Starting execution")
    
    # Execute with periodic message checking
    results = execute_with_message_monitoring
    
    # Notify completion
    broadcast(:completion, {
      success_rate: results[:success_rate],
      key_results: summarize_results(results)
    })
    
    results
  end
  
  private
  
  def process_incoming_messages
    messages = get_messages
    
    messages.each do |message|
      puts "📨 #{@name} received #{message[:type]} from #{message[:from]}: #{message[:content].to_s[0..50]}..."
      
      case message[:type]
      when :status
        handle_status_message(message)
      when :request_help
        handle_help_request(message)
      when :share_data
        handle_data_sharing(message)
      when :coordination
        handle_coordination(message)
      end
    end
  end
  
  def execute_with_message_monitoring
    # Custom execution with message checking
    total_tasks = @tasks.length
    completed_tasks = 0
    results = []
    
    @tasks.each_with_index do |task, index|
      # Check messages before each task
      process_incoming_messages
      
      # Execute task
      begin
        result = task.execute
        completed_tasks += 1
        
        results << {
          task: task,
          result: result,
          status: :completed
        }
        
        # Notify progress
        progress = (completed_tasks.to_f / total_tasks * 100).round
        broadcast(:progress, { task: task.name, progress: progress })
        
      rescue => e
        results << {
          task: task,
          error: e,
          status: :failed
        }
        
        # Request help if task fails
        send_message("support_crew", :request_help, {
          failed_task: task.name,
          error: e.message
        })
      end
    end
    
    # Calculate final results
    success_rate = (completed_tasks.to_f / total_tasks * 100).round
    
    {
      success_rate: success_rate,
      total_tasks: total_tasks,
      completed_tasks: completed_tasks,
      results: results
    }
  end
  
  def handle_status_message(message)
    puts "📊 Status update from #{message[:from]}: #{message[:content]}"
  end
  
  def handle_help_request(message)
    puts "🆘 Help request from #{message[:from]}: #{message[:content]}"
    
    # Offer assistance if available
    send_message(message[:from], :offer_help, {
      from_crew: @name,
      available_agents: @agents.map(&:name),
      response_to: message[:id]
    })
  end
  
  def handle_data_sharing(message)
    puts "📊 Data shared from #{message[:from]}"
    add_shared_context(message[:content])
  end
  
  def handle_coordination(message)
    puts "🤝 Coordination message from #{message[:from]}"
    # Handle coordination logic
  end
  
  def summarize_results(results)
    # Create summary for other crews
    completed = results[:results].select { |r| r[:status] == :completed }
    completed.map { |r| r[:result][0..100] }.join(" | ")
  end
end

# Example: Coordinated Product Development
frontend_crew = CommunicatingCrew.new("frontend_team")
backend_crew = CommunicatingCrew.new("backend_team") 
qa_crew = CommunicatingCrew.new("qa_team")

# Setup communication subscriptions
frontend_crew.subscribe_to("backend_team", message_types: [:api_ready, :schema_update])
qa_crew.subscribe_to("frontend_team", message_types: [:feature_complete])
qa_crew.subscribe_to("backend_team", message_types: [:api_ready])

puts "🌐 Coordinated Product Development with Cross-Crew Communication"
puts "="*70

# Execute crews with communication
backend_results = backend_crew.execute_with_communication
frontend_results = frontend_crew.execute_with_communication  
qa_results = qa_crew.execute_with_communication

puts "\n💬 Communication completed successfully!"
```

## Orchestration Strategies

Advanced patterns for managing complex multi-crew operations:

```ruby
class MultiCrewOrchestrator
  def initialize
    @crews = {}
    @execution_graph = {}
    @resource_manager = SharedResourceManager.new
    @communication_hub = CrewCommunicationHub.new
  end
  
  def add_crew(name, crew, dependencies: [], priority: :normal)
    @crews[name] = {
      crew: crew,
      dependencies: dependencies,
      priority: priority,
      status: :pending
    }
    
    @execution_graph[name] = dependencies
  end
  
  def execute_orchestrated
    puts "🎼 Starting Multi-Crew Orchestration"
    puts "Crews: #{@crews.keys.join(', ')}"
    puts "="*60
    
    # Calculate execution order based on dependencies
    execution_order = calculate_execution_order
    
    puts "Execution Order: #{execution_order.join(' → ')}"
    
    results = {}
    
    execution_order.each do |crew_name|
      puts "\n🎯 Executing #{crew_name}"
      
      crew_config = @crews[crew_name]
      crew = crew_config[:crew]
      
      # Wait for dependencies
      wait_for_dependencies(crew_name)
      
      # Mark as running
      crew_config[:status] = :running
      
      begin
        # Execute crew
        result = crew.execute
        
        # Mark as completed
        crew_config[:status] = :completed
        results[crew_name] = {
          success: true,
          result: result,
          crew_config: crew_config
        }
        
        puts "✅ #{crew_name} completed successfully"
        
        # Share results with dependent crews
        share_results_with_dependents(crew_name, result)
        
      rescue => e
        crew_config[:status] = :failed
        results[crew_name] = {
          success: false,
          error: e.message,
          crew_config: crew_config
        }
        
        puts "❌ #{crew_name} failed: #{e.message}"
        
        # Handle failure - may need to skip dependent crews
        handle_crew_failure(crew_name, e)
      end
    end
    
    generate_orchestration_report(results)
  end
  
  private
  
  def calculate_execution_order
    # Topological sort for dependency resolution
    visited = Set.new
    temp_visited = Set.new
    result = []
    
    def visit_crew(crew_name, visited, temp_visited, result)
      return if visited.include?(crew_name)
      
      if temp_visited.include?(crew_name)
        raise "Circular dependency detected involving #{crew_name}"
      end
      
      temp_visited.add(crew_name)
      
      @execution_graph[crew_name].each do |dependency|
        visit_crew(dependency, visited, temp_visited, result)
      end
      
      temp_visited.delete(crew_name)
      visited.add(crew_name)
      result.unshift(crew_name)
    end
    
    @crews.keys.each do |crew_name|
      visit_crew(crew_name, visited, temp_visited, result) unless visited.include?(crew_name)
    end
    
    result
  end
  
  def wait_for_dependencies(crew_name)
    dependencies = @execution_graph[crew_name]
    return if dependencies.empty?
    
    puts "⏳ Waiting for dependencies: #{dependencies.join(', ')}"
    
    dependencies.each do |dep_name|
      while @crews[dep_name][:status] != :completed
        if @crews[dep_name][:status] == :failed
          raise "Dependency #{dep_name} failed, cannot execute #{crew_name}"
        end
        
        sleep(1)
      end
    end
    
    puts "✅ All dependencies ready for #{crew_name}"
  end
  
  def share_results_with_dependents(crew_name, results)
    # Find crews that depend on this one
    dependents = @execution_graph.select { |name, deps| deps.include?(crew_name) }.keys
    
    dependents.each do |dependent_name|
      dependent_crew = @crews[dependent_name][:crew]
      
      # Share results as context
      if dependent_crew.respond_to?(:add_shared_context)
        dependent_crew.add_shared_context({
          "#{crew_name}_results" => results
        })
      end
    end
  end
  
  def handle_crew_failure(failed_crew, error)
    # Find all crews that depend on the failed crew
    affected_crews = find_affected_crews(failed_crew)
    
    puts "⚠️ Failure in #{failed_crew} affects: #{affected_crews.join(', ')}"
    
    # Mark affected crews as blocked
    affected_crews.each do |crew_name|
      @crews[crew_name][:status] = :blocked
    end
  end
  
  def find_affected_crews(failed_crew)
    affected = []
    
    @execution_graph.each do |crew_name, dependencies|
      if dependencies.include?(failed_crew) || 
         dependencies.any? { |dep| find_affected_crews(dep).include?(failed_crew) }
        affected << crew_name
      end
    end
    
    affected
  end
  
  def generate_orchestration_report(results)
    puts "\n📊 ORCHESTRATION RESULTS"
    puts "="*50
    
    successful = results.values.count { |r| r[:success] }
    total = results.length
    
    puts "Overall Success Rate: #{successful}/#{total} (#{(successful.to_f/total*100).round(1)}%)"
    puts
    
    results.each do |crew_name, result|
      status = result[:success] ? "✅" : "❌"
      priority = result[:crew_config][:priority]
      
      puts "#{status} #{crew_name} (#{priority})"
      
      if result[:success]
        success_rate = result[:result][:success_rate] || 0
        puts "    Success Rate: #{success_rate}%"
        puts "    Tasks: #{result[:result][:completed_tasks]}/#{result[:result][:total_tasks]}"
      else
        puts "    Error: #{result[:error]}"
      end
      
      dependencies = result[:crew_config][:dependencies]
      puts "    Dependencies: #{dependencies.empty? ? 'None' : dependencies.join(', ')}"
      puts
    end
    
    # Save orchestration report
    File.write("orchestration_report.json", JSON.pretty_generate({
      orchestration: "Multi-Crew Execution",
      results: results,
      execution_graph: @execution_graph,
      summary: {
        success_rate: (successful.to_f/total*100).round(1),
        total_crews: total,
        successful_crews: successful
      }
    }))
    
    puts "💾 Orchestration report saved: orchestration_report.json"
  end
end

# Example: Complex Software Release Pipeline
orchestrator = MultiCrewOrchestrator.new

# Add crews with dependencies
orchestrator.add_crew("planning", planning_crew, dependencies: [])
orchestrator.add_crew("development", dev_crew, dependencies: ["planning"])  
orchestrator.add_crew("testing", qa_crew, dependencies: ["development"])
orchestrator.add_crew("security", security_crew, dependencies: ["development"])
orchestrator.add_crew("deployment", deploy_crew, dependencies: ["testing", "security"])
orchestrator.add_crew("monitoring", monitoring_crew, dependencies: ["deployment"])

# Execute orchestrated pipeline
orchestrator.execute_orchestrated
```

## Production Multi-Crew Systems

Production-ready patterns with monitoring, error handling, and scalability:

```ruby
class ProductionMultiCrewSystem
  def initialize
    @logger = Logger.new($stdout)
    @metrics = MetricsCollector.new
    @health_monitor = HealthMonitor.new
    @crew_registry = {}
  end
  
  def register_crew(name, crew, config = {})
    @crew_registry[name] = {
      crew: crew,
      config: config.merge(
        max_retries: config[:max_retries] || 3,
        timeout: config[:timeout] || 300,
        health_check_interval: config[:health_check_interval] || 60
      ),
      status: :registered,
      health: :unknown,
      last_execution: nil
    }
    
    @logger.info("Crew registered: #{name}")
  end
  
  def execute_system(execution_plan)
    @logger.info("Starting production multi-crew system execution")
    @metrics.start_execution
    
    begin
      results = execute_with_monitoring(execution_plan)
      @metrics.record_success
      results
    rescue => e
      @metrics.record_failure(e)
      @logger.error("System execution failed: #{e.message}")
      raise
    ensure
      @metrics.finish_execution
    end
  end
  
  private
  
  def execute_with_monitoring(execution_plan)
    # Start health monitoring
    monitoring_thread = start_health_monitoring
    
    # Execute according to plan
    results = case execution_plan[:type]
    when :sequential
      execute_sequential(execution_plan[:crews])
    when :parallel
      execute_parallel(execution_plan[:crews])
    when :orchestrated
      execute_orchestrated(execution_plan)
    else
      raise "Unknown execution plan type: #{execution_plan[:type]}"
    end
    
    # Stop monitoring
    monitoring_thread.kill if monitoring_thread
    
    results
  end
  
  def start_health_monitoring
    Thread.new do
      loop do
        @crew_registry.each do |name, crew_info|
          check_crew_health(name, crew_info)
        end
        
        sleep(30)  # Check every 30 seconds
      end
    end
  end
  
  def check_crew_health(name, crew_info)
    begin
      # Basic health check
      crew = crew_info[:crew]
      
      health_status = if crew.respond_to?(:health_check)
        crew.health_check
      else
        # Default health check
        { status: :healthy, agents: crew.agents.length }
      end
      
      crew_info[:health] = health_status[:status]
      crew_info[:last_health_check] = Time.now
      
      @health_monitor.record_health_check(name, health_status)
      
    rescue => e
      crew_info[:health] = :unhealthy
      @logger.error("Health check failed for #{name}: #{e.message}")
    end
  end
end

class MetricsCollector
  def initialize
    @metrics = {
      executions: 0,
      successes: 0,
      failures: 0,
      total_duration: 0,
      crew_performance: {}
    }
    @current_execution = nil
  end
  
  def start_execution
    @current_execution = {
      start_time: Time.now,
      crew_metrics: {}
    }
  end
  
  def record_crew_start(crew_name)
    @current_execution[:crew_metrics][crew_name] = {
      start_time: Time.now
    }
  end
  
  def record_crew_completion(crew_name, success, result = nil)
    crew_metrics = @current_execution[:crew_metrics][crew_name]
    crew_metrics[:end_time] = Time.now
    crew_metrics[:duration] = crew_metrics[:end_time] - crew_metrics[:start_time]
    crew_metrics[:success] = success
    crew_metrics[:result_size] = result&.to_s&.length || 0
    
    # Update overall metrics
    @metrics[:crew_performance][crew_name] ||= {
      executions: 0,
      successes: 0,
      avg_duration: 0
    }
    
    crew_perf = @metrics[:crew_performance][crew_name]
    crew_perf[:executions] += 1
    crew_perf[:successes] += 1 if success
    crew_perf[:avg_duration] = (
      crew_perf[:avg_duration] * (crew_perf[:executions] - 1) + crew_metrics[:duration]
    ) / crew_perf[:executions]
  end
  
  def record_success
    @metrics[:executions] += 1
    @metrics[:successes] += 1
  end
  
  def record_failure(error)
    @metrics[:executions] += 1
    @metrics[:failures] += 1
    @metrics[:last_error] = error.message
  end
  
  def finish_execution
    return unless @current_execution
    
    duration = Time.now - @current_execution[:start_time]
    @metrics[:total_duration] += duration
    @metrics[:avg_duration] = @metrics[:total_duration] / @metrics[:executions]
    
    @current_execution = nil
  end
  
  def get_metrics
    @metrics.merge(
      success_rate: @metrics[:executions] > 0 ? 
        (@metrics[:successes].to_f / @metrics[:executions] * 100).round(1) : 0
    )
  end
end

class HealthMonitor
  def initialize
    @health_history = {}
  end
  
  def record_health_check(crew_name, health_status)
    @health_history[crew_name] ||= []
    @health_history[crew_name] << {
      timestamp: Time.now,
      status: health_status[:status],
      details: health_status
    }
    
    # Keep only last 100 health checks
    @health_history[crew_name] = @health_history[crew_name].last(100)
  end
  
  def get_health_summary
    summary = {}
    
    @health_history.each do |crew_name, checks|
      recent_checks = checks.last(10)
      healthy_count = recent_checks.count { |c| c[:status] == :healthy }
      
      summary[crew_name] = {
        current_status: recent_checks.last&.[](:status) || :unknown,
        health_percentage: (healthy_count.to_f / recent_checks.length * 100).round(1),
        last_check: recent_checks.last&.[](:timestamp)
      }
    end
    
    summary
  end
end
```

## Best Practices

### 1. **Crew Design Principles**
- **Clear Boundaries**: Each crew should have distinct responsibilities
- **Minimal Coupling**: Reduce dependencies between crews
- **Resource Isolation**: Crews should manage their own resources
- **Communication Protocols**: Establish clear communication patterns

### 2. **Execution Patterns**
- **Sequential**: Use for workflows with strict dependencies
- **Parallel**: Use when crews can work independently  
- **Orchestrated**: Use for complex coordination requirements
- **Hybrid**: Combine patterns for optimal performance

### 3. **Resource Management**
- **Shared Resources**: Use resource managers for shared data
- **Resource Locking**: Prevent conflicts with locking mechanisms
- **Resource Cleanup**: Ensure resources are released properly
- **Resource Monitoring**: Track resource usage and performance

### 4. **Error Handling**
- **Graceful Degradation**: Handle crew failures without system collapse
- **Retry Logic**: Implement intelligent retry strategies
- **Fallback Options**: Provide alternative execution paths
- **Error Propagation**: Manage error propagation between crews

### 5. **Monitoring and Observability**
- **Health Checks**: Monitor crew health continuously
- **Performance Metrics**: Track execution times and success rates
- **Resource Usage**: Monitor memory, CPU, and other resources
- **Alerting**: Set up alerts for critical failures

## Next Steps

Now that you understand multi-crew operations:

1. Try the [Production Deployment]({{ site.baseurl }}/tutorials/deployment) tutorial
2. Review the [API Documentation]({{ site.baseurl }}/api/) for detailed reference
3. Check out [Advanced Examples]({{ site.baseurl }}/examples/) for complex scenarios
4. Explore [Integration Patterns]({{ site.baseurl }}/guides/) for enterprise use

Multi-crew systems are essential for building scalable AI operations that can handle complex, enterprise-level workflows with reliability and efficiency.