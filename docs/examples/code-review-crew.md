---
layout: example
title: Code Review Crew
description: Automated code review system with specialized agents for security, performance, and quality analysis
---

# Code Review Crew

This example demonstrates an automated code review system using specialized AI agents that analyze code for security vulnerabilities, performance issues, code quality, and documentation completeness. The system provides comprehensive feedback and suggestions for improvement.

## Overview

Our code review crew consists of:
- **Security Analyst** - Identifies vulnerabilities and security best practices
- **Performance Specialist** - Analyzes code efficiency and optimization opportunities  
- **Code Quality Reviewer** - Ensures coding standards and maintainability
- **Documentation Specialist** - Reviews and improves code documentation
- **Integration Tester** - Validates integration patterns and testing coverage

## Complete Implementation

```ruby
require 'rcrewai'
require 'json'

# Configure RCrewAI for code analysis
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.temperature = 0.2  # Lower temperature for consistent analysis
end

# ===== CODE REVIEW SPECIALISTS =====

# Security Analysis Agent
security_analyst = RCrewAI::Agent.new(
  name: "security_analyst",
  role: "Senior Security Code Reviewer",
  goal: "Identify security vulnerabilities and ensure secure coding practices",
  backstory: "You are an expert cybersecurity professional with deep knowledge of common vulnerabilities (OWASP Top 10), secure coding practices, and threat modeling. You excel at identifying security risks in code and providing actionable remediation advice.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Performance Specialist Agent  
performance_specialist = RCrewAI::Agent.new(
  name: "performance_specialist",
  role: "Performance Optimization Expert", 
  goal: "Identify performance bottlenecks and optimize code efficiency",
  backstory: "You are a performance engineering expert who understands algorithmic complexity, memory management, and system optimization. You excel at identifying inefficient code patterns and suggesting improvements.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Code Quality Reviewer Agent
quality_reviewer = RCrewAI::Agent.new(
  name: "quality_reviewer",
  role: "Senior Code Quality Specialist",
  goal: "Ensure code maintainability, readability, and adherence to best practices",
  backstory: "You are a senior developer with expertise in clean code principles, design patterns, and software architecture. You excel at identifying code smells and suggesting refactoring improvements.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Documentation Specialist Agent
documentation_specialist = RCrewAI::Agent.new(
  name: "documentation_specialist", 
  role: "Technical Documentation Expert",
  goal: "Ensure comprehensive and clear code documentation",
  backstory: "You are a technical writer with deep programming knowledge who excels at creating clear, comprehensive documentation. You ensure code is well-documented for maintainability and knowledge transfer.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Integration Testing Specialist
testing_specialist = RCrewAI::Agent.new(
  name: "testing_specialist",
  role: "Software Testing and Integration Expert",
  goal: "Validate testing coverage and integration patterns",
  backstory: "You are a quality assurance expert specializing in automated testing, test coverage analysis, and integration patterns. You ensure code is properly tested and integrates well with existing systems.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Create code review crew
code_review_crew = RCrewAI::Crew.new("code_review_crew")

# Add agents to crew
code_review_crew.add_agent(security_analyst)
code_review_crew.add_agent(performance_specialist)
code_review_crew.add_agent(quality_reviewer)
code_review_crew.add_agent(documentation_specialist)
code_review_crew.add_agent(testing_specialist)

# ===== CODE REVIEW TASKS =====

# Security Review Task
security_review_task = RCrewAI::Task.new(
  name: "security_analysis",
  description: "Perform comprehensive security analysis of the provided code. Identify potential vulnerabilities including injection attacks, authentication issues, authorization problems, data exposure risks, and insecure configurations. Provide specific remediation recommendations for each issue found.",
  expected_output: "Detailed security analysis report with vulnerability findings, risk ratings (Critical/High/Medium/Low), and specific remediation steps",
  agent: security_analyst,
  async: true
)

# Performance Review Task
performance_review_task = RCrewAI::Task.new(
  name: "performance_analysis",
  description: "Analyze code for performance issues including algorithmic complexity, memory usage, database query optimization, caching opportunities, and resource management. Identify bottlenecks and suggest optimization strategies.",
  expected_output: "Performance analysis report with bottleneck identification, complexity analysis, and optimization recommendations with expected impact",
  agent: performance_specialist,
  async: true
)

# Code Quality Review Task
quality_review_task = RCrewAI::Task.new(
  name: "code_quality_review",
  description: "Review code for maintainability, readability, and adherence to coding standards. Identify code smells, design pattern violations, naming issues, and structural problems. Suggest refactoring improvements and architectural enhancements.",
  expected_output: "Code quality assessment with maintainability score, identified code smells, and refactoring recommendations",
  agent: quality_reviewer,
  async: true
)

# Documentation Review Task
documentation_review_task = RCrewAI::Task.new(
  name: "documentation_review", 
  description: "Evaluate code documentation completeness and clarity. Review function/method documentation, API documentation, README files, and inline comments. Identify missing documentation and suggest improvements.",
  expected_output: "Documentation assessment with completeness score, missing documentation identification, and improvement suggestions",
  agent: documentation_specialist,
  async: true
)

# Testing and Integration Review Task
testing_review_task = RCrewAI::Task.new(
  name: "testing_integration_review",
  description: "Assess test coverage, test quality, and integration patterns. Review unit tests, integration tests, and mocking strategies. Identify testing gaps and suggest improvements for better reliability.",
  expected_output: "Testing assessment with coverage analysis, test quality evaluation, and recommendations for improved testing strategy",
  agent: testing_specialist,
  async: true
)

# Add tasks to crew
code_review_crew.add_task(security_review_task)
code_review_crew.add_task(performance_review_task)
code_review_crew.add_task(quality_review_task)
code_review_crew.add_task(documentation_review_task)
code_review_crew.add_task(testing_review_task)

# ===== SAMPLE CODE FOR REVIEW =====

puts "📝 Creating Sample Code for Review"
puts "="*50

# Sample Ruby application with intentional issues for demonstration
sample_code = <<~RUBY
  # user_controller.rb
  class UserController < ApplicationController
    def show
      @user = User.find(params[:id])  # Potential security issue: no authorization
      render json: @user.to_json      # Potential data exposure
    end
    
    def create
      # SQL injection vulnerability
      user_data = "INSERT INTO users (name, email) VALUES ('#{params[:name]}', '#{params[:email]}')"
      ActiveRecord::Base.connection.execute(user_data)
      
      # Performance issue: N+1 query problem
      users = User.all
      users.each do |user|
        user.posts.each do |post|  # N+1 queries
          puts post.title
        end
      end
      
      redirect_to users_path
    end
    
    def update
      user = User.find(params[:id])
      
      # Security issue: mass assignment
      user.update(params[:user])
      
      # Performance issue: expensive operation in loop
      User.all.each do |u|
        u.calculate_score  # Expensive calculation
      end
      
      render json: { status: 'updated' }
    end
    
    # Missing documentation
    def complex_calculation(data)
      result = 0
      data.each do |item|
        if item > 0
          result += item * 2
        elsif item < 0
          result -= item
        else
          result += 1
        end
      end
      result
    end
    
    private
    
    def user_params
      params.require(:user).permit(:name, :email)  # Good practice but not used
    end
  end
  
  # user_service.rb
  class UserService
    def initialize
      @api_key = "sk-1234567890abcdef"  # Hardcoded secret
    end
    
    def process_users
      users = User.where("created_at > ?", 1.month.ago)  # Could be optimized
      
      # Memory issue: loading all records at once
      users.find_each(batch_size: 10000) do |user|
        process_user(user)
      end
    end
    
    def process_user(user)
      # No error handling
      response = HTTParty.get("https://api.example.com/users/#{user.id}", 
                             headers: { 'Authorization' => @api_key })
      
      # No validation
      user.update(external_id: response['id'])
    end
  end
RUBY

File.write("sample_code_for_review.rb", sample_code)

# Sample test file with issues
sample_tests = <<~RUBY
  # user_controller_spec.rb
  require 'rails_helper'
  
  RSpec.describe UserController, type: :controller do
    # Missing setup and context
    
    it "shows user" do
      user = User.create(name: "Test", email: "test@example.com")
      get :show, params: { id: user.id }
      expect(response).to be_successful
      # Missing assertions about response content
    end
    
    # Missing test cases:
    # - Authorization tests
    # - Error handling tests  
    # - Edge case tests
    # - Security tests
    
    it "creates user" do
      post :create, params: { name: "New User", email: "new@example.com" }
      expect(response).to redirect_to(users_path)
      # Missing validation of actual user creation
      # Missing test for SQL injection vulnerability
    end
  end
RUBY

File.write("sample_tests.rb", sample_tests)

puts "✅ Sample files created:"
puts "  - sample_code_for_review.rb (Ruby controller with various issues)"
puts "  - sample_tests.rb (Test file with coverage gaps)"

# ===== EXECUTE CODE REVIEW =====

puts "\n🔍 Starting Comprehensive Code Review"
puts "="*50

# Execute the code review crew
results = code_review_crew.execute

# ===== CODE REVIEW RESULTS =====

puts "\n📊 CODE REVIEW RESULTS"
puts "="*50

puts "Overall Review Completion: #{results[:success_rate]}%"
puts "Total Review Areas: #{results[:total_tasks]}"
puts "Completed Reviews: #{results[:completed_tasks]}"
puts "Review Status: #{results[:success_rate] >= 80 ? 'COMPLETE' : 'INCOMPLETE'}"

review_categories = {
  "security_analysis" => "🔒 Security Analysis",
  "performance_analysis" => "⚡ Performance Analysis", 
  "code_quality_review" => "✨ Code Quality Review",
  "documentation_review" => "📚 Documentation Review",
  "testing_integration_review" => "🧪 Testing & Integration"
}

puts "\n📋 REVIEW BREAKDOWN:"
puts "-"*40

results[:results].each do |review_result|
  task_name = review_result[:task].name
  category_name = review_categories[task_name] || task_name
  status_emoji = review_result[:status] == :completed ? "✅" : "❌"
  
  puts "#{status_emoji} #{category_name}"
  puts "   Reviewer: #{review_result[:assigned_agent] || review_result[:task].agent.name}"
  puts "   Status: #{review_result[:status]}"
  
  if review_result[:status] == :completed
    word_count = review_result[:result].split.length
    puts "   Analysis: #{word_count} words of detailed feedback"
  else
    puts "   Error: #{review_result[:error]&.message}"
  end
  puts
end

# ===== SAVE CODE REVIEW REPORTS =====

puts "\n💾 GENERATING CODE REVIEW REPORTS"
puts "-"*40

completed_reviews = results[:results].select { |r| r[:status] == :completed }

# Create review reports directory
review_dir = "code_review_#{Date.today.strftime('%Y%m%d')}"
Dir.mkdir(review_dir) unless Dir.exist?(review_dir)

review_reports = {}

completed_reviews.each do |review_result|
  task_name = review_result[:task].name
  review_content = review_result[:result]
  
  filename = "#{review_dir}/#{task_name}_report.md"
  review_reports[task_name] = filename
  
  formatted_report = <<~REPORT
    # #{review_categories[task_name] || task_name.split('_').map(&:capitalize).join(' ')} Report
    
    **Reviewer:** #{review_result[:assigned_agent] || review_result[:task].agent.name}  
    **Review Date:** #{Time.now.strftime('%B %d, %Y')}  
    **Code Files Reviewed:** sample_code_for_review.rb, sample_tests.rb
    
    ---
    
    #{review_content}
    
    ---
    
    **Review Methodology:**
    - Static code analysis
    - Best practices evaluation  
    - Industry standards compliance
    - Security vulnerability assessment
    
    *Generated by RCrewAI Code Review System*
  REPORT
  
  File.write(filename, formatted_report)
  puts "  ✅ #{File.basename(filename)}"
end

# ===== CONSOLIDATED CODE REVIEW SUMMARY =====

# Calculate overall scores and priorities
security_issues = completed_reviews.find { |r| r[:task].name == "security_analysis" }
performance_issues = completed_reviews.find { |r| r[:task].name == "performance_analysis" }
quality_issues = completed_reviews.find { |r| r[:task].name == "code_quality_review" }

summary_report = <<~SUMMARY
  # Code Review Summary Report
  
  **Review Date:** #{Time.now.strftime('%B %d, %Y')}  
  **Files Reviewed:** sample_code_for_review.rb, sample_tests.rb  
  **Review Completion:** #{results[:success_rate]}%
  
  ## Executive Summary
  
  The code review identified several areas requiring attention across security, performance, 
  code quality, documentation, and testing. While the code functions correctly, there are 
  important improvements needed before production deployment.
  
  ## Critical Issues Found
  
  ### 🔴 High Priority (Fix Immediately)
  - **SQL Injection Vulnerability** - Direct string interpolation in SQL queries
  - **Hardcoded API Keys** - Sensitive credentials in source code
  - **Missing Authorization** - No access control on user data endpoints
  - **Mass Assignment Vulnerability** - Unfiltered parameter updates
  
  ### 🟡 Medium Priority (Fix Before Production)
  - **N+1 Query Problem** - Inefficient database access patterns
  - **Missing Error Handling** - No exception handling for external API calls
  - **Insufficient Test Coverage** - Critical security scenarios not tested
  - **Performance Inefficiencies** - Expensive operations in loops
  
  ### 🟢 Low Priority (Improvement Opportunities)  
  - **Missing Documentation** - Method documentation incomplete
  - **Code Organization** - Opportunities for better structure
  - **Naming Conventions** - Some inconsistencies in naming
  
  ## Review Details by Category
  
  #{completed_reviews.map do |review|
    category = review_categories[review[:task].name]
    "### #{category}\n**Status:** Completed\n**Report:** #{review_reports[review[:task].name]}\n"
  end.join("\n")}
  
  ## Recommendations for Development Team
  
  ### Immediate Actions Required
  1. **Fix Security Vulnerabilities** - Address all high-priority security issues
  2. **Remove Hardcoded Secrets** - Move API keys to environment variables
  3. **Add Authorization Checks** - Implement proper access controls
  4. **Sanitize Database Queries** - Use parameterized queries or ORM methods
  
  ### Process Improvements
  1. **Automated Security Scanning** - Integrate tools like Brakeman or CodeQL
  2. **Performance Monitoring** - Add APM tools to catch performance issues
  3. **Code Quality Gates** - Implement automated quality checks in CI/CD
  4. **Security Training** - Team training on secure coding practices
  
  ## Quality Metrics
  
  - **Security Score:** #{security_issues ? 'C-' : 'Not Available'} (Critical issues found)
  - **Performance Score:** #{performance_issues ? 'C+' : 'Not Available'} (Multiple inefficiencies)  
  - **Code Quality Score:** #{quality_issues ? 'B-' : 'Not Available'} (Good structure, needs cleanup)
  - **Test Coverage:** Estimated 40% (Insufficient for production)
  - **Documentation Coverage:** Estimated 30% (Needs significant improvement)
  
  ## Next Steps
  
  1. **Developer Review Meeting** - Discuss findings with development team
  2. **Priority Issue Fixing** - Address critical and high priority items first
  3. **Process Integration** - Integrate automated code review into workflow
  4. **Follow-up Review** - Schedule review after fixes are implemented
  
  ## Tools and Resources Recommended
  
  ### Security Tools
  - **Brakeman** - Rails security scanner
  - **bundler-audit** - Gem vulnerability checking
  - **OWASP ZAP** - Dynamic security testing
  
  ### Performance Tools  
  - **Bullet** - N+1 query detection
  - **Rack Mini Profiler** - Performance profiling
  - **New Relic/DataDog** - APM monitoring
  
  ### Code Quality Tools
  - **RuboCop** - Ruby style and quality checker
  - **Reek** - Code smell detection
  - **SimpleCov** - Test coverage analysis
  
  ---
  
  **Next Review Date:** #{(Date.today + 14).strftime('%B %d, %Y')}  
  **Review Type:** Follow-up after issue remediation
  
  *This comprehensive code review was conducted by the RCrewAI automated code review system, providing objective analysis across multiple quality dimensions.*
SUMMARY

File.write("#{review_dir}/CODE_REVIEW_SUMMARY.md", summary_report)
puts "  ✅ CODE_REVIEW_SUMMARY.md"

# ===== ACTION ITEMS TRACKING =====

action_items = {
  "critical_issues" => [
    {
      "title" => "Fix SQL Injection Vulnerability",
      "description" => "Replace string interpolation with parameterized queries",
      "priority" => "Critical",
      "estimated_effort" => "2 hours",
      "assignee" => "TBD"
    },
    {
      "title" => "Remove Hardcoded API Keys", 
      "description" => "Move secrets to environment variables",
      "priority" => "Critical",
      "estimated_effort" => "1 hour",
      "assignee" => "TBD"
    }
  ],
  "high_priority" => [
    {
      "title" => "Add Authorization Checks",
      "description" => "Implement proper access controls on all endpoints",
      "priority" => "High", 
      "estimated_effort" => "4 hours",
      "assignee" => "TBD"
    },
    {
      "title" => "Fix N+1 Query Issues",
      "description" => "Optimize database queries with includes/joins",
      "priority" => "High",
      "estimated_effort" => "3 hours", 
      "assignee" => "TBD"
    }
  ],
  "medium_priority" => [
    {
      "title" => "Add Error Handling",
      "description" => "Implement proper exception handling for external APIs",
      "priority" => "Medium",
      "estimated_effort" => "2 hours",
      "assignee" => "TBD"
    },
    {
      "title" => "Improve Test Coverage",
      "description" => "Add security and edge case tests",
      "priority" => "Medium", 
      "estimated_effort" => "6 hours",
      "assignee" => "TBD"
    }
  ]
}

File.write("#{review_dir}/action_items.json", JSON.pretty_generate(action_items))
puts "  ✅ action_items.json"

puts "\n🎉 CODE REVIEW COMPLETED!"
puts "="*50
puts "📁 Complete review package saved to: #{review_dir}/"
puts ""
puts "🔍 **Review Summary:**"
puts "   • #{completed_reviews.length} analysis areas completed"
puts "   • Critical security issues identified and documented"
puts "   • Performance bottlenecks highlighted with solutions"
puts "   • Code quality improvements recommended"
puts "   • Testing gaps identified with specific recommendations"
puts ""
puts "⚠️ **Critical Actions Required:**"
puts "   • Fix SQL injection vulnerability (URGENT)"
puts "   • Remove hardcoded API keys (URGENT)"
puts "   • Implement authorization checks"
puts "   • Address N+1 query performance issues"
puts ""
puts "📅 **Recommended Timeline:**"
puts "   • Critical fixes: Within 24 hours"
puts "   • High priority: Within 1 week" 
puts "   • Medium priority: Within 2 weeks"
puts "   • Follow-up review: In 2 weeks"
```

## Advanced Code Review Features

### 1. **Multi-Dimensional Analysis**
Each specialist focuses on their expertise area:

```ruby
security_analyst     # OWASP Top 10, vulnerability analysis
performance_specialist  # Algorithmic complexity, bottlenecks
quality_reviewer        # Clean code, maintainability  
documentation_specialist # Technical writing, completeness
testing_specialist      # Coverage, integration patterns
```

### 2. **Parallel Review Process**
All review areas are analyzed simultaneously:

```ruby
# All review tasks run in parallel
security_review_task.async = true
performance_review_task.async = true  
quality_review_task.async = true
documentation_review_task.async = true
testing_review_task.async = true
```

### 3. **Comprehensive Reporting**
Generates detailed reports for each area plus consolidated summary:

- Individual specialist reports
- Executive summary with priorities
- Action items with effort estimates
- Tool recommendations
- Follow-up schedule

### 4. **Actionable Recommendations**
Each finding includes specific remediation steps:

```ruby
# Example security finding
"SQL Injection Vulnerability in UserController#create
Risk: Critical
Fix: Replace string interpolation with User.create(user_params)
Effort: 2 hours"
```

## Integration Patterns

### CI/CD Integration
```ruby
# Add to your CI pipeline
class CodeReviewPipeline
  def self.review_pull_request(pr_files)
    review_crew = CodeReviewCrew.new
    review_crew.analyze_files(pr_files)
    
    if review_crew.has_critical_issues?
      fail_build_with_report(review_crew.report)
    else
      post_review_comments(review_crew.suggestions)
    end
  end
end
```

### IDE Integration
```ruby
# Real-time code analysis
class IDECodeReview
  def analyze_on_save(file_path)
    quick_review = CodeReviewCrew.new(mode: :quick)
    issues = quick_review.analyze_file(file_path)
    
    display_inline_warnings(issues)
  end
end
```

### Team Workflow Integration
```ruby
# Slack notifications for review results
class ReviewNotifier
  def notify_team(review_results)
    if review_results.has_critical_issues?
      send_urgent_slack_message(review_results.critical_issues)
    end
    
    create_jira_tickets(review_results.action_items)
  end
end
```

This automated code review system provides comprehensive analysis across all critical dimensions of code quality, helping teams identify and fix issues before they reach production while maintaining high development velocity.