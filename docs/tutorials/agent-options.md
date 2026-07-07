---
layout: tutorial
title: Advanced Agent & Task Options
description: Per-agent LLM, reasoning, rate limiting, context window, multimodal, structured output, guardrails, and lifecycle hooks
---

# Advanced Agent & Task Options

A tour of the production controls added across 0.4–0.7. All are opt-in; agents
and tasks behave as before when you don't set them.

## Per-agent LLM

Give each agent its own provider/model instead of only the global default:

```ruby
worker  = RCrewAI::Agent.new(name: 'worker', role: '...', goal: '...',
                             llm: { provider: :openai, model: 'gpt-4o-mini' })
manager = RCrewAI::Agent.new(name: 'manager', role: '...', goal: '...',
                             llm: { provider: :anthropic, model: 'claude-3-opus-20240229' })
```

Accepts a provider symbol, an options hash, or a pre-built client. Overrides
never mutate the global configuration.

## Reasoning

Have an agent draft a plan before answering. The trace is exposed on the result
and doesn't pollute `task.result`:

```ruby
agent = RCrewAI::Agent.new(name: '...', role: '...', goal: '...',
                           reasoning: true, max_reasoning_attempts: 3)
result = agent.execute_task(task)
result[:reasoning]   # the plan
result[:content]     # the answer
```

## Rate limiting

Cap an agent's LLM calls to stay under provider limits (thread-safe, holds under
async execution):

```ruby
agent = RCrewAI::Agent.new(name: '...', role: '...', goal: '...', max_rpm: 20)
```

## Context-window management

Trim history to fit the model's context window (oldest non-system messages drop
first; system + latest always kept):

```ruby
agent = RCrewAI::Agent.new(name: '...', role: '...', goal: '...',
                           respect_context_window: true)
```

## Multimodal input

Pass images to a vision-capable model via task attachments (local files are
base64-encoded; URLs pass through). Supported on OpenAI/Azure.

```ruby
task = RCrewAI::Task.new(
  name: 'describe', description: 'What is in this chart?', agent: agent,
  attachments: [
    { type: :image, path: 'chart.png' },
    { type: :image, url: 'https://example.com/photo.jpg' }
  ]
)
```

## Structured output & guardrails

Validate, transform, and persist a task's result:

```ruby
task = RCrewAI::Task.new(
  name: 'extract', description: '...', agent: agent,

  output_schema: { type: 'object', properties: { title: { type: 'string' } },
                   required: ['title'] },       # -> task.structured_output

  guardrail: ->(out) { [out.length < 5000, 'too long'] },  # [ok, value_or_error]

  output_file: 'out/report.md', markdown: true
)
task.execute
task.structured_output   # validated object
task.raw_result          # unprocessed string
```

Schema/guardrail failures re-run the agent with the error fed back.

## Planning

Run a planner pass that drafts a per-task plan before execution:

```ruby
crew = RCrewAI::Crew.new('research', planning: true)   # optional planning_llm:
```

## Lifecycle hooks & batch runs

```ruby
crew.before_kickoff { |inputs| inputs.merge(started_at: Time.now) }
crew.after_kickoff  { |result| notify(result); result }

crew.execute(inputs: { topic: 'ruby' })
crew.last_inputs   # the resolved inputs

# Run the crew once per input set:
results = crew.kickoff_for_each(inputs: [{ topic: 'ruby' }, { topic: 'python' }])
```

## Training & testing

```ruby
crew.train(n_iterations: 3, filename: 'training.json')  # collect feedback
crew.test(n_iterations: 5)                              # score repeated runs
```

## See also

- [Flows]({{ site.baseurl }}/tutorials/flows)
- [Knowledge (RAG)]({{ site.baseurl }}/tutorials/knowledge)
- [Cognitive Memory]({{ site.baseurl }}/tutorials/memory)
- [Consensual Process]({{ site.baseurl }}/tutorials/consensual-process)
