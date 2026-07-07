# Consensual Process: propose → vote → pick

**Date:** 2026-07-07
**Status:** Approved design (pending implementation)
**Target version:** `rcrewai` 0.7.0 (current is 0.6.1)
**Scope:** Replace the stubbed `Process::Consensual` (which silently runs tasks sequentially) with a real multi-agent consensus: agents propose candidate answers, score each other's candidates, and the highest-scored candidate wins.

---

## Motivation

`Crew.new('c', process: :consensual)` is a public, validated, documented process type. But `Process::Consensual#execute` currently just runs each task once (`execute_with_consensus` calls `task.execute` with a "for now, just execute normally" comment). A user selecting `:consensual` silently gets sequential behavior — the feature is advertised but not implemented. This is a latent honesty gap: fix the code to do what its name and comments promise ("agent voting/discussion").

## Behavior

For each task in the crew, instead of a single execution:

1. **Propose** — up to `consensus_agents` agents (default 3, capped from the crew) each independently produce a candidate answer for the task.
2. **Vote** — each participating agent scores every candidate 0–10 for how well it satisfies the task's description and expected output.
3. **Pick** — the candidate with the highest total score wins. Ties break toward the task's assigned agent's candidate (or the first proposer if the assigned agent didn't propose).

## Components

All within `Process::Consensual`, replacing the stub. Result shape is unchanged
(`{ task:, result:, status: }`) so `Crew#format_execution_results` needs no changes.

- `execute` — iterate tasks, call `execute_with_consensus(task)`, log, return results.
- `select_participants(task)` — first N agents (`consensus_agents`), always including the task's assigned agent if present and not already in the first N.
- `gather_proposals(task, participants)` — each agent runs the task; returns `[{ agent:, content: }]`. A proposer that raises is dropped (logged), not fatal.
- `score_candidates(task, candidates, participants)` — each participant scores each candidate via an LLM call; returns per-candidate total. Non-numeric / failed scores count as 0.
- `pick_winner(task, scored)` — highest total; deterministic tie-break toward the task's assigned agent, else first proposer.

## Configuration

```ruby
Crew.new('c', process: :consensual, consensus_agents: 3)
```

`consensus_agents` (default 3) caps how many agents propose and vote, bounding
cost regardless of crew size. Read by the process from the crew.

## Cost

Bounded per task: N proposals + N×N scoring calls, N defaulting to 3
(≈ 3 + 9 = 12 LLM calls/task worst case), independent of crew size.

## Edge cases

- **1 participant** → a single proposal, no meaningful vote; returns a valid result.
- **A proposer errors** → that candidate is dropped; consensus continues with the rest.
- **All proposals fail** → task marked `:failed` with the error, matching Sequential's rescue behavior.
- **No agents in crew** → task `:failed` (nothing can propose).

## Scoring mechanism

Each participant is prompted: given the task (description + expected output) and a
candidate answer, return a single integer 0–10. The response is parsed with a
tolerant integer extraction (first integer in the text; clamp to 0–10; default 0
on failure). Scores are summed across participants per candidate.

## Backward compatibility

`:consensual` already exists and validates. This changes only runtime behavior
(from "silently sequential" to "actual consensus"). The async consensual path
(`Crew#execute_consensual_async`, parallel aggregation) is intentionally left
unchanged for this pass and noted in docs; expanding it is a possible follow-up.

## Testing (TDD)

Fake agents returning canned proposals and scores (no live LLM) prove:
- highest-scored candidate wins
- deterministic tie-break toward the task's assigned agent
- `consensus_agents` cap respected on a larger crew
- single-agent degradation returns a valid result
- a proposer raising is dropped, consensus still completes
- all-proposals-fail marks the task `:failed`

## Rollout

Ship in `0.7.0` (behavior change to an existing feature warrants a minor bump).
`docs/upgrading-to-0.7.md` notes the behavior change; README documents the
consensus flow and `consensus_agents`.
