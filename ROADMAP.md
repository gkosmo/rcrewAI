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

Since CrewAI's `1.0`, the framework grew a second pillar (**Flows**) plus
**Knowledge (RAG)**, **Guardrails**, **structured output**, **Planning**, and
**Training/Testing**. RCrewAI now implements all of these — see the matrix below.

**Status: complete.** All milestone issues (#5–#12) shipped in v0.4.0, and all
backlog items (#15–#20) are done and merged to `main` (awaiting the next
release). There is no outstanding roadmap work.

## Parity matrix

| Concept | crewai | RCrewAI 0.3.0 | Target |
|---|---|---|---|
| Agents / Tasks / Crew | ✅ | ✅ | — |
| Sequential / hierarchical process | ✅ | ✅ | — |
| Native function calling + tool DSL | ✅ | ✅ (0.3.0) | — |
| Streaming events | ✅ | ✅ (0.3.0) | — |
| MCP client | ✅ | ✅ (0.3.0) | — |
| Per-model pricing / cost | ✅ | ✅ (0.3.0) | — |
| Per-agent LLM override | ✅ | ✅ (#5) | ✅ done |
| Structured output (schema) | ✅ | ✅ (#6) | ✅ done |
| Task guardrails | ✅ | ✅ (#7) | ✅ done |
| `output_file` / markdown | ✅ | ✅ (#8) | ✅ done |
| Knowledge / RAG | ✅ | ✅ (#9) | ✅ done |
| Planning | ✅ | ✅ (#10) | ✅ done |
| Flows (`start`/`listen`/`router`) | ✅ | ✅ (#11) | ✅ done |
| Flow state + persistence | ✅ | ✅ (#11) | ✅ done |
| Training / Testing | ✅ | ✅ (#12) | ✅ done |
| Reasoning, rate-limiting, batch kickoff, hooks, context window, multimodal | ✅ | ✅ (#15–#20) | ✅ done |

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

### Backlog — ✅ all complete

Formerly polish items with no set version; all shipped in the `[Unreleased]`
changes (see CHANGELOG):

- [#15](https://github.com/gkosmo/rcrewAI/issues/15) — `before_kickoff` / `after_kickoff` lifecycle hooks ✅
- [#16](https://github.com/gkosmo/rcrewAI/issues/16) — `kickoff_for_each` batch execution ✅
- [#17](https://github.com/gkosmo/rcrewAI/issues/17) — `max_rpm` rate limiting ✅
- [#18](https://github.com/gkosmo/rcrewAI/issues/18) — per-agent reasoning (`reasoning:`, `max_reasoning_attempts:`) ✅
- [#19](https://github.com/gkosmo/rcrewAI/issues/19) — `respect_context_window` history trimming ✅
- [#20](https://github.com/gkosmo/rcrewAI/issues/20) — multimodal agents (image/file inputs) ✅
