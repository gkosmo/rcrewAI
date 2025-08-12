#!/usr/bin/env ruby

require_relative '../lib/rcrewai'

puts "🤝 Human-in-the-Loop Example"
puts "=" * 50

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai  # Change as needed
  config.temperature = 0.1
end

puts "🔧 Setting up crew with human interaction capabilities..."

# Create crew
crew = RCrewAI::Crew.new("human_assisted_crew")

# Create agents with human input capabilities
research_agent = RCrewAI::Agent.new(
  name: "research_assistant",
  role: "Research Specialist", 
  goal: "Conduct thorough research with human oversight",
  backstory: "You work closely with humans to ensure research quality and accuracy.",
  tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileWriter.new],
  verbose: true,
  human_input: true,  # Enable human input
  require_approval_for_tools: true,  # Require approval for tool usage
  require_approval_for_final_answer: true  # Require approval for final answers
)

content_creator = RCrewAI::Agent.new(
  name: "content_creator",
  role: "Content Writer",
  goal: "Create engaging content with human guidance",
  backstory: "You collaborate with humans to create compelling, accurate content.",
  tools: [RCrewAI::Tools::FileWriter.new, RCrewAI::Tools::FileReader.new],
  verbose: true,
  human_input: true,
  require_approval_for_final_answer: true
)

quality_checker = RCrewAI::Agent.new(
  name: "quality_checker", 
  role: "Quality Assurance Specialist",
  goal: "Ensure content meets quality standards",
  backstory: "You work with humans to maintain high quality standards.",
  tools: [RCrewAI::Tools::FileReader.new],
  verbose: true,
  human_input: true
)

# Add agents to crew
crew.add_agent(research_agent)
crew.add_agent(content_creator)
crew.add_agent(quality_checker)

puts "👥 Created crew with #{crew.agents.length} agents (all human-enabled)"

# Create tasks with various levels of human interaction

# Task 1: Research with human confirmation and guidance
research_task = RCrewAI::Task.new(
  name: "research_ai_trends",
  description: "Research the latest AI trends for 2024, focusing on practical business applications",
  agent: research_agent,
  expected_output: "Comprehensive research document saved as ai_trends_2024.md",
  human_input: true,
  require_confirmation: true,  # Human must confirm before starting
  allow_guidance: true,        # Allow human to provide guidance during execution
  human_review_points: [:completion]  # Review when completed
)

# Task 2: Content creation with human oversight
content_task = RCrewAI::Task.new(
  name: "create_ai_article",
  description: "Write an engaging article based on the research findings about AI trends",
  agent: content_creator,
  expected_output: "Well-structured article saved as ai_trends_article.md",
  context: [research_task],
  human_input: true,
  allow_guidance: true,
  human_review_points: [:completion]
)

# Task 3: Quality check with human review
quality_task = RCrewAI::Task.new(
  name: "quality_review",
  description: "Review the article for accuracy, clarity, and engagement",
  agent: quality_checker,
  expected_output: "Quality assessment report with recommendations",
  context: [content_task],
  human_input: true,
  human_review_points: [:completion]
)

crew.add_task(research_task)
crew.add_task(content_task)
crew.add_task(quality_task)

puts "📋 Created #{crew.tasks.length} tasks with human interaction points"

# Demonstrate different human interaction modes
puts "\n🎯 HUMAN-IN-THE-LOOP EXECUTION MODES"
puts "-" * 40

puts "\n1️⃣ BASIC HUMAN APPROVAL MODE"
puts "Tasks will request human approval at key decision points..."

begin
  results = crew.execute
  
  puts "\n📊 Execution Results:"
  puts "  Completed: #{results[:completed_tasks]}/#{results[:total_tasks]}"
  puts "  Success Rate: #{results[:success_rate]}%"
  
  # Show any generated files
  output_files = ['ai_trends_2024.md', 'ai_trends_article.md']
  puts "\n📄 Generated Files:"
  output_files.each do |file|
    if File.exist?(file)
      puts "  ✅ #{file} (#{File.size(file)} bytes)"
    else
      puts "  ❌ #{file} (not created)"
    end
  end

rescue => e
  puts "❌ Execution failed or was cancelled: #{e.message}"
end

puts "\n2️⃣ AGENT-LEVEL HUMAN INTERACTION DEMONSTRATION"
puts "Creating a standalone task to show detailed human interactions..."

# Create a simple demonstration task
demo_agent = RCrewAI::Agent.new(
  name: "demo_agent",
  role: "Demonstration Agent",
  goal: "Show human interaction capabilities",
  backstory: "I demonstrate various human interaction patterns.",
  tools: [RCrewAI::Tools::FileWriter.new],
  verbose: true
)

# Enable different types of human interaction
demo_agent.enable_human_input(
  require_approval_for_tools: true,
  require_approval_for_final_answer: true
)

demo_task = RCrewAI::Task.new(
  name: "human_interaction_demo",
  description: "Write a short summary of Ruby programming benefits and save it to ruby_benefits.txt",
  agent: demo_agent,
  expected_output: "A text file containing Ruby programming benefits",
  human_input: true,
  require_confirmation: true,
  allow_guidance: true
)

puts "\n🚀 Starting human interaction demonstration..."

begin
  demo_result = demo_task.execute
  puts "\nDemo result: #{demo_result}"
  
  if File.exist?('ruby_benefits.txt')
    puts "\n📄 Generated demo file:"
    puts File.read('ruby_benefits.txt')[0..200] + "..."
  end

rescue => e
  puts "Demo task result: #{e.message}"
end

puts "\n3️⃣ HUMAN INPUT UTILITY DEMONSTRATION"
puts "Testing different types of human input requests..."

# Demonstrate the HumanInput utility directly
human_input = RCrewAI::HumanInput.new(verbose: true)

puts "\nTesting approval request..."
approval_result = human_input.request_approval(
  "Test approval request - this is just a demonstration",
  context: "This is a test of the human input system",
  consequences: "Nothing will actually happen",
  timeout: 30
)
puts "Approval result: #{approval_result[:approved] ? 'APPROVED' : 'REJECTED'}"

puts "\nTesting choice request..."
choice_result = human_input.request_choice(
  "What's your preferred programming language?",
  ["Ruby", "Python", "JavaScript", "Other"],
  timeout: 30
)
puts "Choice result: #{choice_result[:choice]}" if choice_result[:valid]

puts "\nTesting input request..."
input_result = human_input.request_input(
  "Enter a short message (or press Enter to skip):",
  help_text: "This is just for testing the input system",
  timeout: 20
)
puts "Input result: '#{input_result[:input]}'" if input_result[:valid]

# Show session summary
puts "\n📈 Human Input Session Summary:"
summary = human_input.session_summary
summary.each { |key, value| puts "  #{key}: #{value}" }

puts "\n🎯 HUMAN-IN-THE-LOOP FEATURES DEMONSTRATED:"
puts "  • Task-level human confirmation before execution"
puts "  • Agent-level tool approval workflows"
puts "  • Final answer review and revision capabilities"
puts "  • Human guidance integration into agent reasoning"
puts "  • Task completion review and feedback handling"
puts "  • Error handling with human intervention options"
puts "  • Flexible human input types (approval, choice, input, review)"
puts "  • Session tracking and interaction history"
puts "  • Configurable timeouts and auto-approval modes"
puts "  • Integration with both sync and async execution"

puts "\n💡 USAGE PATTERNS:"
puts "  1. Development & Testing: Use human approval for tool usage"
puts "  2. Content Creation: Human review of final outputs"
puts "  3. Critical Tasks: Human confirmation before execution"
puts "  4. Learning & Training: Human guidance during reasoning"
puts "  5. Quality Assurance: Human review at completion points"

puts "\n" + "=" * 50
puts "🤝 Human-in-the-Loop Demo Complete!"
puts "=" * 50