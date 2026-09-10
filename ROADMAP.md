# RCrewAI Roadmap

This roadmap tracks feature parity between **RCrewAI** (Ruby) and the upstream
[**crewai**](https://pypi.org/project/crewai/) Python framework.

## Current status

- **RCrewAI:** `0.7.1` released; `0.8.0`, `0.9.0` and `0.9.x` merged to `main`, unreleased
- **Upstream crewai:** `1.15.21`

RCrewAI is a faithful port of CrewAI's **"Crews"** mental model (Agents / Tasks /
Crew, sequential + hierarchical + consensual processes, tools, memory,
human-in-the-loop), and it carries CrewAI's second pillar (**Flows**) plus
**Knowledge (RAG)**, **guardrails**, **structured output**, **planning**, and
**training/testing**. In one area — cognitive memory (semantic recall, SQLite
persistence, four memory types) — the gem went past what was originally ported.

**Status: one milestone remaining.** An earlier revision of this file declared
parity "complete" against a matrix that only covered CrewAI through roughly
`1.0` (October 2025) while quoting `1.15.x` in its header; everything upstream
added across `1.1`–`1.15` was unmeasured. That delta was re-derived, and three
of the four scheduled milestones have since shipped. Only native async (1.0.0)
is outstanding, and it is blocked on an open decision — see below.

## Parity matrix

### Shipped

| Concept | crewai | RCrewAI |
|---|---|---|
| Agents / Tasks / Crew | ✅ | ✅ |
| Sequential / hierarchical process | ✅ | ✅ |
| Consensual process (propose → vote → pick) | ✅ | ✅ (0.7.0) |
| Native function calling + tool DSL | ✅ | ✅ (0.3.0) |
| Streaming events | ✅ | ✅ (0.3.0) |
| MCP client | ✅ | ✅ (0.3.0) |
| Per-model pricing / cost | ✅ | ✅ (0.3.0) |
| Per-agent LLM override | ✅ | ✅ (0.4.0) |
| Structured output (schema) | ✅ | ✅ (0.4.0) |
| Task guardrails | ✅ | ✅ (0.4.0) |
| `output_file` / markdown | ✅ | ✅ (0.4.0) |
| Knowledge / RAG | ✅ | ✅ (0.4.0) |
| Planning | ✅ | ✅ (0.4.0) |
| Flows (`start`/`listen`/`router`) | ✅ | ✅ (0.4.0) |
| Flow state + persistence | ✅ | ✅ (0.4.0) |
| Training / testing | ✅ | ✅ (0.4.0) |
| Lifecycle hooks, batch kickoff, rate limiting | ✅ | ✅ (0.5.0) |
| Reasoning, context window, multimodal | ✅ | ✅ (0.5.0) |
| Cognitive memory (semantic, persistent, typed) | ✅ | ✅ (0.6.x) |
| LLM message interceptor hooks | ✅ | ✅ (0.8.0) |
| Event hierarchy + safe fan-out | ✅ | ✅ (0.8.0) |
| Checkpointing (save / resume / lineage) | ✅ | ✅ (0.9.0) |
| Newer providers (Bedrock, Cortex, OpenAI-compatible) | ✅ | ✅ (0.9.x) |
| OpenAI Responses API | ✅ | ✅ (0.9.x) |

### Gaps

| Concept | crewai | RCrewAI | Plan |
|---|---|---|---|
| Native async (LLM + tool level) | ✅ (1.4–1.6) | ⚠️ partial | 1.0.0 |
| OTel export for the event hierarchy | ✅ (1.10+) | ❌ | 1.0.x |
| Streaming for Bedrock / Responses | ✅ | ❌ | 1.0.x |
| Bedrock SigV4 signing | ✅ | ❌ (hook workaround) | 1.0.x |
| A2A (agent-to-agent) | ✅ (1.7–1.9) | ❌ | deferred |

### Out of scope

Three upstream areas are deliberately **not** targets. They are CrewAI's
commercial platform surface rather than framework capability, and porting them
means tracking someone else's product roadmap with no Ruby-side consumer:

- **JSON-first project format** (`agents/*.jsonc`, `crew.jsonc`, declarative and
  conversational flows in the CLI TUI) — a config format whose shape is set by
  upstream's tooling.
- **Skills Repository** — a hosted registry plus authentication.
- **Policies** — CrewAI enforces these at the infrastructure level via the NVIDIA
  OpenShell runtime. Reimplementing them in-process would provide the appearance
  of enforcement without the property that makes enforcement worth having.

If a Ruby-side need for any of these appears, revisit — but not speculatively.

## Milestones

### 0.8.0 — Interceptors & observability ✅ shipped (#39)

`before_request` / `after_response` hooks on `LLMClients::Base`, inherited by
every provider and wired on both the plain and streaming paths. Events gained
`:id` / `:parent_id` with `Events.with_parent` spans opened per agent run.

`Events.fan_out` now serializes delivery under a reentrant mutex, fixing a live
race: it previously called sinks inline on the emitting thread, so under
`async: true` an aggregating subscriber was entered from several pool workers at
once. **Behavior change:** subscribers no longer need their own mutex.

### 0.9.0 — Checkpointing ✅ shipped (#42)

Task-level `crew.execute(checkpoint: store)` / `crew.resume(run_id)` across the
sequential, hierarchical and consensual processes, with `MemoryStore` and
`FileStore` following the `Flow::StateStore` shape. Resumed runs link to their
parent via `parent_run_id`; `Checkpoint.lineage` walks the chain to the root.
CLI: `rcrewai checkpoint list|info|delete`.

Also repaired `bin/rcrewai`, which had never worked: `lib/rcrewai/cli.rb`
defined `def run`, a Thor reserved word, so the class raised on load and the
file was never required — hiding the breakage from the suite while the shipped
gem executable crashed for every installed user.

### 0.9.x — Providers & Responses API ✅ shipped (#41)

`:openai_compatible`, `:bedrock` (Converse v4), `:snowflake` (Cortex) and
`:openai_responses`. Provider resolution moved to a `LLMClient::PROVIDERS`
table, which also fixed `for_provider` silently dropping interceptor hooks.

Two deliberate limitations carried forward to 1.0.x: Bedrock does not implement
SigV4 (a hard `aws-sigv4` dependency for one provider is not worth it; sign via
a `before_request` hook), and Bedrock/Responses are non-streaming only.

### 1.0.0 — Native async

The largest item, and the one with a genuine architecture decision attached.
Today `AsyncExecutor` fans tasks out across a `Concurrent::ThreadPoolExecutor` in
dependency-ordered phases; concurrency stops at the task boundary. CrewAI went
async *through* the LLM and tool calls (1.4–1.6), covering flows, crews, tasks,
knowledge, and memory.

Ruby has no direct port of that. Two candidate models:

1. **Fibers** via the `async` gem — closer to upstream's shape, new runtime
   dependency, and every provider client's HTTP layer has to cooperate.
2. **Stay on threads** and make the client layer non-blocking — smaller
   conceptual change, keeps `concurrent-ruby`, less faithful to upstream.

**This decision is open and blocks the milestone.** It touches all five LLM
clients either way. The 8.2k lines of `lib/` are backed by 4.9k lines of spec,
which is what makes a refactor at this depth tractable.

### Deferred — A2A

Agent-to-agent task execution utilities and server configuration (upstream
1.7–1.9). Real framework capability, but it presumes a deployment topology that
no current RCrewAI user has asked for. Revisit once the items above land.

## Sequencing

| Milestone | Contents | Risk | Status |
|---|---|---|---|
| 0.8.0 | Interceptors + observability | Low | ✅ merged (#39) |
| 0.9.0 | Checkpointing | Moderate | ✅ merged (#42) |
| 0.9.x | Providers, Responses API | Low | ✅ merged (#41) |
| 1.0.0 | Native async | High — decision open | ⏳ blocked |

The three shipped milestones are on `main` and unreleased; they want a version
bump and a release before or alongside 1.0.0 work.

**1.0.0 is blocked on the fibers-vs-threads decision above.** It is the only
remaining scheduled work, and the largest single change in this roadmap: it
touches all nine provider clients and the executor. Nothing else should start
before that call is made.
