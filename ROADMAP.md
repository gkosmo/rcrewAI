# RCrewAI Roadmap

This roadmap tracks feature parity between **RCrewAI** (Ruby) and the upstream
[**crewai**](https://pypi.org/project/crewai/) Python framework.

## Current status

- **RCrewAI:** `0.3.0` (2026-05-12)
- **Upstream crewai:** `1.15.x` (mid-2026)

RCrewAI is a faithful port of CrewAI's **"Crews"** mental model (Agents / Tasks /
Crew, sequential + hierarchical processes, tools, memory, human-in-the-loop). As
of `0.3.0` the LLM plumbing is modern: native function calling across all five
providers, a tool-schema DSL, typed streaming events, MCP client, and per-model
pricing.

Since CrewAI's `1.0`, the framework has grown a second pillar (**Flows**) plus
**Knowledge (RAG)**, **Guardrails**, **structured output**, **Planning**, and
**Training/Testing**. RCrewAI implements roughly **60–70% of the classic Crews
surface** and **~0% of the newer layer**. This roadmap closes that gap.

## Parity matrix

| Concept | crewai | RCrewAI 0.3.0 | Target |
|---|---|---|---|
| Agents / Tasks / Crew | ✅ | ✅ | — |
| Sequential / hierarchical process | ✅ | ✅ | — |
| Native function calling + tool DSL | ✅ | ✅ (0.3.0) | — |
| Streaming events | ✅ | ✅ (0.3.0) | — |
| MCP client | ✅ | ✅ (0.3.0) | — |
| Per-model pricing / cost | ✅ | ✅ (0.3.0) | — |
| Per-agent LLM override | ✅ | ❌ (global only) | **0.3.1** |
| Structured output (schema) | ✅ | ❌ | **0.4.0** |
| Task guardrails | ✅ | ❌ | **0.4.0** |
| `output_file` / markdown | ✅ | ❌ | **0.4.0** |
| Knowledge / RAG | ✅ | ❌ | **0.5.0** |
| Planning | ✅ | ❌ | **0.5.0** |
| Flows (`start`/`listen`/`router`) | ✅ | ❌ | **0.6.0** |
| Flow state + persistence | ✅ | ❌ | **0.6.0** |
| Training / Testing | ✅ | ❌ | **0.7.0** |
| Reasoning, rate-limiting, batch kickoff | ✅ | ❌ | backlog |

## Milestones (highest leverage first)

### 0.3.1 — Per-agent LLM override
Let `Agent.new(llm:)` accept a provider/model, instead of only the global
`RCrewAI.configure`. Unblocks mixed-model crews (cheap model for workers, strong
model for the manager).

### 0.4.0 — Structured output & guardrails
Builds directly on the 0.3.0 tool-schema/JSON-schema plumbing.
- `Task.new(output_schema:)` → validated, coerced structured result.
- `Task.new(guardrail:)` → proc/object that validates & transforms output, with
  bounded retries (`guardrail_max_retries`).
- `output_file:` + `markdown:` output formatting.

### 0.5.0 — Knowledge (RAG) & Planning
- Knowledge sources: string, `.txt`, PDF (have `pdf-reader`), CSV, JSON, URL
  (have `nokogiri`). Embeddings client + a pluggable vector store (start with an
  in-memory / SQLite cosine store; no hard Chroma dependency).
- Attach at agent **and** crew level.
- `Crew.new(planning: true)` → a planner pass that drafts a step plan before
  execution.

### 0.6.0 — Flows
The flagship. A Ruby DSL mirroring CrewAI Flows:
- `start`, `listen`, `router` decorators/class-methods.
- `and_` / `or_` trigger combinators.
- Structured flow **state** (a plain struct/`Data` or dry-struct) with a UUID.
- `@persist`-equivalent state persistence across restarts.
- `human_feedback` pause/resume point.

### 0.7.0 — Training & Testing
- `crew.train(n_iterations:, filename:)` capturing human feedback.
- `crew.test(n_iterations:, model:)` scoring runs.

### Backlog
Per-agent reasoning (`reasoning:`, `max_reasoning_attempts:`), `max_rpm`
rate-limiting, `respect_context_window`, `kickoff_for_each` batch execution,
`before_kickoff` / `after_kickoff` hooks, multimodal agents.
