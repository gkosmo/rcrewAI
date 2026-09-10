# RCrewAI Roadmap

This roadmap tracks feature parity between **RCrewAI** (Ruby) and the upstream
[**crewai**](https://pypi.org/project/crewai/) Python framework.

## Current status

- **RCrewAI:** `0.7.1` (2026-08-13)
- **Upstream crewai:** `1.15.21`

RCrewAI is a faithful port of CrewAI's **"Crews"** mental model (Agents / Tasks /
Crew, sequential + hierarchical + consensual processes, tools, memory,
human-in-the-loop), and it carries CrewAI's second pillar (**Flows**) plus
**Knowledge (RAG)**, **guardrails**, **structured output**, **planning**, and
**training/testing**. In one area — cognitive memory (semantic recall, SQLite
persistence, four memory types) — the gem went past what was originally ported.

**Status: behind upstream.** The previous revision of this file declared parity
"complete" against a matrix that only covered CrewAI through roughly `1.0`
(October 2025), while quoting `1.15.x` in its header. Everything CrewAI added
across `1.1`–`1.15` was unmeasured. This revision re-derives the delta and
schedules the parts of it worth closing.

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

### Gaps

| Concept | crewai | RCrewAI | Plan |
|---|---|---|---|
| LLM message interceptor hooks | ✅ (1.1–1.3) | ❌ | 0.8.0 |
| Event hierarchy + observability | ✅ (1.10+) | ❌ | 0.8.0 |
| Checkpointing (save / fork / lineage) | ✅ (1.10+) | ❌ | 0.9.0 |
| Newer providers (Cortex, Bedrock v4, OpenAI-compatible) | ✅ | ❌ | 0.9.x |
| OpenAI Responses API | ✅ (1.7–1.9) | ❌ | 0.9.x |
| Native async (LLM + tool level) | ✅ (1.4–1.6) | ⚠️ partial | 1.0.0 |
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

### 0.8.0 — Interceptors & observability

These ship together: the interceptor seam is what observability plugs into, and
the observability work fixes a defect that already exists.

**Interceptor hooks.** `before_request` / `after_response` hooks on
`LLMClients::Base#chat`, so callers can inspect, log, or rewrite requests and
responses without subclassing a provider. Small (the seam is a single method on
one base class, inherited by all five providers) and independently useful.

**Event hierarchy + thread-safe fan-out.** `Events.fan_out` currently invokes
sinks inline on the emitting thread with no serialization, so under `async: true`
a sink may be called concurrently from several worker threads — the 0.7.1
CHANGELOG documents this as a caveat, but for any subscriber that aggregates it
is a live race. Give events parent/child structure (matching CrewAI's 1.x event
system) and make fan-out safe, closing the gap and the defect in one change.
Optional OpenTelemetry export sits behind this as a **non-required** dependency.

### 0.9.0 — Checkpointing

Save / restore / fork of execution state with lineage tracking, plus CLI
commands to list and inspect checkpoints. Much of the machinery exists:
`Flow::StateStore` already defines the pluggable `#save(id, hash)` / `#load(id)`
interface with in-memory and file-backed implementations, and
`Memory::SqliteStore` establishes the persistence pattern. The work is extending
state capture from flow state to crew/task execution state.

### 0.9.x — Providers & Responses API

Mechanical, well-bounded, no design risk — follows the existing
`LLMClients::Base` pattern:

- Snowflake Cortex, Bedrock v4, and a generic OpenAI-compatible client.
- OpenAI Responses API shape alongside the current Chat Completions clients.

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

| Milestone | Contents | Risk |
|---|---|---|
| 0.8.0 | Interceptors + observability | Low — additive, fixes a live bug |
| 0.9.0 | Checkpointing | Moderate — new capability, existing patterns |
| 0.9.x | Providers, Responses API | Low — mechanical |
| 1.0.0 | Native async | High — architecture decision open |

0.8.0 first regardless of what follows: it is the smallest increment that ships
a real bug fix, and it de-risks everything after it.
