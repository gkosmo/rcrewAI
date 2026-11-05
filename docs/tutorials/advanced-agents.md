---
layout: tutorial
title: Advanced Agent Configuration
description: Configure per-agent models, memory, reasoning, rate limits, concurrency, delegation, and custom agent subclasses
---

# Advanced Agent Configuration

Every option here is a keyword argument to `RCrewAI::Agent.new`. All of them are
optional, and an agent behaves sensibly without them.

## Table of Contents
1. [A Model per Agent](#a-model-per-agent)
2. [Memory](#memory)
3. [Reasoning](#reasoning)
4. [Limits: Iterations, Rate, and Context](#limits-iterations-rate-and-context)
5. [Concurrent Tool Calls](#concurrent-tool-calls)
6. [Human Approval](#human-approval)
7. [Managers and Delegation](#managers-and-delegation)
8. [Subclassing Agent](#subclassing-agent)
9. [Handling Failure](#handling-failure)
10. [Best Practices](#best-practices)

## A Model per Agent

By default an agent uses the global configuration. Pass `llm:` to give one agent
its own provider or model, for example a stronger model for planning and a
cheaper one for bulk work:

```ruby
require 'rcrewai'

RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.model = 'gpt-4o'
end

# Current Claude models reject `temperature`, so this agent's client is built
# from a configuration that doesn't send it. See "Building a client" below.
reviewer_config = RCrewAI.configuration.with_overrides(provider: :anthropic, model: 'claude-opus-5-5')
reviewer_config.temperature = nil

reviewer = RCrewAI::Agent.new(
  name: 'reviewer',
  role: 'Principal Engineer',
  goal: 'Find defects before they ship',
  llm: RCrewAI::LLMClient.for_provider(:anthropic, reviewer_config)
)

# Provider and model only, using that provider's configured key.
summarizer = RCrewAI::Agent.new(
  name: 'summarizer',
  role: 'Technical Writer',
  goal: 'Summarize findings',
  llm: { provider: :openai, model: 'gpt-4o-mini' }
)
```

`llm:` accepts a provider symbol, a hash (`provider:`, `model:`, `api_key:`,
`temperature:`), or any object that responds to `chat`. Overrides never change
the global configuration. An agent that switches provider doesn't inherit a
global `config.model`: it uses its own provider's model.

**Building a client.** A `temperature:` override can set a value but not remove
one, which is why the Claude example above builds its client from a modified
configuration. If Anthropic is your global provider, setting
`config.temperature = nil` in `RCrewAI.configure` is enough.

## Memory

Every agent has a memory, with nothing to configure. It records each task, and
later tasks recall relevant earlier work:

```ruby
analyst = RCrewAI::Agent.new(name: 'analyst', role: 'Analyst', goal: 'Find trends')

analyst.memory.stats
# => { short_term_count: 0, long_term_total: 0, entity_count: 0, tool_usage_count: 0 }
```

By default memory lives in the process and is gone when it exits. Add an embedder
for semantic recall, and a store to survive restarts:

```ruby
persistent = RCrewAI::Agent.new(
  name: 'researcher',
  role: 'Researcher',
  goal: 'Build on earlier findings',
  memory: {
    store: RCrewAI::Memory::SqliteStore.new(path: 'researcher_memory.db'),
    # embedder: RCrewAI::Knowledge::Embedder.new,  # semantic recall; calls an embeddings API
    short_term_limit: 200
  }
)
```

Memory is scoped to the agent's name, so agents can share a store without reading
each other's records. Pass `scope: 'shared'` when they should. See the
[Cognitive Memory tutorial]({{ site.baseurl }}/tutorials/memory) for memory types
and entity extraction.

## Reasoning

With `reasoning: true`, the agent writes a short plan before it answers, at the
cost of one extra LLM call per task. The plan feeds the answer and is returned
alongside it rather than mixed into `task.result`:

```ruby
planner = RCrewAI::Agent.new(
  name: 'planner',
  role: 'Solutions Architect',
  goal: 'Design migration plans',
  reasoning: true,
  max_reasoning_attempts: 3  # retries only if the model returns an empty plan
)

task = RCrewAI::Task.new(name: 'plan', description: 'Plan a database migration', agent: planner)

result = planner.execute_task(task)
result[:reasoning]  # the plan
result[:content]    # the answer
```

If planning fails, or every attempt comes back empty, the agent carries on
without a plan.

## Limits: Iterations, Rate, and Context

```ruby
bounded = RCrewAI::Agent.new(
  name: 'bounded',
  role: 'Support Engineer',
  goal: 'Resolve tickets',
  max_iterations: 5,             # LLM turns per task (default 10)
  max_rpm: 30,                   # LLM calls per minute for this agent, thread-safe
  respect_context_window: true   # drop the oldest messages to fit the model's window
)
```

`respect_context_window` looks up the window for known models and always keeps the
system prompt and the latest message.

## Concurrent Tool Calls

When a model asks for several tools in one turn, they run at the same time, so the
turn costs the slowest call rather than the sum. Results stay in the order the
model asked for them, and up to 8 run at once.

Turn this off for an agent whose tools share state that isn't thread-safe, or that
call a rate-limited API:

```ruby
sequential = RCrewAI::Agent.new(
  name: 'db_writer',
  role: 'Database Operator',
  goal: 'Apply changes one at a time',
  parallel_tools: false
)
```

This applies when the model uses native function calling. The older text-based
runner, used for models without native tools, always runs one tool at a time.

## Human Approval

```ruby
supervised = RCrewAI::Agent.new(
  name: 'operator',
  role: 'Production Operator',
  goal: 'Make careful changes',
  human_input: true,
  require_approval_for_tools: true,
  require_approval_for_final_answer: true
)
```

These prompts read from the terminal, so they suit attended runs rather than
background jobs. The [human-in-the-loop example]({{ site.baseurl }}/examples/human-in-the-loop)
covers the task-level options too.

## Managers and Delegation

In a hierarchical crew, a manager coordinates the other agents:

```ruby
manager = RCrewAI::Agent.new(
  name: 'team_manager',
  role: 'Engineering Manager',
  goal: 'Coordinate the team to deliver projects',
  manager: true,
  allow_delegation: true
)

backend = RCrewAI::Agent.new(name: 'backend', role: 'Backend Engineer', goal: 'Build reliable APIs')
qa      = RCrewAI::Agent.new(name: 'qa', role: 'QA Engineer', goal: 'Verify software quality')

crew = RCrewAI::Crew.new('delivery', process: :hierarchical)
[manager, backend, qa].each { |agent| crew.add_agent(agent) }

# Assigned explicitly.
crew.add_task(RCrewAI::Task.new(name: 'api', description: 'Build the orders API', agent: backend))

# No agent: matched to the best subordinate by comparing the description with
# each agent's role and goal.
crew.add_task(RCrewAI::Task.new(name: 'verify', description: 'Verify software quality of the API'))

results = crew.execute
```

The manager is the first agent with `manager: true`, otherwise the first with
`allow_delegation: true`. If the crew has neither, RCrewAI adds a default
`crew_manager`. A hierarchical crew needs at least one other agent and one task,
or it raises `RCrewAI::Process::ProcessError`.

Matching by description is a simple keyword comparison, so assign `agent:` yourself
whenever the choice matters.

## Subclassing Agent

Most needs are covered by the options above, but you can subclass `Agent` to wrap
execution. Keep the full `execute_task` signature, because the crew passes `stream:`
to it. An override declared as `def execute_task(task)` fails with
`wrong number of arguments`.

```ruby
class TimedAgent < RCrewAI::Agent
  def execute_task(task, stream: nil, **opts)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    super
  ensure
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    warn "#{name} spent #{elapsed.round(2)}s on #{task.name}"
  end
end

timed = TimedAgent.new(name: 'timed', role: 'Analyst', goal: 'Analyze data')
```

For observing a run without subclassing, prefer streaming events
(`crew.execute(stream: ...)`) or LLM interceptors.

## Handling Failure

Failures are handled at the task and crew level:

```ruby
writer = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write summaries')

draft = RCrewAI::Task.new(
  name: 'draft',
  description: 'Write a summary',
  agent: writer,
  max_retries: 2,                 # re-run after an error (default 2)
  guardrail: lambda { |output|    # validate the output, retrying with feedback
    output.length < 2000 ? [true, output] : [false, 'Keep it under 2000 characters']
  }
)
```

A tool that raises doesn't fail the task under native function calling: the error
goes back to the model as the tool's result, so it can try something else. A failed
task doesn't stop a sequential crew either, so check the outcome:

```ruby
crew = RCrewAI::Crew.new('reporting')
crew.add_agent(writer)
crew.add_task(draft)

results = crew.execute
warn "#{results[:failed_tasks]} task(s) failed" if results[:failed_tasks].positive?
```

A failed task also fails any task that depends on it through `context:`. To resume a
long run without repeating finished work, pass a store to `crew.execute(checkpoint:)`
and call `crew.resume(run_id)`.

## Best Practices

- **Use specific roles and goals.** They drive the prompt and hierarchical task matching.
- **Give agents only the tools they need.** Fewer tools means fewer wrong choices.
- **Set `max_iterations` and `max_rpm` deliberately.** They bound both cost and rate-limit errors.
- **Reserve expensive models for the agents that need them.** Use `llm:` per agent.
- **Set `parallel_tools: false` for tools that aren't thread-safe.** Concurrency is on by default.

## Next Steps

- [Custom Tools Development]({{ site.baseurl }}/tutorials/custom-tools)
- [Advanced Agent & Task Options]({{ site.baseurl }}/tutorials/agent-options)
- [Working with Multiple Crews]({{ site.baseurl }}/tutorials/multiple-crews)
- [Production Deployment]({{ site.baseurl }}/tutorials/deployment)

## Next Steps

- [LLM Providers]({{ site.baseurl }}/tutorials/providers): set up each provider
- [Concurrency]({{ site.baseurl }}/tutorials/concurrency): control parallel tool calls
- [Interceptors and Events]({{ site.baseurl }}/tutorials/interceptors-and-events): see inside a run
- [Checkpointing]({{ site.baseurl }}/tutorials/checkpointing): resume failed runs
