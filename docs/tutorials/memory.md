---
layout: tutorial
title: Cognitive Memory
description: Semantic, persistent, multi-type agent memory
---

# Cognitive Memory

Agents remember what they've done and recall it on future tasks. Memory is
**zero-config by default** (in-memory, word-overlap recall) and becomes far more
capable when you add an embedder (semantic recall) and a store (persistence).

## Zero-config

Every agent gets a `Memory` scoped to itself. Nothing to set up:

```ruby
agent = RCrewAI::Agent.new(name: 'engineer', role: '...', goal: '...')
# agent.memory records executions and recalls relevant ones automatically
```

## Semantic recall

Pass an embedder and recall becomes semantic — the agent finds conceptually
related past work even when the wording differs:

```ruby
embedder = RCrewAI::Knowledge::Embedder.new           # or provider: :ollama
agent = RCrewAI::Agent.new(name: 'engineer', role: '...', goal: '...',
                           memory: { embedder: embedder })
```

Recall falls back to word-overlap similarity without an embedder, and embedding
failures fall back gracefully — **memory never breaks agent execution.**

## Persistence

Give memory a SQLite store and it survives restarts:

```ruby
store = RCrewAI::Memory::SqliteStore.new(path: '~/.rcrewai/memory.db')
agent = RCrewAI::Agent.new(name: 'engineer', role: '...', goal: '...',
                           memory: { embedder: embedder, store: store })
```

The default store is `InMemoryStore` (volatile). `SqliteStore` accepts
`max_candidates:` (default 1000) to bound how many recent rows a search scans,
keeping recall fast as memory grows.

## Memory types

The `Memory` facade exposes four underlying types:

```ruby
agent.memory.short_term   # recent executions (capped, semantic recall)
agent.memory.long_term    # durable, deduped insights from successful runs
agent.memory.entity       # facts about entities (people, systems) seen in work
agent.memory.tool         # tool-call history + outcomes

agent.memory.entity.entities              # => ["Alice", "AWS", ...]
agent.memory.long_term.recall('...', limit: 3)
```

### Better entity extraction

By default entities are extracted heuristically (capitalized tokens). For
multi-word names, plug in an LLM extractor:

```ruby
extractor = RCrewAI::Memory::LlmEntityExtractor.new(agent.llm_client)
agent = RCrewAI::Agent.new(name: '...', role: '...', goal: '...',
                           memory: { entity_extractor: extractor })
```

## Scoping

Memory is scoped per agent, so agents sharing a persistent store don't read each
other's memories. Override with `memory: { scope: 'shared' }` for deliberate
sharing.

## The classic API still works

`add_execution`, `add_tool_usage`, `relevant_executions`, `tool_usage_for`,
`clear_short_term!`, `clear_all!`, and `stats` behave as before — the cognitive
system is a drop-in upgrade.

## Runnable example

See [`examples/cognitive_memory_example.rb`](https://github.com/gkosmo/rcrewAI/blob/main/examples/cognitive_memory_example.rb)
— semantic recall + SQLite persistence, no API key required.
