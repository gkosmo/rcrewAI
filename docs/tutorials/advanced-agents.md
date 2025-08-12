---
layout: tutorial
title: Advanced Agent Configuration
description: Master advanced agent features including memory, custom reasoning, delegation, and performance optimization
---

# Advanced Agent Configuration

This tutorial covers advanced agent configuration techniques including memory systems, custom reasoning loops, delegation patterns, performance optimization, and specialized agent behaviors.

## Table of Contents
1. [Agent Memory Systems](#agent-memory-systems)
2. [Custom Reasoning Loops](#custom-reasoning-loops)
3. [Manager Agents and Delegation](#manager-agents-and-delegation)
4. [Performance Optimization](#performance-optimization)
5. [Specialized Agent Behaviors](#specialized-agent-behaviors)
6. [Agent Communication Patterns](#agent-communication-patterns)
7. [Error Handling and Recovery](#error-handling-and-recovery)

## Agent Memory Systems

Agents in RCrewAI have sophisticated memory systems that allow them to learn and improve over time.

### Short-term and Long-term Memory

```ruby
require 'rcrewai'

# Create agent with enhanced memory capabilities
analyst = RCrewAI::Agent.new(
  name: "data_analyst",
  role: "Senior Data Analyst",
  goal: "Analyze data patterns and learn from past analyses",
  backstory: "Expert analyst who improves with each analysis",
  verbose: true
)

# Memory is automatically created and managed
memory = analyst.memory

# After task execution, memory stores:
# - Successful patterns and strategies
# - Tool usage that worked well
# - Context that led to good results
# - Failed approaches to avoid

# Access memory statistics
stats = memory.stats
puts "Total executions: #{stats[:total_executions]}"
puts "Success rate: #{stats[:success_rate]}%"
puts "Most used tools: #{stats[:top_tools]}"
puts "Average execution time: #{stats[:avg_execution_time]}s"

# Memory influences future reasoning
# Agent will prefer successful patterns from memory
```

### Custom Memory Persistence

```ruby
class PersistentMemoryAgent < RCrewAI::Agent
  def initialize(**options)
    super
    load_memory_from_storage
  end
  
  def execute_task(task)
    result = super
    save_memory_to_storage
    result
  end
  
  private
  
  def load_memory_from_storage
    if File.exist?("#{name}_memory.json")
      memory_data = JSON.parse(File.read("#{name}_memory.json"))
      @memory.restore(memory_data)
    end
  end
  
  def save_memory_to_storage
    File.write("#{name}_memory.json", @memory.to_json)
  end
end

# Agent that remembers across sessions
persistent_agent = PersistentMemoryAgent.new(
  name: "persistent_researcher",
  role: "Research Specialist",
  goal: "Build knowledge over time"
)
```

### Memory-Enhanced Learning

```ruby
# Create a learning agent that improves over time
learning_agent = RCrewAI::Agent.new(
  name: "learning_assistant",
  role: "Adaptive Assistant",
  goal: "Learn from each interaction to provide better assistance",
  backstory: "An AI that continuously improves through experience",
  tools: [RCrewAI::Tools::WebSearch.new, RCrewAI::Tools::FileWriter.new]
)

# Track performance over multiple executions
10.times do |i|
  task = RCrewAI::Task.new(
    name: "research_task_#{i}",
    description: "Research topic #{i}",
    agent: learning_agent
  )
  
  result = task.execute
  
  # Agent automatically learns:
  # - Which search queries work best
  # - How to structure research
  # - Optimal tool usage patterns
  
  puts "Iteration #{i}: Success=#{task.status == :completed}"
end

# Check improvement
puts "Learning progress: #{learning_agent.memory.learning_curve}"
```

## Custom Reasoning Loops

Advanced agents can have customized reasoning processes for specialized tasks.

### Custom Reasoning Agent

```ruby
class AnalyticalReasoningAgent < RCrewAI::Agent
  def reasoning_loop(task, context)
    iteration = 0
    hypotheses = []
    
    loop do
      iteration += 1
      
      # Phase 1: Generate hypotheses
      if iteration == 1
        hypotheses = generate_hypotheses(task, context)
        @logger.info "Generated #{hypotheses.length} hypotheses"
      end
      
      # Phase 2: Test hypotheses
      if iteration > 1 && iteration <= hypotheses.length + 1
        hypothesis = hypotheses[iteration - 2]
        result = test_hypothesis(hypothesis, context)
        
        if result[:valid]
          return formulate_conclusion(hypothesis, result)
        end
      end
      
      # Phase 3: Synthesize findings
      if iteration > hypotheses.length + 1
        return synthesize_findings(hypotheses, context)
      end
      
      break if iteration > max_iterations
    end
  end
  
  private
  
  def generate_hypotheses(task, context)
    prompt = build_hypothesis_prompt(task, context)
    response = llm_client.chat(messages: [{ role: 'user', content: prompt }])
    parse_hypotheses(response[:content])
  end
  
  def test_hypothesis(hypothesis, context)
    # Use tools to validate hypothesis
    if tools.any? { |t| t.name == 'websearch' }
      evidence = use_tool('websearch', query: hypothesis[:query])
      { valid: evidence.include?(hypothesis[:expected]), evidence: evidence }
    else
      { valid: false, evidence: nil }
    end
  end
  
  def formulate_conclusion(hypothesis, result)
    "Conclusion: #{hypothesis[:statement]} is supported by evidence: #{result[:evidence]}"
  end
  
  def synthesize_findings(hypotheses, context)
    "Unable to validate hypotheses. Best assessment based on available data..."
  end
end

# Use the analytical reasoning agent
analyst = AnalyticalReasoningAgent.new(
  name: "hypothesis_tester",
  role: "Scientific Analyst",
  goal: "Test hypotheses systematically",
  tools: [RCrewAI::Tools::WebSearch.new]
)
```

### Multi-Stage Reasoning

```ruby
class MultiStageReasoningAgent < RCrewAI::Agent
  REASONING_STAGES = [
    :understand,
    :analyze,
    :plan,
    :execute,
    :verify,
    :conclude
  ]
  
  def reasoning_loop(task, context)
    current_stage_index = 0
    stage_results = {}
    
    while current_stage_index < REASONING_STAGES.length
      stage = REASONING_STAGES[current_stage_index]
      
      @logger.info "Reasoning stage: #{stage}"
      
      result = case stage
      when :understand
        understand_requirements(task, context)
      when :analyze
        analyze_problem(task, context, stage_results[:understand])
      when :plan
        create_action_plan(stage_results[:analyze])
      when :execute
        execute_plan(stage_results[:plan])
      when :verify
        verify_results(stage_results[:execute])
      when :conclude
        formulate_conclusion(stage_results)
      end
      
      stage_results[stage] = result
      
      # Allow stage retry on failure
      if result[:success]
        current_stage_index += 1
      elsif result[:retry]
        @logger.info "Retrying stage: #{stage}"
      else
        break
      end
    end
    
    stage_results[:conclude] || "Reasoning incomplete"
  end
end
```

## Manager Agents and Delegation

Manager agents coordinate teams and delegate tasks intelligently.

### Creating a Manager Agent

```ruby
# Create a manager with delegation capabilities
manager = RCrewAI::Agent.new(
  name: "team_manager",
  role: "Engineering Manager",
  goal: "Coordinate team to deliver projects efficiently",
  backstory: "Experienced manager who knows how to leverage team strengths",
  manager: true,              # Mark as manager
  allow_delegation: true,     # Enable delegation
  tools: [RCrewAI::Tools::FileWriter.new],  # Manager tools
  verbose: true
)

# Create specialist team members
backend_dev = RCrewAI::Agent.new(
  name: "backend_developer",
  role: "Backend Engineer",
  goal: "Build robust backend systems",
  tools: [RCrewAI::Tools::FileWriter.new]
)

frontend_dev = RCrewAI::Agent.new(
  name: "frontend_developer",
  role: "Frontend Engineer",
  goal: "Create excellent user interfaces",
  tools: [RCrewAI::Tools::FileWriter.new]
)

qa_engineer = RCrewAI::Agent.new(
  name: "qa_engineer",
  role: "QA Engineer",
  goal: "Ensure software quality",
  tools: [RCrewAI::Tools::FileReader.new]
)

# Build team hierarchy
manager.add_subordinate(backend_dev)
manager.add_subordinate(frontend_dev)
manager.add_subordinate(qa_engineer)

# Manager will automatically delegate tasks to appropriate team members
```

### Advanced Delegation Strategies

```ruby
class StrategicManager < RCrewAI::Agent
  def delegate_task(task, target_agent = nil)
    if target_agent.nil?
      # Intelligent agent selection based on multiple factors
      target_agent = select_best_agent(task)
    end
    
    # Create delegation context with strategic guidance
    delegation_context = {
      priority: assess_priority(task),
      deadline: calculate_deadline(task),
      resources: allocate_resources(task),
      success_criteria: define_success_criteria(task),
      escalation_path: define_escalation(task)
    }
    
    # Enhanced delegation with context
    @logger.info "Delegating #{task.name} to #{target_agent.name}"
    @logger.info "Context: #{delegation_context}"
    
    super(task, target_agent)
  end
  
  private
  
  def select_best_agent(task)
    # Score each subordinate for task fit
    scores = subordinates.map do |agent|
      score = 0
      
      # Factor 1: Role match
      role_match = calculate_role_match(task, agent)
      score += role_match * 0.4
      
      # Factor 2: Current workload
      workload = assess_workload(agent)
      score += (1.0 - workload) * 0.3
      
      # Factor 3: Past performance
      performance = agent.memory.stats[:success_rate] || 0.5
      score += performance * 0.2
      
      # Factor 4: Tool availability
      tool_match = calculate_tool_match(task, agent)
      score += tool_match * 0.1
      
      { agent: agent, score: score }
    end
    
    # Select highest scoring agent
    best = scores.max_by { |s| s[:score] }
    best[:agent]
  end
  
  def calculate_role_match(task, agent)
    task_keywords = extract_keywords(task.description)
    role_keywords = extract_keywords(agent.role)
    
    common = (task_keywords & role_keywords).length
    total = [task_keywords.length, role_keywords.length].max
    
    common.to_f / total
  end
  
  def assess_workload(agent)
    # Return workload between 0 (idle) and 1 (overloaded)
    active_tasks = @delegated_tasks[agent.name] || []
    active_tasks.count { |t| t.status == :running } / 5.0
  end
end
```

### Cross-Team Coordination

```ruby
# Multiple managers coordinating
engineering_manager = RCrewAI::Agent.new(
  name: "eng_manager",
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

# Managers can coordinate through shared context
shared_context = {
  project_goals: "Launch new feature by Q2",
  constraints: "Limited to 3 engineers",
  priorities: ["Performance", "User Experience", "Security"]
}

# Create tasks that require cross-team coordination
feature_task = RCrewAI::Task.new(
  name: "new_feature",
  description: "Implement new dashboard feature",
  context_data: shared_context
)

# Both managers will coordinate their teams
```

## Performance Optimization

Optimize agent performance for production workloads.

### Parallel Agent Execution

```ruby
# Configure agents for parallel execution
fast_researcher = RCrewAI::Agent.new(
  name: "fast_researcher",
  role: "Research Specialist",
  goal: "Quickly gather information",
  max_iterations: 3,          # Limit iterations
  max_execution_time: 60,     # 1 minute timeout
  tools: [RCrewAI::Tools::WebSearch.new(timeout: 10)]  # Fast timeout
)

# Create parallel tasks
parallel_tasks = 5.times.map do |i|
  RCrewAI::Task.new(
    name: "research_#{i}",
    description: "Research topic #{i}",
    agent: fast_researcher,
    async: true  # Mark for async execution
  )
end

# Execute in parallel
crew = RCrewAI::Crew.new("parallel_crew")
crew.add_agent(fast_researcher)
parallel_tasks.each { |t| crew.add_task(t) }

results = crew.execute(async: true, max_concurrency: 5)
```

### Resource-Optimized Agents

```ruby
class ResourceOptimizedAgent < RCrewAI::Agent
  def initialize(**options)
    super
    @resource_monitor = ResourceMonitor.new
  end
  
  def execute_task(task)
    # Check resources before execution
    if @resource_monitor.memory_usage > 0.8
      @logger.warn "High memory usage, optimizing..."
      optimize_memory
    end
    
    # Use chunked processing for large tasks
    if task.estimated_size > 1_000_000
      execute_chunked(task)
    else
      super
    end
  end
  
  private
  
  def execute_chunked(task)
    chunks = split_task(task)
    results = []
    
    chunks.each_with_index do |chunk, i|
      @logger.info "Processing chunk #{i+1}/#{chunks.length}"
      
      # Process chunk with resource limits
      result = with_resource_limits do
        process_chunk(chunk)
      end
      
      results << result
      
      # Clear memory between chunks
      GC.start if i % 5 == 0
    end
    
    merge_results(results)
  end
  
  def with_resource_limits(&block)
    Thread.new do
      Thread.current[:memory_limit] = 100_000_000  # 100MB
      Thread.current[:time_limit] = 30  # 30 seconds
      
      Timeout::timeout(Thread.current[:time_limit]) do
        yield
      end
    end.value
  end
end
```

### Caching and Memoization

```ruby
class CachedAgent < RCrewAI::Agent
  def initialize(**options)
    super
    @cache = {}
    @cache_ttl = options[:cache_ttl] || 3600  # 1 hour default
  end
  
  def use_tool(tool_name, **params)
    cache_key = "#{tool_name}_#{params.hash}"
    
    # Check cache first
    if cached = get_cached(cache_key)
      @logger.info "Cache hit for #{tool_name}"
      return cached
    end
    
    # Execute and cache
    result = super
    set_cached(cache_key, result)
    result
  end
  
  private
  
  def get_cached(key)
    return nil unless @cache[key]
    
    entry = @cache[key]
    if Time.now - entry[:time] < @cache_ttl
      entry[:value]
    else
      @cache.delete(key)
      nil
    end
  end
  
  def set_cached(key, value)
    @cache[key] = {
      value: value,
      time: Time.now
    }
    
    # Limit cache size
    if @cache.size > 100
      oldest = @cache.min_by { |k, v| v[:time] }
      @cache.delete(oldest[0])
    end
  end
end
```

## Specialized Agent Behaviors

Create agents with specialized behaviors for specific use cases.

### Research Specialist Agent

```ruby
class ResearchSpecialistAgent < RCrewAI::Agent
  def initialize(**options)
    super(options.merge(
      tools: [
        RCrewAI::Tools::WebSearch.new(max_results: 20),
        RCrewAI::Tools::FileWriter.new,
        RCrewAI::Tools::FileReader.new
      ]
    ))
    
    @research_depth = options[:research_depth] || 3
    @citation_style = options[:citation_style] || :apa
  end
  
  def execute_task(task)
    # Enhanced research methodology
    research_plan = create_research_plan(task)
    sources = gather_sources(research_plan)
    validated_sources = validate_sources(sources)
    synthesis = synthesize_findings(validated_sources)
    
    # Format with citations
    format_research_output(synthesis, validated_sources)
  end
  
  private
  
  def create_research_plan(task)
    {
      primary_queries: extract_key_topics(task.description),
      secondary_queries: generate_related_queries(task.description),
      depth_level: @research_depth,
      quality_threshold: 0.7
    }
  end
  
  def gather_sources(plan)
    sources = []
    
    # Primary research
    plan[:primary_queries].each do |query|
      results = use_tool('websearch', query: query, max_results: 10)
      sources.concat(parse_search_results(results))
    end
    
    # Deep research for important topics
    if @research_depth > 1
      plan[:secondary_queries].each do |query|
        results = use_tool('websearch', query: query, max_results: 5)
        sources.concat(parse_search_results(results))
      end
    end
    
    sources
  end
  
  def validate_sources(sources)
    sources.select do |source|
      score = calculate_source_credibility(source)
      score > 0.5
    end
  end
  
  def format_research_output(content, sources)
    output = "# Research Report\n\n"
    output += content
    output += "\n\n## References\n\n"
    
    sources.each_with_index do |source, i|
      output += format_citation(source, i + 1)
    end
    
    output
  end
end
```

### Code Review Agent

```ruby
class CodeReviewAgent < RCrewAI::Agent
  REVIEW_CATEGORIES = [
    :syntax,
    :style,
    :security,
    :performance,
    :maintainability,
    :testing
  ]
  
  def initialize(**options)
    super(options.merge(
      role: "Senior Code Reviewer",
      goal: "Ensure code quality and best practices"
    ))
    
    @review_strictness = options[:strictness] || :medium
    @languages = options[:languages] || [:ruby, :python, :javascript]
  end
  
  def review_code(code, language = :ruby)
    review_results = {}
    
    REVIEW_CATEGORIES.each do |category|
      review_results[category] = review_category(code, category, language)
    end
    
    generate_review_report(review_results, code)
  end
  
  private
  
  def review_category(code, category, language)
    case category
    when :syntax
      check_syntax(code, language)
    when :style
      check_style_compliance(code, language)
    when :security
      security_scan(code)
    when :performance
      analyze_performance(code)
    when :maintainability
      assess_maintainability(code)
    when :testing
      check_test_coverage(code)
    end
  end
  
  def generate_review_report(results, code)
    report = "## Code Review Report\n\n"
    
    # Overall score
    overall_score = calculate_overall_score(results)
    report += "**Overall Score: #{overall_score}/10**\n\n"
    
    # Category breakdown
    results.each do |category, findings|
      report += "### #{category.to_s.capitalize}\n"
      report += format_findings(findings)
      report += "\n"
    end
    
    # Recommendations
    report += "### Recommendations\n"
    report += generate_recommendations(results)
    
    report
  end
end
```

## Agent Communication Patterns

Enable sophisticated communication between agents.

### Message Passing Between Agents

```ruby
class CommunicatingAgent < RCrewAI::Agent
  attr_accessor :message_queue
  
  def initialize(**options)
    super
    @message_queue = []
    @subscribers = []
  end
  
  def send_message(recipient, message)
    if recipient.respond_to?(:receive_message)
      recipient.receive_message(self, message)
      @logger.info "Sent message to #{recipient.name}: #{message[:type]}"
    end
  end
  
  def receive_message(sender, message)
    @message_queue << {
      from: sender.name,
      message: message,
      timestamp: Time.now
    }
    
    # Process immediately if high priority
    if message[:priority] == :high
      process_message(message)
    end
  end
  
  def broadcast(message)
    @subscribers.each do |subscriber|
      send_message(subscriber, message)
    end
  end
  
  def subscribe(agent)
    @subscribers << agent unless @subscribers.include?(agent)
  end
  
  private
  
  def process_message(message)
    case message[:type]
    when :request_help
      provide_assistance(message)
    when :share_findings
      incorporate_findings(message)
    when :coordinate
      coordinate_action(message)
    end
  end
end

# Create communicating agents
lead_analyst = CommunicatingAgent.new(
  name: "lead_analyst",
  role: "Lead Data Analyst"
)

junior_analyst = CommunicatingAgent.new(
  name: "junior_analyst",
  role: "Junior Analyst"
)

# Set up communication
junior_analyst.subscribe(lead_analyst)

# Agents can now communicate during execution
junior_analyst.send_message(lead_analyst, {
  type: :request_help,
  priority: :high,
  content: "Need help with statistical analysis"
})
```

### Collaborative Decision Making

```ruby
class CollaborativeAgent < RCrewAI::Agent
  def make_collaborative_decision(decision_context, collaborators)
    # Gather input from all collaborators
    inputs = collaborators.map do |agent|
      {
        agent: agent.name,
        opinion: get_agent_opinion(agent, decision_context),
        confidence: get_confidence_level(agent, decision_context)
      }
    end
    
    # Synthesize decision
    synthesize_collaborative_decision(inputs, decision_context)
  end
  
  private
  
  def get_agent_opinion(agent, context)
    # Request opinion from agent
    prompt = "Given context: #{context}, what is your recommendation?"
    
    # Simulate agent providing opinion based on expertise
    if agent.respond_to?(:provide_opinion)
      agent.provide_opinion(context)
    else
      "No opinion"
    end
  end
  
  def synthesize_collaborative_decision(inputs, context)
    # Weight opinions by confidence
    weighted_opinions = inputs.map do |input|
      {
        opinion: input[:opinion],
        weight: input[:confidence]
      }
    end
    
    # Find consensus or synthesize
    if unanimous?(weighted_opinions)
      weighted_opinions.first[:opinion]
    else
      create_consensus(weighted_opinions, context)
    end
  end
end
```

## Error Handling and Recovery

Advanced error handling strategies for robust agent operation.

### Graceful Degradation

```ruby
class ResilientAgent < RCrewAI::Agent
  def execute_task(task)
    attempt_with_fallbacks(task)
  end
  
  private
  
  def attempt_with_fallbacks(task)
    strategies = [
      -> { execute_with_all_tools(task) },
      -> { execute_with_essential_tools(task) },
      -> { execute_with_no_tools(task) },
      -> { provide_best_effort_response(task) }
    ]
    
    strategies.each_with_index do |strategy, i|
      begin
        @logger.info "Attempting strategy #{i + 1}"
        return strategy.call
      rescue => e
        @logger.warn "Strategy #{i + 1} failed: #{e.message}"
        next
      end
    end
    
    "Unable to complete task after all strategies"
  end
  
  def execute_with_essential_tools(task)
    # Disable non-essential tools
    essential_tools = tools.select { |t| t.essential? }
    with_tools(essential_tools) do
      super(task)
    end
  end
  
  def execute_with_no_tools(task)
    # Pure reasoning without tools
    with_tools([]) do
      super(task)
    end
  end
end
```

### Self-Healing Agents

```ruby
class SelfHealingAgent < RCrewAI::Agent
  def initialize(**options)
    super
    @health_monitor = HealthMonitor.new(self)
    @recovery_strategies = {}
  end
  
  def execute_task(task)
    @health_monitor.check_health
    
    begin
      result = super
      @health_monitor.record_success
      result
    rescue => e
      @health_monitor.record_failure(e)
      
      if @health_monitor.needs_healing?
        perform_self_healing
        retry
      else
        raise
      end
    end
  end
  
  private
  
  def perform_self_healing
    @logger.info "Performing self-healing procedures"
    
    # Clear corrupted memory
    if @health_monitor.memory_corrupted?
      @memory.clear_corrupted_entries
    end
    
    # Reset tool connections
    if @health_monitor.tools_failing?
      reset_tool_connections
    end
    
    # Adjust parameters
    if @health_monitor.performance_degraded?
      optimize_parameters
    end
    
    @health_monitor.reset
  end
  
  def optimize_parameters
    # Dynamically adjust agent parameters
    self.max_iterations = [max_iterations - 2, 3].max
    self.max_execution_time = max_execution_time * 1.5
    
    @logger.info "Adjusted parameters for better performance"
  end
end
```

## Best Practices

### 1. **Agent Design Principles**
- Single Responsibility: Each agent should have one clear role
- Clear Goals: Define specific, measurable goals
- Rich Backstories: Provide context that guides behavior
- Appropriate Tools: Equip agents with necessary tools only

### 2. **Performance Guidelines**
- Set reasonable iteration limits (5-10 for most tasks)
- Use timeouts to prevent hanging (60-300 seconds typical)
- Cache expensive operations when possible
- Use async execution for independent tasks

### 3. **Memory Management**
- Implement memory cleanup for long-running agents
- Persist valuable memory across sessions
- Limit memory size to prevent bloat
- Use memory statistics for optimization

### 4. **Delegation Best Practices**
- Managers should have broad understanding, not deep expertise
- Delegate based on agent strengths and availability
- Provide clear context in delegations
- Monitor delegation success rates

### 5. **Error Handling**
- Implement graceful degradation strategies
- Log errors with context for debugging
- Use retry logic with exponential backoff
- Provide fallback responses

## Next Steps

Now that you understand advanced agent configuration:

1. Try the [Custom Tools Development]({{ site.baseurl }}/tutorials/custom-tools) tutorial
2. Learn about [Working with Multiple Crews]({{ site.baseurl }}/tutorials/multiple-crews)
3. Explore [Production Deployment]({{ site.baseurl }}/tutorials/deployment) strategies
4. Review [API Documentation]({{ site.baseurl }}/api/) for detailed reference

Advanced agents are the key to building sophisticated AI systems that can handle complex, real-world tasks with reliability and efficiency.