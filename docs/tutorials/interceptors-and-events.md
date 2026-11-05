---
layout: tutorial
title: Interceptors and Events
description: Inspect or change LLM requests and responses, and rebuild a run's event stream into a trace
---

# Interceptors and Events

Interceptors let you see or change each LLM call. Events report what a crew is doing
while it runs.

## LLM interceptors

Build a client with hooks, then give it to an agent:

```ruby
redact = lambda do |payload, _context|
  payload.merge(user: 'anonymous')
end

client = RCrewAI::LLMClient.for_provider(:openai, RCrewAI.configuration,
                                         before_request: redact)

client.after_response do |result, context|
  puts "#{context[:provider]}/#{context[:model]} took #{context[:duration_ms]}ms"
  nil # keep the original result
end

agent = RCrewAI::Agent.new(name: 'analyst', role: 'Analyst', goal: 'Analyze', llm: client)
```

- `before_request` receives `(payload, context)`. `after_response` receives
  `(result, context)`, and its context also has `:duration_ms`.
- Return a new value to replace the original, or `nil` to keep it.
- Hooks run in the order they were registered.
- A hook that raises is reported to stderr and skipped, so it can't break the call.
  That also means a hook can't be used to block a request by raising.

## Events

Pass a block or callable to `crew.execute` to receive events. `stream:` also takes an
array of subscribers:

```ruby
crew.execute do |event|
  case event
  when RCrewAI::Events::TextDelta     then print event.text
  when RCrewAI::Events::ToolCallStart then puts "Calling #{event.tool}"
  when RCrewAI::Events::Usage         then puts "Cost: #{event.cost_usd}"
  end
end
```

| Event | Fields, besides the common ones |
|---|---|
| `IterationStart` / `IterationEnd` | `iteration_index` / `finish_reason` |
| `TextDelta` / `TextDone` | `text` |
| `Thinking` | `text` |
| `ToolCallStart` | `tool`, `args`, `call_id` |
| `ToolCallResult` | `tool`, `call_id`, `result`, `duration_ms` |
| `ToolCallError` | `tool`, `call_id`, `error` |
| `Usage` | `prompt_tokens`, `completion_tokens`, `total_tokens`, `cost_usd`, `cached_tokens` |
| `Error` | `error` |

Token and text events come from agents using native function calling. An agent that
falls back to the legacy runner, such as Ollama with a model without native tools,
emits fewer of them.

Delivery is serialized, so a subscriber is never entered from two threads at once and
doesn't need its own mutex.

## Building a trace

Every event has an `id`, and a `parent_id` naming the span that encloses it, so you can
rebuild the flat stream into a tree. To group your own work under a span:

```ruby
RCrewAI::Events.with_parent(span_id) do
  RCrewAI::Events.emit(sink, RCrewAI::Events::Event.new(type: :checkpoint))
end
```

Spans are per-thread. Tool events from RCrewAI's own worker threads carry the run's
span across, but a thread you start yourself begins with no parent.
