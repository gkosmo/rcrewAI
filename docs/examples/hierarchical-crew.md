---
layout: example
title: Hierarchical Crew with Manager Coordination
description: Advanced example showing hierarchical team coordination with manager agents
---

# Hierarchical Crew with Manager Coordination

This example demonstrates RCrewAI's hierarchical execution mode where a manager agent coordinates and delegates tasks to specialist agents. This pattern is ideal for complex workflows requiring coordination, delegation, and strategic oversight.

## Overview

We'll create a software development crew with:
- **Project Manager**: Coordinates team and delegates tasks
- **Backend Developer**: Handles server-side development tasks  
- **Frontend Developer**: Manages user interface development
- **QA Engineer**: Ensures quality and testing
- **DevOps Engineer**: Manages deployment and infrastructure

The manager will intelligently delegate tasks based on agent expertise and coordinate the overall project execution.

## Complete Implementation

```ruby
require 'rcrewai'

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai  # or your preferred provider
  config.temperature = 0.2       # Lower temperature for more consistent coordination
end

# Create hierarchical crew
software_team = RCrewAI::Crew.new("software_development_team", process: :hierarchical)

# ===== MANAGER AGENT =====
project_manager = RCrewAI::Agent.new(
  name: "project_manager",
  role: "Senior Technical Project Manager",
  goal: "Coordinate software development projects efficiently and ensure high-quality deliverables",
  backstory: "You are an experienced project manager with 15+ years in software development. You excel at breaking down complex projects, delegating tasks to the right specialists, and ensuring everything comes together seamlessly. You understand each team member's strengths and can provide strategic guidance.",
  manager: true,              # Designate as manager
  allow_delegation: true,     # Enable task delegation
  tools: [
    RCrewAI::Tools::FileReader.new,  # Can review project files
    RCrewAI::Tools::FileWriter.new   # Can create project docs
  ],
  verbose: true,
  max_iterations: 8
)

# ===== SPECIALIST AGENTS =====

backend_developer = RCrewAI::Agent.new(
  name: "backend_developer",
  role: "Senior Backend Developer",
  goal: "Build robust, scalable backend systems and APIs",
  backstory: "You are a seasoned backend developer with expertise in Ruby, Python, databases, and API design. You excel at creating efficient server-side solutions, optimizing database queries, and ensuring system reliability.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new,
    RCrewAI::Tools::WebSearch.new  # For researching best practices
  ],
  verbose: true,
  max_execution_time: 600
)

frontend_developer = RCrewAI::Agent.new(
  name: "frontend_developer", 
  role: "Frontend Developer",
  goal: "Create intuitive and responsive user interfaces",
  backstory: "You are a creative frontend developer skilled in React, Vue.js, and modern CSS frameworks. You focus on user experience, accessibility, and creating visually appealing interfaces that users love.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new,
    RCrewAI::Tools::WebSearch.new
  ],
  verbose: true
)

qa_engineer = RCrewAI::Agent.new(
  name: "qa_engineer",
  role: "Quality Assurance Engineer", 
  goal: "Ensure software quality through comprehensive testing strategies",
  backstory: "You are a detail-oriented QA engineer with expertise in both manual and automated testing. You excel at finding edge cases, creating comprehensive test plans, and ensuring applications are reliable and user-friendly.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

devops_engineer = RCrewAI::Agent.new(
  name: "devops_engineer",
  role: "DevOps Engineer",
  goal: "Manage deployment pipelines and infrastructure efficiently",
  backstory: "You are an experienced DevOps engineer skilled in containerization, CI/CD pipelines, and cloud infrastructure. You ensure smooth deployments and maintain reliable production environments.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new,
    RCrewAI::Tools::WebSearch.new
  ],
  verbose: true
)

# ===== BUILD TEAM HIERARCHY =====

# Add manager first
software_team.add_agent(project_manager)

# Add specialists (manager will coordinate them)
software_team.add_agent(backend_developer)
software_team.add_agent(frontend_developer)  
software_team.add_agent(qa_engineer)
software_team.add_agent(devops_engineer)

# ===== DEFINE COMPLEX PROJECT TASKS =====

# Phase 1: Planning and Architecture
architecture_task = RCrewAI::Task.new(
  name: "system_architecture",
  description: "Design the overall system architecture for a task management web application. Include database schema, API endpoints, frontend structure, and deployment strategy. Consider scalability, security, and maintainability.",
  expected_output: "Comprehensive system architecture document with diagrams, technology stack decisions, and implementation plan",
  async: true
)

# Phase 2: Backend Development
backend_api_task = RCrewAI::Task.new(
  name: "backend_api_development",
  description: "Implement the backend API for the task management system. Create RESTful endpoints for user management, task CRUD operations, team collaboration features, and authentication. Include proper error handling and validation.",
  expected_output: "Complete backend API code with endpoints, models, database migrations, and API documentation",
  context: [architecture_task],  # Depends on architecture
  async: true
)

database_task = RCrewAI::Task.new(
  name: "database_design",
  description: "Design and implement the database schema for the task management system. Optimize for performance and include proper indexing, relationships, and data integrity constraints.",
  expected_output: "Database schema file, migration scripts, and performance optimization recommendations", 
  context: [architecture_task],
  async: true
)

# Phase 3: Frontend Development  
frontend_ui_task = RCrewAI::Task.new(
  name: "frontend_ui_development",
  description: "Create the user interface for the task management application. Build responsive components for task creation, team collaboration, dashboard views, and user management. Ensure excellent UX and accessibility.",
  expected_output: "Complete frontend application with all UI components, routing, and state management",
  context: [architecture_task, backend_api_task],
  async: true
)

# Phase 4: Quality Assurance
testing_strategy_task = RCrewAI::Task.new(
  name: "testing_strategy",
  description: "Develop comprehensive testing strategy including unit tests, integration tests, and end-to-end testing. Create test cases for all critical user workflows and edge cases.",
  expected_output: "Complete test suite with automated tests, test documentation, and quality assurance checklist",
  context: [backend_api_task, frontend_ui_task],
  async: true
)

# Phase 5: Deployment
deployment_task = RCrewAI::Task.new(
  name: "deployment_pipeline", 
  description: "Set up production-ready deployment pipeline with CI/CD automation. Include containerization, environment configurations, monitoring, and rollback capabilities.",
  expected_output: "Deployment scripts, CI/CD pipeline configuration, monitoring setup, and deployment documentation",
  context: [backend_api_task, frontend_ui_task, testing_strategy_task],
  async: true
)

# Phase 6: Integration and Documentation
integration_task = RCrewAI::Task.new(
  name: "system_integration",
  description: "Integrate all components and create comprehensive project documentation. Include setup instructions, API documentation, user guides, and maintenance procedures.",
  expected_output: "Fully integrated system with complete documentation package",
  context: [backend_api_task, frontend_ui_task, testing_strategy_task, deployment_task]
)

# ===== ADD TASKS TO CREW =====
software_team.add_task(architecture_task)
software_team.add_task(backend_api_task)
software_team.add_task(database_task)
software_team.add_task(frontend_ui_task)
software_team.add_task(testing_strategy_task)
software_team.add_task(deployment_task)
software_team.add_task(integration_task)

# ===== EXECUTE WITH HIERARCHICAL COORDINATION =====

puts "🚀 Starting Software Development Project with Hierarchical Team"
puts "="*60
puts "Manager: #{project_manager.name}"
puts "Team: #{[backend_developer, frontend_developer, qa_engineer, devops_engineer].map(&:name).join(', ')}"
puts "Tasks: #{software_team.tasks.length} tasks with dependencies"
puts "="*60

# Execute with async coordination - manager will:
# 1. Analyze all tasks and dependencies
# 2. Create execution phases based on dependencies
# 3. Delegate tasks to most appropriate specialists
# 4. Monitor progress and coordinate between phases
# 5. Handle any failures or blockers
results = software_team.execute(async: true, max_concurrency: 3)

# ===== ANALYZE RESULTS =====

puts "\n" + "="*60
puts "📊 PROJECT EXECUTION RESULTS"
puts "="*60

puts "Overall Success Rate: #{results[:success_rate]}%"
puts "Total Tasks: #{results[:total_tasks]}"
puts "Completed Tasks: #{results[:completed_tasks]}" 
puts "Failed Tasks: #{results[:failed_tasks]}"
puts "Manager: #{results[:manager]}"
puts "Process Type: #{results[:process]}"

puts "\n📋 TASK BREAKDOWN:"
puts "-"*40

results[:results].each_with_index do |task_result, index|
  status_emoji = task_result[:status] == :completed ? "✅" : "❌"
  
  puts "#{index + 1}. #{status_emoji} #{task_result[:task].name}"
  puts "   Assigned to: #{task_result[:assigned_agent]}"
  puts "   Phase: #{task_result[:phase]}"
  puts "   Status: #{task_result[:status]}"
  
  if task_result[:status] == :completed
    puts "   Result preview: #{task_result[:result][0..100]}..."
  else
    puts "   Error: #{task_result[:error]&.message}"
  end
  puts
end

# ===== SAVE PROJECT ARTIFACTS =====

puts "\n💾 SAVING PROJECT ARTIFACTS:"
puts "-"*40

completed_tasks = results[:results].select { |r| r[:status] == :completed }

completed_tasks.each do |task_result|
  filename = "#{task_result[:task].name.gsub(' ', '_')}_result.md"
  
  content = <<~CONTENT
    # #{task_result[:task].name.split('_').map(&:capitalize).join(' ')}
    
    **Task:** #{task_result[:task].name}
    **Assigned Agent:** #{task_result[:assigned_agent]}
    **Execution Phase:** #{task_result[:phase]}
    **Status:** #{task_result[:status]}
    
    ## Result
    
    #{task_result[:result]}
    
    ---
    Generated by RCrewAI Hierarchical Team
    Manager: #{results[:manager]}
    Execution Date: #{Time.now}
  CONTENT
  
  File.write(filename, content)
  puts "  ✅ Saved #{filename} (#{content.length} characters)"
end

# ===== MANAGER SUMMARY REPORT =====

summary_report = <<~REPORT
  # Software Development Project Summary
  
  **Project Manager:** #{results[:manager]}
  **Team Size:** #{software_team.agents.length - 1} specialists
  **Execution Mode:** Hierarchical with Async Coordination
  
  ## Project Metrics
  - **Success Rate:** #{results[:success_rate]}%
  - **Total Tasks:** #{results[:total_tasks]}
  - **Completed:** #{results[:completed_tasks]}
  - **Failed:** #{results[:failed_tasks]}
  
  ## Team Performance
  
  #{software_team.agents.reject(&:is_manager?).map do |agent|
    assigned_tasks = results[:results].select { |r| r[:assigned_agent] == agent.name }
    completed = assigned_tasks.count { |r| r[:status] == :completed }
    
    "- **#{agent.name}** (#{agent.role}): #{completed}/#{assigned_tasks.length} tasks completed"
  end.join("\n")}
  
  ## Task Execution Phases
  
  The manager organized tasks into efficient execution phases:
  
  #{results[:results].group_by { |r| r[:phase] }.map do |phase, tasks|
    "### Phase #{phase}\n" + tasks.map { |t| "- #{t[:task].name} (#{t[:status]})" }.join("\n")
  end.join("\n\n")}
  
  ## Key Achievements
  
  ✅ System architecture designed with scalability in mind
  ✅ Backend API implemented with proper error handling  
  ✅ Database optimized for performance
  ✅ Frontend UI created with excellent UX
  ✅ Comprehensive testing strategy developed
  ✅ Production deployment pipeline established
  ✅ All components integrated successfully
  
  ## Recommendations
  
  Based on the hierarchical execution, the manager recommends:
  1. Continue using async execution for independent tasks
  2. Maintain clear task dependencies to optimize workflow
  3. Regular coordination meetings for complex integrations
  4. Implement automated quality gates in the CI/CD pipeline
  
  ---
  Report generated by RCrewAI Hierarchical Management System
  Date: #{Time.now}
REPORT

File.write("project_summary_report.md", summary_report)
puts "  ✅ Saved project_summary_report.md"

puts "\n🎉 SOFTWARE DEVELOPMENT PROJECT COMPLETED!"
puts "The hierarchical team successfully coordinated #{results[:total_tasks]} tasks"
puts "with #{results[:success_rate]}% success rate using intelligent delegation."
```

## Key Features Demonstrated

### 1. **Manager Coordination**
The project manager:
- Analyzes task dependencies and creates execution phases
- Delegates tasks to specialists based on expertise matching
- Monitors progress across multiple concurrent streams
- Makes strategic decisions about task prioritization

### 2. **Intelligent Delegation**
```ruby
# Manager automatically delegates based on:
# - Agent role and expertise keywords
# - Tool availability and requirements  
# - Current workload and capacity
# - Task complexity and dependencies

# Backend tasks → Backend Developer
# UI tasks → Frontend Developer  
# Testing tasks → QA Engineer
# Deployment tasks → DevOps Engineer
```

### 3. **Async Coordination**
```ruby
# Tasks execute in coordinated phases:
# Phase 1: Architecture (foundation)
# Phase 2: Backend API + Database (parallel)
# Phase 3: Frontend UI (depends on backend)
# Phase 4: Testing (depends on implementation)
# Phase 5: Deployment (depends on testing)
# Phase 6: Integration (depends on all components)
```

### 4. **Failure Management**
The manager handles failures intelligently:
- Retries transient failures
- Reassigns failed tasks to other qualified agents
- Adjusts execution plan based on bottlenecks
- Provides detailed failure analysis

## Advanced Coordination Patterns

### Human-in-the-Loop Management
```ruby
# Manager with human oversight for critical decisions
project_manager = RCrewAI::Agent.new(
  name: "senior_pm",
  role: "Senior Project Manager",
  goal: "Coordinate complex projects with stakeholder input",
  manager: true,
  human_input: true,                      # Enable human collaboration
  require_approval_for_tools: false,      # Manager can use tools freely
  require_approval_for_final_answer: true # Human reviews project decisions
)
```

### Dynamic Team Scaling
```ruby
# Add specialists based on project needs
if project_requires_mobile?
  mobile_developer = RCrewAI::Agent.new(
    name: "mobile_developer",
    role: "Mobile App Developer", 
    goal: "Create native mobile applications",
    tools: [mobile_dev_tools]
  )
  
  software_team.add_agent(mobile_developer)
end

if project_requires_ml?
  ml_engineer = RCrewAI::Agent.new(
    name: "ml_engineer", 
    role: "Machine Learning Engineer",
    goal: "Implement ML models and data pipelines",
    tools: [ml_tools]
  )
  
  software_team.add_agent(ml_engineer)
end
```

### Multi-Manager Hierarchy
```ruby
# Large projects can have multiple manager layers
engineering_manager = RCrewAI::Agent.new(
  name: "engineering_manager",
  role: "Engineering Manager", 
  manager: true,
  allow_delegation: true
)

product_manager = RCrewAI::Agent.new(
  name: "product_manager",
  role: "Product Manager",
  manager: true, 
  allow_delegation: true
)

# Both managers coordinate different aspects
crew.add_agent(engineering_manager)  # Technical coordination
crew.add_agent(product_manager)      # Product coordination
```

## Performance Optimization

### Concurrent Execution
- Independent tasks run in parallel
- Dependencies are automatically resolved  
- Resource usage is optimized across agents
- Manager monitors and balances workload

### Intelligent Task Routing
- Tasks routed to most qualified agents
- Workload balanced across team members
- Expertise matching improves quality
- Reduced coordination overhead

## Running the Example

1. **Setup:**
   ```bash
   bundle install
   export OPENAI_API_KEY="your-api-key"
   ```

2. **Execute:**
   ```bash
   ruby hierarchical_crew_example.rb
   ```

3. **Expected Output:**
   - Detailed manager coordination logs
   - Task delegation decisions
   - Phase-by-phase execution progress
   - Individual task results
   - Comprehensive project summary
   - Generated project artifacts

This hierarchical pattern is perfect for:
- **Complex Software Projects**: Multi-component development
- **Enterprise Workflows**: Requiring coordination and oversight  
- **Multi-Disciplinary Teams**: Different expertise areas
- **Quality-Critical Projects**: Needing management oversight
- **Large-Scale Operations**: Requiring delegation and coordination

The manager agent acts as an intelligent orchestrator, making strategic decisions about task delegation while maintaining oversight of the entire project workflow.