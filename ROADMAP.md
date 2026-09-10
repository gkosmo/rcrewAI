# RCrewAI Roadmap

This roadmap tracks feature parity between **RCrewAI** (Ruby) and the upstream
[**crewai**](https://pypi.org/project/crewai/) Python framework.

## Current status

- **RCrewAI:** `0.8.1` released; 1.0.0 concurrency work merged to `main`, unreleased
- **Upstream crewai:** `1.15.21`

RCrewAI is a faithful port of CrewAI's **"Crews"** mental model (Agents / Tasks /
Crew, sequential + hierarchical + consensual processes, tools, memory,
human-in-the-loop), and it carries CrewAI's second pillar (**Flows**) plus
**Knowledge (RAG)**, **guardrails**, **structured output**, **planning**, and
**training/testing**. In one area — cognitive memory (semantic recall, SQLite
persistence, four memory types) — the gem went past what was originally ported.

**Status: roadmap complete.** An earlier revision of this file declared
parity "complete" against a matrix that only covered CrewAI through roughly
`1.0` (October 2025) while quoting `1.15.x` in its header; everything upstream
added across `1.1`–`1.15` was unmeasured. That delta was re-derived, and all four
scheduled milestones have since shipped. What remains are two additive items
(Bedrock/Responses streaming, SigV4) and one deferred concept (A2A).

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
| Concurrent tool calls | ✅ (1.4–1.6) | ✅ (#47) | — |
| Concurrent embedding / consensus | ✅ (1.4–1.6) | ✅ (#49, #50) | — |
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

### 1.0.0 — Concurrency ✅ shipped

**Decision made: threads, not fibers.** The roadmap previously left this open.
Prototyping settled it, and not the way the fiber option's low apparent cost
suggested.

The attraction of fibers was that it looked cheap: keep Faraday, wrap calls in
`Async`, get non-blocking IO for free. That premise is false on this stack. On
Ruby 3.1.4 with `async` 2.24.0, a Faraday/`net_http` call inside a fiber
**never returns** — the task is silently abandoned and the process exits `0` as
though it succeeded. Raw `Net::HTTP` under `Async` raises `NoMethodError`
rather than yielding. A first benchmark appeared to show a 1.53s → 0.0s win;
it was measuring five failed requests that never reached the server.

Making fibers work would mean replacing Faraday with `async-http` across all
nine provider clients, adding a hard runtime dependency on a stack whose
observed failure mode is *silent abandonment* — the worst possible behavior in
an agent framework — and likely raising `required_ruby_version` from `3.0`,
since this fragility lives exactly in 3.0/3.1 scheduler support.

Threads cost none of that: `concurrent-ruby` is already a dependency, the Ruby
floor is unchanged, and failures are loud.

Upstream's async/await shape is a Python idiom; porting its *form* rather than
its *effect* would buy nothing here.

#### Shipped

Three fan-out points, all on threads, each bounded and each preserving input
order (every one of them feeds a positional zip or a deterministic tie-break
downstream):

- **Parallel tool calls** (#47) — a turn's tool calls run concurrently, so a
  turn costs the slowest call rather than their sum. Measured 0.45s → 0.165s
  for three 150ms tools. `Agent.new(parallel_tools: false)` opts out.
- **Concurrent embedding** (#49) — providers without a batch endpoint
  (`:google`, `:ollama`) issued one request per text in sequence, so building a
  knowledge base cost the sum of every chunk's round-trip. Bounded by
  `Knowledge::Embedder.new(max_concurrency:)`.
- **Concurrent consensus** (#50) — the `:consensual` process made twelve
  sequential LLM calls per task with three agents. Proposals and the whole
  (candidate × voter) scoring grid now fan out. Measured 1.22s → 0.22s.
  Bounded by `Crew.new(consensus_max_concurrency:)`.

Bounding was not optional: the first consensus implementation was unbounded and
put 36 concurrent LLM calls in flight with six agents — a thundering herd that
trips provider rate limits, which is a worse problem than the latency it
solves. Every fan-out here has a ceiling and a spec asserting it.

#### Remaining

An audit of `lib/` for per-item IO loops now turns up only CPU-bound work
(lexical similarity), so the task-boundary goal is met. What is left is not
concurrency work as such:

- Streaming for Bedrock and Responses (both non-streaming today).
- Bedrock SigV4 signing, currently a `before_request` hook workaround.

Neither blocks a 1.0.0 release; both are tracked in the gaps table.

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
| 1.0.0 | Concurrency (threads) | Moderate | ✅ merged (#47, #49, #50) |

The three shipped milestones are on `main` and unreleased; they want a version
bump and a release before or alongside 1.0.0 work.

**All scheduled milestones are merged.** The concurrency work landed on threads
across three fan-out points; see the milestone above for the prototype evidence
that ruled out fibers.

`main` carries the 1.0.0 concurrency work unreleased on top of `0.8.1`. The
remaining gaps — Bedrock/Responses streaming and SigV4 — are additive and do
not block cutting a release.
