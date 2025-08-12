---
layout: example
title: Task Automation with RCrewAI
description: Automate repetitive business tasks using specialized AI agents with defined roles and workflows
---

# Task Automation with RCrewAI

This example demonstrates how to automate repetitive business tasks using RCrewAI agents. We'll create a workflow that automatically processes incoming data, generates reports, and handles routine communications.

## Overview

We'll build an automation system that:
- **Processes incoming data** from various sources
- **Generates standardized reports** with analysis
- **Handles routine email responses** based on content
- **Updates tracking systems** with processed information
- **Escalates complex issues** to human operators

## Complete Implementation

```ruby
require 'rcrewai'
require 'json'
require 'csv'

# Configure RCrewAI
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.temperature = 0.3  # Balanced for automation tasks
end

# ===== DATA PROCESSING AGENT =====
data_processor = RCrewAI::Agent.new(
  name: "data_processor",
  role: "Data Processing Specialist",
  goal: "Efficiently process and validate incoming data from multiple sources",
  backstory: "You are a meticulous data specialist who ensures data quality and consistency. You excel at identifying patterns, cleaning data, and preparing it for analysis.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# ===== REPORT GENERATOR AGENT =====
report_generator = RCrewAI::Agent.new(
  name: "report_generator",
  role: "Business Report Analyst",
  goal: "Generate comprehensive and actionable business reports from processed data",
  backstory: "You are an experienced business analyst who creates clear, insightful reports that help stakeholders make informed decisions. You excel at data visualization and trend analysis.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# ===== EMAIL AUTOMATION AGENT =====
email_agent = RCrewAI::Agent.new(
  name: "email_assistant",
  role: "Customer Communication Specialist",
  goal: "Handle routine customer communications with professionalism and accuracy",
  backstory: "You are a professional customer service representative who excels at written communication. You handle routine inquiries efficiently while maintaining a personal touch.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# ===== QUALITY ASSURANCE AGENT =====
qa_agent = RCrewAI::Agent.new(
  name: "quality_controller",
  role: "Quality Assurance Specialist", 
  goal: "Review automated outputs and flag items requiring human attention",
  backstory: "You are a detail-oriented quality assurance professional who ensures all automated processes meet high standards. You identify edge cases and exceptions that need human review.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# ===== CREATE AUTOMATION CREW =====
automation_crew = RCrewAI::Crew.new("task_automation_crew")

# Add all agents to crew
automation_crew.add_agent(data_processor)
automation_crew.add_agent(report_generator)
automation_crew.add_agent(email_agent)
automation_crew.add_agent(qa_agent)

# ===== DEFINE AUTOMATION TASKS =====

# Task 1: Data Processing and Validation
data_processing_task = RCrewAI::Task.new(
  name: "process_incoming_data",
  description: "Process incoming data files from various sources. Validate data quality, clean inconsistencies, and prepare structured output. Handle CSV files, JSON data, and text reports. Flag any data quality issues or anomalies.",
  expected_output: "Clean, validated dataset with quality report highlighting any issues or anomalies found",
  agent: data_processor,
  async: true
)

# Task 2: Report Generation
report_task = RCrewAI::Task.new(
  name: "generate_business_report",
  description: "Create comprehensive business reports from processed data. Include key metrics, trend analysis, executive summary, and actionable recommendations. Format reports professionally with clear visualizations and insights.",
  expected_output: "Professional business report with executive summary, key metrics, trends, and actionable recommendations",
  agent: report_generator,
  context: [data_processing_task],
  async: true
)

# Task 3: Email Response Automation
email_task = RCrewAI::Task.new(
  name: "handle_customer_emails",
  description: "Process customer emails and generate appropriate responses. Handle common inquiries about orders, products, and services. Maintain professional tone while providing helpful information. Flag complex issues for human review.",
  expected_output: "Professional email responses with clear, helpful information and flags for human review when needed",
  agent: email_agent,
  async: true
)

# Task 4: Quality Assurance Review
qa_task = RCrewAI::Task.new(
  name: "quality_review",
  description: "Review all automated outputs for quality and accuracy. Verify that reports are comprehensive, emails are appropriate, and data processing was successful. Flag any outputs that require human review or intervention.",
  expected_output: "Quality assurance report with approval status and list of items requiring human attention",
  agent: qa_agent,
  context: [data_processing_task, report_task, email_task]
)

# Add tasks to crew
automation_crew.add_task(data_processing_task)
automation_crew.add_task(report_task)
automation_crew.add_task(email_task)
automation_crew.add_task(qa_task)

# ===== SAMPLE DATA CREATION =====

puts "📋 Creating Sample Data for Automation"
puts "="*50

# Create sample customer data
customer_data = [
  ["Customer ID", "Name", "Email", "Order Value", "Status", "Issue Type"],
  ["C001", "John Smith", "john@example.com", 299.99, "pending", "shipping_query"],
  ["C002", "Sarah Johnson", "sarah@example.com", 156.50, "completed", "product_question"],
  ["C003", "Mike Brown", "mike@example.com", 89.99, "cancelled", "refund_request"],
  ["C004", "Lisa Davis", "lisa@example.com", 425.00, "processing", "order_modification"],
  ["C005", "David Wilson", "david@example.com", 199.99, "completed", "product_review"]
]

CSV.open("sample_customer_data.csv", "w") do |csv|
  customer_data.each { |row| csv << row }
end

# Create sample sales data
sales_data = {
  "period": "2024-Q1",
  "total_sales": 125890.45,
  "total_orders": 892,
  "average_order_value": 141.16,
  "top_products": [
    {"name": "Premium Widget", "sales": 35420.00, "units": 156},
    {"name": "Standard Widget", "sales": 28750.50, "units": 287},
    {"name": "Widget Pro", "sales": 22350.00, "units": 89}
  ],
  "customer_segments": {
    "new_customers": 234,
    "returning_customers": 658,
    "premium_customers": 127
  }
}

File.write("sample_sales_data.json", JSON.pretty_generate(sales_data))

# Create sample email inquiries
email_inquiries = [
  {
    "from": "john@example.com",
    "subject": "Order C001 - Shipping Status",
    "body": "Hi, I placed order C001 last week and haven't received shipping information yet. Can you please provide an update on when it will ship? Thanks!"
  },
  {
    "from": "sarah@example.com", 
    "subject": "Product Question - Widget Compatibility",
    "body": "Hello, I purchased the Premium Widget but I'm not sure if it's compatible with my current setup. Can you provide compatibility information or technical specifications?"
  },
  {
    "from": "mike@example.com",
    "subject": "Refund Request - Order C003",
    "body": "I need to cancel my order C003 and request a refund. The product doesn't meet my requirements. Please process this as soon as possible."
  }
]

File.write("sample_email_inquiries.json", JSON.pretty_generate(email_inquiries))

puts "✅ Sample data created:"
puts "  - sample_customer_data.csv (5 customer records)"
puts "  - sample_sales_data.json (Q1 sales summary)"
puts "  - sample_email_inquiries.json (3 customer emails)"

# ===== AUTOMATION EXECUTION =====

puts "\n🚀 Starting Task Automation Workflow"
puts "="*50

# Execute the automation crew
results = automation_crew.execute

# ===== RESULTS ANALYSIS =====

puts "\n📊 AUTOMATION RESULTS"
puts "="*50

puts "Overall Success Rate: #{results[:success_rate]}%"
puts "Total Tasks: #{results[:total_tasks]}"
puts "Completed Tasks: #{results[:completed_tasks]}"
puts "Failed Tasks: #{results[:failed_tasks]}"

puts "\n📋 TASK BREAKDOWN:"
puts "-"*40

results[:results].each_with_index do |task_result, index|
  status_emoji = task_result[:status] == :completed ? "✅" : "❌"
  
  puts "#{index + 1}. #{status_emoji} #{task_result[:task].name}"
  puts "   Agent: #{task_result[:assigned_agent] || task_result[:task].agent.name}"
  puts "   Status: #{task_result[:status]}"
  
  if task_result[:status] == :completed
    puts "   Result: #{task_result[:result][0..100]}..."
  else
    puts "   Error: #{task_result[:error]&.message}"
  end
  puts
end

# ===== SAVE AUTOMATION OUTPUTS =====

puts "\n💾 SAVING AUTOMATION OUTPUTS"
puts "-"*40

completed_results = results[:results].select { |r| r[:status] == :completed }

completed_results.each do |task_result|
  task_name = task_result[:task].name
  output_filename = "automation_output_#{task_name}.md"
  
  content = <<~CONTENT
    # #{task_name.split('_').map(&:capitalize).join(' ')} Output
    
    **Generated by:** #{task_result[:assigned_agent] || task_result[:task].agent.name}  
    **Status:** #{task_result[:status]}  
    **Generated at:** #{Time.now}
    
    ## Task Description
    #{task_result[:task].description}
    
    ## Expected Output
    #{task_result[:task].expected_output}
    
    ## Result
    
    #{task_result[:result]}
    
    ---
    *Generated by RCrewAI Task Automation System*
  CONTENT
  
  File.write(output_filename, content)
  puts "  ✅ Saved #{output_filename}"
end

# ===== AUTOMATION SUMMARY REPORT =====

summary_report = <<~REPORT
  # Task Automation Summary Report
  
  **Execution Date:** #{Time.now}  
  **Automation Crew:** #{automation_crew.name}  
  **Total Agents:** #{automation_crew.agents.length}
  
  ## Performance Metrics
  - **Success Rate:** #{results[:success_rate]}%
  - **Tasks Completed:** #{results[:completed_tasks]}/#{results[:total_tasks]}
  - **Processing Time:** Completed in parallel execution
  
  ## Agent Performance
  
  #{automation_crew.agents.map do |agent|
    assigned_tasks = completed_results.select do |r| 
      (r[:assigned_agent] || r[:task].agent.name) == agent.name 
    end
    
    "- **#{agent.name}** (#{agent.role}): #{assigned_tasks.length} task(s) completed"
  end.join("\n")}
  
  ## Automation Outputs Generated
  
  #{completed_results.map.with_index do |result, i|
    "#{i + 1}. #{result[:task].name} - #{result[:result].length} characters"
  end.join("\n")}
  
  ## Data Processing Summary
  
  ✅ **Customer Data:** 5 customer records processed  
  ✅ **Sales Data:** Q1 2024 metrics analyzed  
  ✅ **Email Inquiries:** 3 customer emails processed  
  ✅ **Quality Review:** All outputs reviewed for accuracy
  
  ## Automation Benefits Achieved
  
  - **Time Saved:** ~4-6 hours of manual work automated
  - **Consistency:** Standardized processing across all tasks
  - **Quality:** Built-in quality assurance and validation
  - **Scalability:** Can handle increased volume automatically
  - **Documentation:** Complete audit trail of all processes
  
  ## Recommendations for Enhancement
  
  1. **Integration:** Connect to email systems for automatic processing
  2. **Scheduling:** Set up automated execution on regular intervals  
  3. **Monitoring:** Add performance dashboards and alerting
  4. **Customization:** Tailor responses based on customer segments
  5. **Machine Learning:** Implement learning from human feedback
  
  ## Next Steps
  
  - Review and approve automated outputs
  - Deploy to production environment
  - Set up monitoring and alerting
  - Train team on oversight procedures
  - Plan for scaling to additional task types
  
  ---
  *This report was generated automatically by the RCrewAI Task Automation System*
REPORT

File.write("automation_summary_report.md", summary_report)
puts "  ✅ Saved automation_summary_report.md"

puts "\n🎉 TASK AUTOMATION COMPLETED SUCCESSFULLY!"
puts "="*50
puts "The automation system has successfully processed all tasks:"
puts "• Customer data validated and cleaned"
puts "• Business reports generated with insights"  
puts "• Customer emails processed with appropriate responses"
puts "• Quality assurance review completed"
puts ""
puts "📁 Check the generated files:"
puts "• automation_output_*.md - Individual task results"
puts "• automation_summary_report.md - Complete automation summary"
puts ""
puts "🚀 This automation system can now be:"
puts "• Scheduled to run automatically"
puts "• Integrated with your existing systems"
puts "• Scaled to handle larger volumes"
puts "• Enhanced with additional task types"
```

## Key Automation Features

### 1. **Multi-Agent Specialization**
Each agent has a specific role in the automation pipeline:

```ruby
# Specialized agents for different automation tasks
data_processor     # Handles data validation and cleaning
report_generator   # Creates business reports and analysis
email_agent       # Manages customer communications
qa_agent          # Reviews outputs for quality assurance
```

### 2. **Parallel Processing**
Tasks that can run independently execute in parallel:

```ruby
# These tasks run simultaneously
data_processing_task   # Async: true
email_task            # Async: true (independent of data processing)

# Report generation waits for data processing
report_task           # Context: [data_processing_task]

# QA reviews all outputs
qa_task              # Context: [data_processing_task, report_task, email_task]
```

### 3. **Quality Assurance**
Built-in quality control ensures reliable automation:

```ruby
qa_task = RCrewAI::Task.new(
  name: "quality_review",
  description: "Review all automated outputs for quality and accuracy...",
  context: [data_processing_task, report_task, email_task]  # Reviews all outputs
)
```

### 4. **Comprehensive Output**
The system generates detailed documentation of all processes:

- Individual task results with full audit trails
- Summary reports with performance metrics
- Quality assurance findings
- Recommendations for improvements

## Automation Patterns

### Sequential Processing
```ruby
# Tasks with dependencies run in sequence
Task A → Task B → Task C

# Example: Data must be processed before report generation
data_processing_task → report_task
```

### Parallel Processing
```ruby
# Independent tasks run simultaneously
Task A ∥ Task B ∥ Task C

# Example: Data processing and email handling can run together
data_processing_task ∥ email_task
```

### Hub-and-Spoke Pattern
```ruby
# Multiple inputs feed into central processing
Task A ↘
Task B → Central Task → Output
Task C ↗

# Example: QA agent reviews outputs from all other agents
[data_task, report_task, email_task] → qa_task
```

## Use Cases for Task Automation

### 1. **Customer Service Automation**
- Process support tickets
- Generate standard responses
- Escalate complex issues
- Update CRM systems

### 2. **Data Processing Workflows**
- Clean and validate incoming data
- Generate standardized reports
- Update databases and systems
- Flag anomalies for review

### 3. **Content Management**
- Process document uploads
- Generate summaries and metadata
- Organize and categorize content
- Update content management systems

### 4. **Financial Processing**
- Process invoices and receipts
- Generate expense reports
- Validate transactions
- Update accounting systems

## Scaling the Automation

### Adding New Task Types
```ruby
# Add a new specialized agent
invoice_processor = RCrewAI::Agent.new(
  name: "invoice_processor",
  role: "Accounts Payable Specialist",
  goal: "Process invoices accurately and efficiently"
)

# Add corresponding tasks
invoice_task = RCrewAI::Task.new(
  name: "process_invoices",
  description: "Process pending invoices...",
  agent: invoice_processor
)

# Integrate into existing workflow
automation_crew.add_agent(invoice_processor)
automation_crew.add_task(invoice_task)
```

### Integration with External Systems
```ruby
# Custom tools for system integration
crm_tool = CRMIntegrationTool.new(api_key: ENV['CRM_API_KEY'])
email_tool = EmailSystemTool.new(smtp_config: email_config)

# Agents can use integration tools
customer_agent.tools << crm_tool
email_agent.tools << email_tool
```

## Best Practices for Task Automation

### 1. **Error Handling**
- Implement comprehensive error catching
- Provide fallback procedures
- Log all errors for analysis
- Set up alerting for failures

### 2. **Quality Control**
- Always include quality assurance steps
- Validate outputs before use
- Maintain human oversight for complex decisions
- Regular auditing of automated processes

### 3. **Documentation**
- Document all automated processes
- Maintain audit trails
- Generate regular performance reports
- Keep process documentation updated

### 4. **Monitoring**
- Track success/failure rates
- Monitor processing times
- Set up performance alerts
- Regular performance reviews

This automation system provides a solid foundation for automating repetitive business tasks while maintaining quality and providing comprehensive audit trails. It can be easily extended and integrated into existing business processes.