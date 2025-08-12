#!/usr/bin/env ruby

require_relative '../lib/rcrewai'

puts "🏗️ Hierarchical Crew Process Example"
puts "=" * 50

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai  # Change as needed
  config.temperature = 0.1
end

# Create a hierarchical crew
crew = RCrewAI::Crew.new("product_development_crew", process: :hierarchical, verbose: true)

puts "📋 Creating hierarchical crew with manager and specialists..."

# Create a manager agent
project_manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Senior Project Manager", 
  goal: "Coordinate team efforts and ensure project success",
  backstory: "You are an experienced project manager with 10+ years leading cross-functional teams. You excel at delegation, coordination, and ensuring deliverables meet requirements.",
  manager: true,  # This makes the agent a manager
  allow_delegation: true,
  tools: [RCrewAI::Tools::FileWriter.new],
  verbose: true,
  max_iterations: 6
)

# Create specialist agents
market_researcher = RCrewAI::Agent.new(
  name: "market_researcher",
  role: "Market Research Specialist",
  goal: "Conduct thorough market analysis and competitive research",
  backstory: "You are a market research expert who excels at finding market opportunities, analyzing competitors, and identifying customer needs.",
  tools: [RCrewAI::Tools::WebSearch.new(max_results: 10)],
  verbose: true
)

product_designer = RCrewAI::Agent.new(
  name: "product_designer", 
  role: "Senior Product Designer",
  goal: "Design user-centered products and experiences",
  backstory: "You are a product designer with expertise in UX/UI design, user research, and product strategy. You create designs that solve real user problems.",
  tools: [RCrewAI::Tools::FileWriter.new],
  verbose: true
)

technical_lead = RCrewAI::Agent.new(
  name: "technical_lead",
  role: "Technical Lead",
  goal: "Define technical architecture and implementation strategy", 
  backstory: "You are a senior software architect who designs scalable, maintainable systems. You excel at technical planning and risk assessment.",
  tools: [
    RCrewAI::Tools::FileWriter.new,
    RCrewAI::Tools::FileReader.new
  ],
  verbose: true
)

# Add agents to crew
crew.add_agent(project_manager)  # Manager added first
crew.add_agent(market_researcher)
crew.add_agent(product_designer) 
crew.add_agent(technical_lead)

puts "👥 Crew created with:"
puts "  📊 Manager: #{project_manager.name}"
puts "  🔍 Specialists: #{crew.agents.length - 1} agents"

# Set up manager relationships
project_manager.add_subordinate(market_researcher)
project_manager.add_subordinate(product_designer)
project_manager.add_subordinate(technical_lead)

# Create tasks that will be delegated by the manager
market_research_task = RCrewAI::Task.new(
  name: "market_analysis",
  description: "Conduct comprehensive market research for a new AI-powered productivity app. Focus on market size, target demographics, competitors, pricing strategies, and key opportunities.",
  expected_output: "Detailed market analysis report with actionable insights and recommendations",
  max_retries: 2
)

product_design_task = RCrewAI::Task.new(
  name: "product_design",
  description: "Design the core user experience and feature set for an AI productivity app based on market research. Include user personas, key features, user journey, and design principles.",
  expected_output: "Product design document with UX strategy, feature specifications, and user flow diagrams",
  context: [market_research_task]  # Depends on market research
)

technical_architecture_task = RCrewAI::Task.new(
  name: "technical_architecture",
  description: "Define the technical architecture for an AI productivity app. Include technology stack, system design, scalability considerations, AI integration approach, and implementation roadmap.",
  expected_output: "Technical architecture document with system design, technology recommendations, and implementation plan",
  context: [market_research_task, product_design_task]  # Depends on both previous tasks
)

project_plan_task = RCrewAI::Task.new(
  name: "project_planning",
  description: "Create comprehensive project plan integrating market research, product design, and technical architecture. Include timeline, milestones, resource requirements, and risk assessment.",
  expected_output: "Complete project plan with timelines, deliverables, and coordination strategy saved to project_plan.md",
  agent: project_manager,  # Manager handles this directly
  context: [market_research_task, product_design_task, technical_architecture_task]
)

# Add tasks to crew
crew.add_task(market_research_task)
crew.add_task(product_design_task)
crew.add_task(technical_architecture_task)
crew.add_task(project_plan_task)

puts "📋 Tasks created with dependencies:"
crew.tasks.each_with_index do |task, i|
  deps = task.context&.length || 0
  puts "  #{i + 1}. #{task.name} (#{deps} dependencies)"
end

# Execute the hierarchical crew
puts "\n🚀 Starting hierarchical execution..."
puts "The project manager will coordinate and delegate tasks to specialists"

begin
  start_time = Time.now
  
  # Execute with hierarchical process
  results = crew.execute
  
  execution_time = Time.now - start_time
  
  # Display results
  puts "\n" + "=" * 60
  puts "🎉 HIERARCHICAL EXECUTION COMPLETED"
  puts "=" * 60
  puts "Total execution time: #{execution_time.round(2)} seconds"
  puts "Process type: #{results[:process]}"
  puts "Success rate: #{results[:success_rate]}%"
  puts "Completed tasks: #{results[:completed_tasks]}/#{results[:total_tasks]}"
  
  # Show task results
  puts "\n📊 Task Results:"
  results[:results].each do |result|
    status_icon = result[:status] == :completed ? "✅" : "❌"
    agent_name = result[:assigned_agent]&.name || result[:task].agent&.name
    
    puts "#{status_icon} #{result[:task].name}"
    puts "    Assigned to: #{agent_name}"
    puts "    Status: #{result[:status]}"
    
    if result[:phase]
      puts "    Phase: #{result[:phase]}"
    end
    
    if result[:status] == :completed
      preview = result[:result][0..150]
      preview += "..." if result[:result].length > 150
      puts "    Result: #{preview}"
    else
      puts "    Error: #{result[:result]}"
    end
    
    puts
  end
  
  # Show delegation insights
  puts "🎯 Hierarchical Process Insights:"
  puts "  • Manager coordinated #{crew.agents.length - 1} specialists"
  puts "  • Tasks were delegated based on agent expertise"
  puts "  • Dependencies were handled automatically"
  puts "  • Cross-phase coordination was managed"
  
  # Check for output files
  if File.exist?('project_plan.md')
    puts "\n📄 Generated Files:"
    puts "  ✅ project_plan.md (#{File.size('project_plan.md')} bytes)"
  end
  
rescue RCrewAI::ProcessError => e
  puts "\n❌ Process Error: #{e.message}"
  puts "This might indicate issues with agent setup or task dependencies"
  
rescue RCrewAI::AgentError => e
  puts "\n❌ Agent Error: #{e.message}"
  
rescue => e
  puts "\n💥 Unexpected error: #{e.message}"
  puts e.backtrace.first(3).join("\n") if ENV['DEBUG']
end

puts "\n" + "=" * 50
puts "🏗️ Hierarchical Crew Example Complete!"
puts "=" * 50