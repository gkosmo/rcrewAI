# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Cognitive memory: `RCrewAI::Memory` is now a semantic, optionally-persistent, multi-type memory system, replacing the previous word-overlap placeholder. It composes four memory types — `ShortTermMemory` (recent executions, capped), `LongTermMemory` (durable, deduped insights), `EntityMemory` (facts about entities seen in work), and `ToolMemory` (tool-call history) — behind the original `Memory` public API.
- Semantic recall: pass `Agent.new(memory: { embedder: RCrewAI::Knowledge::Embedder.new })` to recall conceptually related past work via embeddings + cosine similarity. Without an embedder, recall falls back to lexical (word-overlap) similarity — and embedding failures fall back gracefully, so memory never breaks execution.
- Persistent memory: `RCrewAI::Memory::SqliteStore` persists memories to SQLite (vectors packed as floats, metadata as JSON) so recall survives restarts. Default store is `InMemoryStore` (volatile). The store interface is pluggable.
- Memory scoping: each agent's memory is scoped to its name by default, so agents sharing a persistent store don't cross-read; override via `memory: { scope: ... }`.
- `RCrewAI::Similarity` — shared cosine + lexical similarity helpers (extracted from `Knowledge::Store`, now used by both Knowledge and Memory).
- `sqlite3` added as a runtime dependency (required lazily; only needed for `SqliteStore`).

### Changed
- `Agent.new(memory:)` accepts a pre-built `Memory`, an options hash (`{ embedder:, store:, scope:, short_term_limit: }`), or nothing (zero-config default, unchanged behavior).

## [0.5.0] - 2026-07-03

Polish release completing the roadmap backlog: crew lifecycle hooks, batch
execution, rate limiting, per-agent reasoning, context-window management, and
multimodal image input. All additive — existing code runs unchanged.

### Added
- Crew lifecycle hooks: `Crew#before_kickoff` and `Crew#after_kickoff` register callbacks that run before/after execution. A `before_kickoff` hook receives the inputs hash (passed via `crew.execute(inputs:)`) and may transform it; an `after_kickoff` hook receives the result and may transform it. Multiple hooks run in registration order. The (possibly transformed) inputs are exposed on `Crew#last_inputs`. (#15)
- `Crew#kickoff_for_each(inputs:)` runs the crew once per input set and returns one result per input, in order. Runs are isolated — each execution starts from only its own inputs. (#16)
- Rate limiting: `Agent.new(max_rpm:)` throttles the agent's LLM calls to the given requests-per-minute using a thread-safe rolling-window `RCrewAI::RateLimiter`. The agent's client is transparently wrapped (`RateLimiter::ThrottledClient`) so every `chat` acquires a slot first; `max_rpm` nil/0 means unlimited. (#17)
- Reasoning: `Agent.new(reasoning: true)` runs a reasoning/planning pass before answering — the LLM drafts a short plan for the task, which is injected into the answer prompt and surfaced on the result hash as `:reasoning` (without polluting `task.result`). Bounded by `max_reasoning_attempts` (default 3), retrying if the model returns empty output; if every attempt is empty, execution proceeds without a plan. Off by default. (#18)
- Context-window management: `Agent.new(respect_context_window: true)` trims the message history to fit the model's context window before each LLM call, dropping the oldest non-system messages while always keeping system messages and the latest message. The new `RCrewAI::ContextWindow` module provides the token estimate (chars/4 heuristic), a per-model window-size table, and the `fit` trimmer. Off by default. (#19)
- Multimodal input: `Task.new(attachments:)` accepts image attachments (`{ type: :image, url: '...' }` or `{ type: :image, path: '...' }`). When a task has attachments, the agent builds an OpenAI-style multimodal user message (text + `image_url` parts); local files are base64-encoded into data URLs with a mime type inferred from the extension. Supported on OpenAI/Azure; other providers raise a clear `Multimodal::UnsupportedProviderError`. The new `RCrewAI::Multimodal` module builds the content parts. (#20)

## [0.4.0] - 2026-07-03

This release closes the feature-parity gap with the modern CrewAI framework,
adding its second pillar (**Flows**) alongside **Knowledge (RAG)**, structured
output, guardrails, planning, and training/testing. See `ROADMAP.md`.

### Added

#### Flows (#11)
- `RCrewAI::Flow` — an event-driven workflow engine (CrewAI's second pillar). Subclass it and declare methods with a class-level DSL: `start`, `listen`, `router`, and the `and_` / `or_` trigger combinators. `kickoff` runs the graph to a fixed point; routers emit labels that listeners trigger on.
- Flow state (`Flow::State`) is a schemaless object with an automatic UUID, seedable via `kickoff(inputs:)`.
- Flow persistence: pluggable state stores (`Flow::MemoryStateStore`, `Flow::FileStateStore`, or any `#save`/`#load` object); `flow.restore(id)` resumes a persisted run.
- Flows can invoke a `Crew` as a step and pause for input via `#human_feedback`.

#### Knowledge / RAG (#9)
- `RCrewAI::Knowledge` module adds retrieval-augmented context. Sources (`StringSource`, `FileSource`, `PdfSource`, `CsvSource`, `UrlSource`) are chunked, embedded, and stored in an in-memory cosine-similarity vector store (no external DB required).
- Attach via `Agent.new(knowledge:)` / `knowledge_sources:` (role-specific) or `Crew.new(knowledge:)` / `knowledge_sources:` (shared with all agents); relevant chunks are injected into each task's prompt at execution.
- The embedder (`Knowledge::Embedder`, default OpenAI `text-embedding-3-small`) and vector store are pluggable.

#### Task output processing (#6, #7, #8)
- Structured output: `Task.new(output_schema:)` validates and coerces the agent's output against a JSON-schema subset, exposing the parsed object via `Task#structured_output` (and the raw string via `Task#raw_result`). JSON embedded in surrounding prose or a fenced code block is extracted automatically; output that doesn't conform re-runs the agent with the error fed back.
- Guardrails: `Task.new(guardrail:)` takes a callable returning `[ok, value_or_error]` to validate and transform output before it flows downstream, retrying up to `guardrail_max_retries` (default 3) with the rejection reason fed back to the agent.
- Output persistence & formatting: `Task.new(output_file:)` writes the result to disk (`create_directory:` controls parent-dir creation, default true), and `markdown: true` prepends a heading when the output isn't already a markdown document.
- `RCrewAI::OutputSchema` — a small JSON-schema-subset validator/coercer used by structured task output.

#### Per-agent LLM (#5)
- `Agent.new(llm:)` accepts a provider symbol (`:anthropic`), an options hash (`{ provider:, model:, api_key:, temperature: }`), or a pre-built client instance. Agents in the same crew can use different providers/models (e.g. a cheap worker model and a stronger manager model). Omitting `llm:` keeps the previous global-configuration behavior.
- `Configuration#with_overrides` returns a copy of the configuration with per-agent overrides applied, leaving global state untouched.

#### Planning (#10)
- `Crew.new(planning: true)` runs a single planner pass before execution that asks an LLM to draft a short plan for each task and folds it into the task's description. Optional `planning_llm:` selects the planner client (defaults to the global provider). Best-effort — a planner error or unparseable output leaves tasks unchanged and execution proceeds.
- `Task#enrich_description` appends supplementary guidance (used by the planner) without discarding the original instructions.

#### Training & testing (#12)
- `Crew#train(n_iterations:, filename:)` runs the crew repeatedly, collects feedback after each iteration (via a `feedback:` callable, defaulting to a human prompt), and persists it as JSON.
- `Crew#test(n_iterations:)` runs the crew repeatedly and reports per-run and average scores (via a `scorer:` callable, defaulting to the run's success rate).

## [0.3.0] - 2026-05-12

### Added
- Native function calling across all five providers (OpenAI, Anthropic, Google, Azure, Ollama). Tools declare a JSON schema via the new DSL (`tool_name`, `description`, `param`) on `Tools::Base`.
- Typed streaming event model (`RCrewAI::Events::*`) covering text deltas, tool-call lifecycle, usage, and errors. Pass `stream:` to `crew.execute` or `agent.execute_task`.
- MCP (Model Context Protocol) client. Connect to stdio or HTTP MCP servers and expose their tools as ordinary RCrewAI tools (`RCrewAI::MCP::Client.with_connection`).
- Per-model price table (`RCrewAI::Pricing`) and `cost_usd` on `Events::Usage` for cost tracking.
- `Tools::Base#execute_with_validation` coerces and validates args against the DSL schema.
- New `ToolRunner` (native function calling loop) and `LegacyReactRunner` (extracted `USE_TOOL[]` parsing loop).
- `RCrewAI::SSEParser` — reusable Server-Sent Events parser used by all providers and MCP HTTP transport.

### Changed
- `Agent#execute_task` now delegates to `ToolRunner` (native function calling) or `LegacyReactRunner` (existing `USE_TOOL[]` parsing, used as fallback for legacy models or tools without a DSL declaration).
- `Agent#execute_task` return value is now a hash including `:content`, `:tool_calls_history`, `:usage`, `:iterations`, `:finish_reason`. `task.result` continues to hold the string content.
- `LLMClients::Base#chat` gains `tools:`, `tool_choice:`, and `stream:` keyword arguments.
- Provider clients return symbolic `finish_reason` (`:stop`, `:tool_calls`, `:length`) and symbol-keyed `usage`.

### Breaking
- Subclasses of `LLMClients::Base` that override `chat` with an explicit kwarg list must add `tools: nil, stream: nil` to the signature (or accept `**options`).
- Tools without DSL declarations now receive a permissive fallback schema and emit a one-time deprecation warning to stderr.

### Migration
- See `docs/upgrading-to-0.3.md` for step-by-step migration.

## [0.1.0] - 2025-01-12

### Added

#### Core Features
- **Intelligent Agent System**: AI agents with reasoning loops, memory, and tool usage capabilities
- **Multi-LLM Support**: Complete implementations for OpenAI, Anthropic, Google Gemini, Azure OpenAI, and Ollama
- **Advanced Task Orchestration**: Sequential, hierarchical, and async/concurrent execution modes
- **Human-in-the-Loop Integration**: Interactive approval workflows, real-time guidance, and collaborative decision making

#### Agent Capabilities
- Reasoning loops with configurable iterations and timeouts
- Short-term and long-term memory systems
- Tool usage with intelligent selection
- Manager agents with delegation capabilities
- Human interaction support (approval, guidance, reviews)

#### Task System
- Task dependencies and context sharing
- Retry logic with exponential backoff
- Async/concurrent execution with dependency management
- Human confirmation and review points
- Callback support and error handling

#### Tool Ecosystem
- **Web Search**: DuckDuckGo integration for research
- **File Operations**: Read/write files with security controls
- **SQL Database**: Secure database querying with connection management
- **Email Integration**: SMTP email sending with attachment support
- **Code Execution**: Sandboxed code execution environment
- **PDF Processing**: Text extraction and document processing
- **Custom Tool Framework**: Easy framework for building specialized tools

#### Orchestration Modes
- **Sequential Process**: Tasks execute one after another with dependency resolution
- **Hierarchical Process**: Manager agents coordinate and delegate to specialist agents
- **Async Execution**: Parallel task processing with intelligent dependency management
- **Human Oversight**: Interactive workflows with human collaboration points

#### LLM Provider Support
- **OpenAI**: GPT-4, GPT-3.5-turbo, and legacy completion models
- **Anthropic**: Claude-3 Opus/Sonnet/Haiku, Claude-2.1/2.0
- **Google**: Gemini Pro, Gemini Pro Vision, Gemini 1.5 models
- **Azure OpenAI**: Full compatibility with Azure OpenAI deployments
- **Ollama**: Local LLM support with model management

#### Human-in-the-Loop Features
- Task execution confirmation workflows
- Tool usage approval systems
- Real-time human guidance during agent reasoning
- Final answer review and revision capabilities
- Error recovery with human intervention options
- Session tracking and interaction history

#### Production Features
- Comprehensive error handling and recovery
- Security controls and input validation
- Detailed logging and debugging support
- Memory management and cleanup
- Configuration validation and environment variable support
- CLI interface for crew management

#### Development & Testing
- Comprehensive test suite with >90% coverage
- RSpec tests for all core components
- Mock LLM responses for reliable testing
- WebMock/VCR for HTTP interaction testing
- Continuous Integration setup
- Code quality checks with RuboCop

### Technical Details

#### Dependencies
- **thor**: CLI framework for command-line interface
- **zeitwerk**: Code loading and autoloading
- **faraday**: HTTP client for API interactions
- **concurrent-ruby**: Thread-safe concurrent execution
- **nokogiri**: HTML/XML parsing for web scraping
- **pdf-reader**: PDF text extraction capabilities
- **mail**: SMTP email functionality

#### Architecture
- Modular design with clear separation of concerns
- Plugin-based tool system for extensibility
- Event-driven human interaction system
- Thread-safe concurrent execution
- Memory-efficient resource management
- Flexible configuration system

### Documentation
- Complete API documentation with examples
- Human-in-the-loop integration guide
- LLM provider configuration examples
- Production deployment guidelines
- CLI usage documentation
- Real-world use cases and examples

[Unreleased]: https://github.com/gkosmo/rcrewAI/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/gkosmo/rcrewAI/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/gkosmo/rcrewAI/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/gkosmo/rcrewAI/compare/v0.1.0...v0.3.0
[0.1.0]: https://github.com/gkosmo/rcrewAI/releases/tag/v0.1.0