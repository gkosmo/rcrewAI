---
layout: tutorial
title: Concurrency
description: Control parallel tool calls, consensus rounds, embedding requests and async task execution
---

# Concurrency

RCrewAI runs independent, IO-bound work at the same time wherever it can. Each kind of
fan-out has a limit, so faster runs don't turn into rate-limit errors.

| What runs concurrently | Default limit | Change it with |
|---|---|---|
| Tool calls in one model turn | 8 | `Agent.new(parallel_tools: false)`; `ToolRunner.new(max_tool_concurrency:)` |
| Consensus proposals and scoring | 8 | `Crew.new(consensus_max_concurrency:)` |
| Embeddings on `:google` and `:ollama` | 8 | `Knowledge::Embedder.new(max_concurrency:)` |
| Tasks, with `crew.execute(async: true)` | CPU count | `crew.execute(async: true, max_concurrency:)` |

## Tool calls

When a model asks for several tools in one turn, they run together, so the turn takes
as long as the slowest call rather than the sum of them. Results stay in the order the
model asked for them.

Turn this off for an agent whose tools aren't safe to run in parallel, or that shouldn't
send a burst of requests to a rate-limited API:

```ruby
agent = RCrewAI::Agent.new(name: 'clerk', role: 'Clerk', goal: 'Update records',
                           tools: [ledger_tool], parallel_tools: false)
```

If your tools share state and you leave this on, they have to be thread-safe.

## Consensus

Scoring grows with the square of the number of participants: every voter scores every
candidate. Six agents would mean 36 scoring requests, which is why the limit exists.

```ruby
crew = RCrewAI::Crew.new('panel', process: :consensual,
                                  consensus_agents: 6,
                                  consensus_max_concurrency: 4)
```

Results keep their input order, so ties still go to the task's assigned agent.

## Embeddings

`:google` and `:ollama` have no batch endpoint, so each text is its own request:

```ruby
embedder = RCrewAI::Knowledge::Embedder.new(provider: :ollama, max_concurrency: 2)
```

`:openai` and `:azure` send one batched request and aren't affected. If any request
fails, the error is raised rather than leaving the knowledge base with missing vectors.
