# Upgrading to RCrewAI 0.7

RCrewAI 0.7 makes the `:consensual` crew process do what its name promises.

## Behavior change: `:consensual` process

Previously, `Crew.new('c', process: :consensual)` was a stub — it silently ran
tasks **sequentially**. As of 0.7 it performs real multi-agent consensus:

1. **Propose** — up to `consensus_agents` agents (default 3) each produce a
   candidate answer for the task.
2. **Vote** — every participant scores each candidate 0–10.
3. **Pick** — the highest-scored candidate wins (ties break toward the task's
   assigned agent).

### What you must do

Nothing to keep your code running — the API is unchanged. But be aware:

- If you were using `process: :consensual` and relying on its (accidental)
  sequential behavior, switch to `process: :sequential` explicitly.
- Consensus multiplies LLM calls (≈ N proposals + N×N scoring per task, N=3 by
  default). Tune or bound it with `consensus_agents:`.

```ruby
crew = RCrewAI::Crew.new('panel', process: :consensual, consensus_agents: 3)
```

### Edge cases

- One agent → a single proposal (no real vote), still a valid result.
- A proposer that errors is dropped; consensus continues with the rest.
- If every proposal fails, the task is marked failed.

The async consensual path (`crew.execute(async: true)` with `:consensual`) is
unchanged in this release (parallel aggregation).
