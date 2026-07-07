---
layout: tutorial
title: Consensual Process
description: Multi-agent consensus — agents propose competing answers and vote to pick one
---

# Consensual Process

For decisions where multiple perspectives matter, the `:consensual` process has
several agents propose competing answers and vote to pick the best one.

> **Since 0.7.0.** Earlier versions treated `:consensual` as a stub that ran
> tasks sequentially. It now performs real consensus — if you relied on the old
> behavior, use `process: :sequential`.

## How it works

For each task:

1. **Propose** — up to `consensus_agents` agents (default 3, capped from the
   crew) each produce a candidate answer.
2. **Vote** — every participant scores each candidate 0–10 against the task's
   description and expected output.
3. **Pick** — the highest total score wins. Ties break toward the task's
   assigned agent.

```ruby
crew = RCrewAI::Crew.new('panel', process: :consensual, consensus_agents: 3)
crew.add_agent(junior)
crew.add_agent(senior)
crew.add_task(task)

result = crew.execute   # each task goes through propose → vote → pick
```

## Cost

Consensus multiplies LLM calls: roughly `N` proposals + `N × N` scoring calls per
task, where `N` is `consensus_agents` (default 3). The cap keeps cost bounded even
on large crews — raise or lower it to trade thoroughness for cost.

## Edge cases

- **One agent** → a single proposal (no meaningful vote), still a valid result.
- **A proposer errors** → that candidate is dropped; consensus continues with the
  rest.
- **All proposals fail** → the task is marked failed.

## When to use it

Reach for `:consensual` when answer quality benefits from diversity and
cross-checking — design decisions, judgment calls, ambiguous tasks. For
straightforward pipelines, `:sequential` or `:hierarchical` is cheaper.

## Runnable example

See [`examples/consensual_process_example.rb`](https://github.com/gkosmo/rcrewAI/blob/main/examples/consensual_process_example.rb)
— runs without an API key.
