# LLM Modernization: Native Tool Calling, Streaming, and MCP Client

**Date:** 2026-05-11
**Status:** Approved design (pending implementation plan)
**Target version:** `rcrewai` 0.3.0 (current is 0.2.1)
**Scope:** Replace prompt-engineered ReAct tool calls with native function calling across all five LLM providers; add a typed streaming event model; add an MCP (Model Context Protocol) client so RCrewAI agents can consume external MCP servers as ordinary tools.

---

## Motivation

The current tool-call mechanism is ReAct-style: agents are prompted to emit `USE_TOOL[name](k=v)`, which a regex in `Agent#execute_task` then parses. This works but is fragile — argument escaping, multi-word string values, nested data, and "the model forgot to call the tool" are all recurring failure modes that providers' native function-calling APIs handle correctly.

Streaming is absent entirely, which blocks UI work, live cost tracking, and observability/tracing.

MCP has emerged as the de-facto standard protocol for exposing tools (filesystem, GitHub, Slack, browsers, internal services) to agent frameworks. Supporting it as a client unlocks a large existing tool ecosystem with zero per-tool code.

## Decisions captured during brainstorming

| # | Decision | Choice |
|---|---|---|
| 1 | Backward compatibility posture | **Dual-mode, native preferred.** Existing tools and the `USE_TOOL[]` path keep working; native tool calling is the default when both the provider and the tool support it. |
| 2 | Tool schema definition | **Explicit DSL** on `Tools::Base` (`tool_name`, `description`, `param`). Tools without DSL declarations get a permissive fallback schema. |
| 3 | MCP scope | **Client only** in v1 (stdio + HTTP/SSE transports). Server-mode deferred. |
| 4 | Streaming surface | **Full typed event stream** (text deltas, tool-call lifecycle, usage, errors). Text-only and listener-object idioms are thin wrappers. |
| 5 | Provider matrix | All five providers (OpenAI, Anthropic, Google, Azure, Ollama) gain native tools + streaming, with auto-fallback to ReAct for Ollama models that don't support tools. |

## Non-goals (v1)

- MCP **server** mode (exposing RCrewAI as a callable MCP service).
- MCP resources and prompts (only tools are wired).
- MCP OAuth flows for HTTP servers; header-based auth only.
- MCP sampling (server-initiated LLM calls).
- Live cost reconciliation against provider invoices (we provide a calculator + price table only).
- New providers beyond the existing five (Bedrock, Groq, OpenRouter, Mistral) — tracked as a follow-up.

---

## 1. Architecture overview

### New module layout (additive)

```
lib/rcrewai/
├── tool_schema.rb           # NEW – Schema DSL & JSON-schema emitter
├── events.rb                # NEW – Typed event classes for streaming
├── tool_runner.rb           # NEW – Native tool-call loop
├── legacy_react_runner.rb   # NEW – Extracted ReAct loop from agent.rb
├── pricing.rb               # NEW – Per-model price table for cost tracking
├── mcp/
│   ├── client.rb            # NEW – MCP protocol client (JSON-RPC 2.0)
│   ├── transport/stdio.rb   # NEW
│   ├── transport/http.rb    # NEW – Streamable HTTP (SSE)
│   └── tool_adapter.rb      # NEW – Wraps MCP tool as RCrewAI::Tools::Base
└── llm_clients/
    ├── base.rb              # MODIFIED – new chat() contract
    ├── openai.rb            # MODIFIED – tools + streaming
    ├── anthropic.rb         # MODIFIED – tools + streaming + prompt-caching hook
    ├── google.rb            # MODIFIED – tools + streaming
    ├── azure.rb             # MODIFIED – inherits OpenAI shape
    └── ollama.rb            # MODIFIED – native tools (allowlist) + streaming
```

### New `chat` contract on `LLMClients::Base`

```ruby
def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
  # If `stream` is a Proc (or array of Procs), yields RCrewAI::Events::*
  #   and still returns the final aggregated result.
  # If `tools:` is given, uses native function calling on the provider.
  # Returns:
  #   {
  #     content: String | nil,
  #     tool_calls: [{ id:, name:, arguments: Hash }],
  #     usage:        { prompt_tokens:, completion_tokens:, total_tokens: },
  #     finish_reason: Symbol,   # :stop | :tool_calls | :length | :max_iterations
  #     model:        String,
  #     provider:     Symbol
  #   }
end

def supports_native_tools?(model: config.model)
  # OpenAI / Anthropic / Google / Azure: always true
  # Ollama: allowlist check against known tool-capable models
end
```

### Provider matrix for v1

| Provider | Native tools | Streaming | Notes |
|---|---|---|---|
| OpenAI | ✅ | ✅ | Reference impl |
| Anthropic | ✅ | ✅ | Prompt-caching hook on `system` block |
| Google (Gemini) | ✅ | ✅ | `functionDeclarations` shape |
| Azure | ✅ | ✅ | Reuses OpenAI client logic |
| Ollama | ✅ (llama3.1+, qwen2.5, mistral-nemo, etc.) | ✅ | Auto-detects; falls back to ReAct on legacy models |

Capability detection: `LLMClient#supports_native_tools?(model:)` is checked once per agent run; the result is logged at INFO level as `[rcrewai] agent=<name> mode=native_tools|react_legacy provider=<provider>`. Suppressible via `config.log_level = :warn`.

---

## 2. Tool Schema DSL

A small class-level DSL on `Tools::Base` produces a canonical JSON schema. Per-provider adapters reshape the canonical schema for OpenAI / Anthropic / Google / Ollama (small differences in nesting and keys).

### DSL surface

```ruby
class WebSearch < RCrewAI::Tools::Base
  tool_name        "web_search"
  description      "Search the web via DuckDuckGo and return top results"

  param :query,       type: :string,  required: true,
                      description: "Natural-language search query"
  param :max_results, type: :integer, default: 10,
                      description: "Number of results to return (1-25)"

  def execute(query:, max_results: 10)
    # existing implementation
  end
end
```

### Supported types

`:string`, `:integer`, `:number`, `:boolean`, `:array` (with `items:`), `:object` (with `properties:`), `:enum` (with `values: [...]`).

### Generated canonical schema

```ruby
WebSearch.json_schema
# => {
#   name: "web_search",
#   description: "Search the web via DuckDuckGo and return top results",
#   parameters: {
#     type: "object",
#     properties: {
#       query:       { type: "string",  description: "Natural-language search query" },
#       max_results: { type: "integer", description: "Number of results to return (1-25)", default: 10 }
#     },
#     required: ["query"]
#   }
# }
```

### Validation

`Tools::Base#execute_with_validation(args_hash)` validates `args_hash` against the schema (types coerced where unambiguous, e.g. `"10"` → `10` for an `:integer` param) before delegating to `execute(**)`. Bad types raise `ToolError` with a clean message that flows back to the LLM as a tool-result, allowing the agent to recover on the next iteration.

### Fallback for undeclared tools

Tools without DSL declarations receive a permissive schema (`{ type: "object", additionalProperties: true }`) and a deprecation warning printed once per process. They still work in native-tools mode (the model gets less guidance) and still work in ReAct mode (unchanged).

### Built-in tool migration

All 7 built-in tools (`web_search`, `file_reader`, `file_writer`, `sql_database`, `email_sender`, `code_executor`, `pdf_processor`) get DSL declarations as part of this work. Each is ~5 added lines.

---

## 3. Native tool-call loop (`ToolRunner`)

The current ~300 lines of prompt-template + regex-parsing code in `Agent#execute_task` is split:

- The new **`ToolRunner`** drives a native function-calling conversation.
- The extracted **`LegacyReactRunner`** preserves the current `USE_TOOL[]` semantics for fallback.

`Agent#execute_task` becomes a thin orchestrator: build initial messages → choose runner → return runner result.

### `ToolRunner` interface

```ruby
class ToolRunner
  def initialize(agent:, llm:, tools:, max_iterations: 10, event_sink: nil); end

  def run(messages:)
    # Returns:
    #   {
    #     content: String,
    #     tool_calls_history: [{ tool:, args:, result:, duration_ms: }, ...],
    #     usage: { prompt_tokens:, completion_tokens:, total_tokens: },
    #     iterations: Integer,
    #     finish_reason: Symbol
    #   }
  end
end
```

### Loop algorithm (per iteration)

1. Call `llm.chat(messages:, tools: tools.map(&:json_schema), stream: event_sink)`.
2. Emit `Events::IterationStart` / `Events::TextDelta` / `Events::TextDone` / `Events::Usage` as deltas arrive.
3. If the response contains `tool_calls`:
   - For each call: emit `Events::ToolCallStart`, run `tool.execute_with_validation(args)`, emit `Events::ToolCallResult` (or `Events::ToolCallError`).
   - Honor `agent.require_approval_for_tools` (existing human-in-loop hook fires here).
   - Record into `agent.memory` via existing `memory.add_tool_usage`.
   - Append the assistant message (with `tool_calls`) and each tool-result message to `messages`.
   - Emit `Events::IterationEnd(finish_reason: :tool_calls)`; continue.
4. If no `tool_calls` (i.e. `finish_reason: :stop`): emit `Events::IterationEnd(finish_reason: :stop)`; return final content.
5. If `iterations >= max_iterations`: emit `Events::IterationEnd(finish_reason: :max_iterations)`; return best-effort content with a logged warning.

### Runner selection

```ruby
runner = if llm.supports_native_tools?(model: config.model) && tools.all? { |t| t.respond_to?(:json_schema) }
           ToolRunner.new(...)
         else
           LegacyReactRunner.new(...)
         end
```

A single INFO-level log line records the choice. Both runners emit the same event types, so streaming consumers don't care which is in use.

### Agent invariants preserved

- `Agent#use_tool(name, **args)` (direct invocation API) is unchanged.
- Both runners route tool execution through `Agent#use_tool` so the human-approval hook and memory recording are shared.
- `Agent#execute_task` return value gains a `tool_calls_history:` key. All existing keys are unchanged.

---

## 4. Streaming event model

A single typed event stream consumed by UIs, observability, cost tracking, and the tool runner itself.

### Event types — `RCrewAI::Events`

```ruby
module RCrewAI::Events
  Event           = Struct.new(:type, :timestamp, :agent, :iteration, keyword_init: true)

  TextDelta       = Class.new(Event)  # adds :text (partial)
  TextDone        = Class.new(Event)  # adds :text (full)
  ToolCallStart   = Class.new(Event)  # adds :tool, :args, :call_id
  ToolCallResult  = Class.new(Event)  # adds :tool, :call_id, :result, :duration_ms
  ToolCallError   = Class.new(Event)  # adds :tool, :call_id, :error
  Thinking        = Class.new(Event)  # adds :text (Anthropic extended thinking, etc.)
  Usage           = Class.new(Event)  # adds :prompt_tokens, :completion_tokens, :total_tokens, :cost_usd
  IterationStart  = Class.new(Event)  # adds :iteration_index
  IterationEnd    = Class.new(Event)  # adds :finish_reason
  Error           = Class.new(Event)  # adds :error
end
```

Every event carries `agent` (name) and `iteration` so consumers can correlate without external bookkeeping.

### Public API — three idioms

```ruby
# 1. Block form
crew.execute(stream: true) do |event|
  case event
  when RCrewAI::Events::TextDelta      then print event.text
  when RCrewAI::Events::ToolCallStart  then puts "→ #{event.tool}(#{event.args})"
  when RCrewAI::Events::Usage          then meter.record(event)
  end
end

# 2. Multiple listeners (good for UI + logging + metering simultaneously)
crew.execute(stream: [logger_sink, cost_sink, ui_sink])  # each responds to #call(event)

# 3. Convenience text-only
agent.execute_task(task).each_text_delta { |chunk| print chunk }
```

### Plumbing path

```
LLMClient (SSE parse) → ToolRunner (orchestrates) → Agent (tags :agent) → Crew (fans out)
```

Each layer is a Proc that calls the next. No coupling between producers and consumers.

### Per-provider SSE parsing

- **OpenAI:** `chat.completions` stream with `delta.content` + `delta.tool_calls[].function.arguments` (incremental JSON; assembled before emission).
- **Anthropic:** `message_delta` / `content_block_delta` / `input_json_delta` events.
- **Google:** `streamGenerateContent` with `candidates[].content.parts[].functionCall`.
- **Azure:** identical to OpenAI.
- **Ollama:** line-delimited JSON; `message.tool_calls` arrives as a single chunk (less granular but still streamed).

Each adapter normalizes to the canonical `Events::*` shape.

### Cost tracking

`Events::Usage` includes `cost_usd` computed from `lib/rcrewai/pricing.rb` (per-model price table for OpenAI/Anthropic/Google list prices, shipped at release time). Users can override:

```ruby
RCrewAI.configure do |c|
  c.pricing = { "gpt-4o" => { input: 2.50, output: 10.00 } }  # USD per 1M tokens
end
```

If a model isn't in the table, `cost_usd` is `nil` — not an error.

### Non-streaming callers

If `stream:` is not provided, the event stream is collected internally and discarded. Public return value is unchanged.

---

## 5. MCP client integration

MCP is JSON-RPC 2.0. We add a client that connects to MCP servers (stdio subprocess or HTTP) and surfaces remote tools as `RCrewAI::Tools::Base` instances — so they run through the same `ToolRunner`, schema validation, human-approval hook, memory recording, and event emission as native tools. No special-casing.

### Module — `RCrewAI::MCP`

```ruby
module RCrewAI::MCP
  class Client            # JSON-RPC 2.0 over a Transport
  class Transport::Stdio  # spawn subprocess, talk over stdin/stdout
  class Transport::Http   # Streamable HTTP per MCP spec (POST + SSE)
  class ToolAdapter       # wraps one MCP tool as Tools::Base
  class Error
end
```

### User-facing API

```ruby
# Stdio (subprocess) — most common deployment
github = RCrewAI::MCP::Client.connect(
  command: "npx",
  args:    ["-y", "@modelcontextprotocol/server-github"],
  env:     { "GITHUB_TOKEN" => ENV.fetch("GITHUB_TOKEN") }
)

# HTTP (remote MCP server)
linear = RCrewAI::MCP::Client.connect(
  url:     "https://mcp.linear.app/sse",
  headers: { "Authorization" => "Bearer #{ENV['LINEAR_TOKEN']}" }
)

agent = RCrewAI::Agent.new(
  name:  "engineer",
  role:  "Backend Engineer",
  tools: github.tools + linear.tools + [RCrewAI::Tools::FileWriter.new]
)
```

### What `client.tools` returns

On connect, the client performs the `initialize` handshake and then `tools/list`. Each remote tool becomes a `ToolAdapter` whose:

- `tool_name` ← MCP tool name, prefixed with the server name (e.g. `github__create_issue`) to avoid collisions.
- `description` ← MCP tool description.
- `json_schema` ← MCP tool's `inputSchema` (already JSON Schema — no translation).
- `execute(**args)` → sends `tools/call`, returns the result content (text / image / resource).

### Lifecycle

```ruby
client = RCrewAI::MCP::Client.connect(...)   # opens transport, handshakes, lists tools
# ...
client.close                                 # graceful shutdown

# Or block form (auto-closes):
RCrewAI::MCP::Client.with_connection(command: ...) do |client|
  crew.add_agent(RCrewAI::Agent.new(..., tools: client.tools))
  crew.execute
end
```

A finalizer plus `at_exit` hook ensure subprocesses are killed even on hard exit.

### Dependencies

No new gem dependency. We hand-roll a minimal JSON-RPC 2.0 client (~100 LOC) since we only need request/response + notifications. SSE is handled by the same parser used by the LLM clients.

---

## 6. Backward compatibility & migration

### Unchanged public surface (zero migration)

- `RCrewAI::Agent.new(name:, role:, goal:, tools: [...])`
- `RCrewAI::Crew.new(...).execute` (return shape unchanged when `stream:` is not passed)
- `RCrewAI::Task.new(...)`
- All `human_input`, `require_approval_for_*`, `manager`, `allow_delegation` flags
- Custom tools that subclass `Tools::Base` and implement `execute(**params)`

### Behavior changes a user might observe

1. **Tool calls are more reliable.** Agents using OpenAI / Anthropic / Google / Azure (or modern Ollama models) now use native function calling. Fewer "agent forgot to call the tool" and "argument got mangled" failures. *This is the headline win.*
2. **One new INFO log line per agent run** identifies the mode and provider. Suppressible via `config.log_level = :warn`.
3. **Tools without DSL declarations** get a permissive fallback schema and a one-time deprecation warning.

### Hard breaking changes (called out in CHANGELOG)

- `LLMClients::Base#chat` adds `tools:` and `stream:` keyword args. Subclasses outside the gem that override `chat` with an explicit kwarg list need to add these (or accept `**options`). Realistic blast radius: near-zero.
- `Agent#execute_task` return value gains a `tool_calls_history:` key. Pure addition; existing keys unchanged.

### Versioning

**0.3.0** — minor bump under 1.0 conventions. CHANGELOG explicitly lists the two hard breaks above.

### Migration guide (`docs/upgrading-to-0.3.md`)

1. *(Optional, recommended)* Add `tool_name`, `description`, `param` declarations to custom tools. Before/after example provided.
2. *(Optional)* Adopt streaming via `crew.execute(stream: ...) { |event| ... }`.
3. *(Optional)* Wire in MCP servers via `RCrewAI::MCP::Client.connect(...)`.
4. *(Only if affected)* If you subclassed `LLMClients::Base#chat` with explicit kwargs, add `tools: nil, stream: nil` to the signature.

### Companion gem (`rcrewai-rails`)

Needs a coordinated release. The Rails engine's `Crew#execute` ActiveJob wrapper will gain a `stream:` parameter that pipes events into ActionCable for live UI. Tracked as a follow-up issue, not blocking 0.3.0 of the core gem.

---

## 7. Testing strategy

### New specs

```
spec/
├── tool_schema_spec.rb              # DSL → JSON schema (all types, edge cases, validation)
├── tool_runner_spec.rb              # Multi-iteration loop, max_iterations, error recovery,
│                                    # human-approval hook, memory recording, event emission
├── legacy_react_runner_spec.rb      # Pins existing USE_TOOL[] behavior
├── events_spec.rb                   # Event tagging, fan-out to multiple sinks
├── mcp/
│   ├── client_spec.rb               # JSON-RPC framing, handshake, tools/list, tools/call
│   ├── transport/stdio_spec.rb      # Subprocess lifecycle, stderr passthrough, kill on close
│   ├── transport/http_spec.rb       # POST + SSE, header auth, reconnection
│   └── tool_adapter_spec.rb         # MCP tool → Tools::Base behavior parity
├── llm_clients/
│   ├── openai_spec.rb               # Tools payload shape, SSE delta parsing, tool_call assembly
│   ├── anthropic_spec.rb            # Tools shape, content_block_delta parsing, caching hook
│   ├── google_spec.rb               # functionDeclarations shape, streamGenerateContent
│   ├── azure_spec.rb                # Inherits OpenAI; one auth-shape smoke test
│   └── ollama_spec.rb               # Native-tools allowlist, ReAct fallback
├── pricing_spec.rb                  # Cost calculation; missing model returns nil
└── integration/
    ├── native_tool_calling_spec.rb  # End-to-end agent + real tool + recorded LLM responses
    ├── streaming_spec.rb            # End-to-end event stream with multiple consumers
    ├── mcp_end_to_end_spec.rb       # Real subprocess (fixture MCP server in spec/fixtures/)
    └── legacy_react_fallback_spec.rb# Old USE_TOOL[] path still works on tools w/o DSL
```

### Recording strategy

- **Unit tests** for LLM clients use **webmock** with fixture JSON/SSE bodies in `spec/fixtures/llm_responses/` — deterministic, fast, no network.
- **Integration tests** use **VCR cassettes** (already a dev dep) recorded once against real providers and committed. Re-record via `RECORD=true rspec`.
- **MCP integration** ships a tiny stdio MCP server (~50 LOC Ruby script) in `spec/fixtures/mcp_servers/` so CI doesn't need `npx`.

### Regression coverage

- `legacy_react_runner_spec.rb` pins current `USE_TOOL[]` semantics.
- Existing `agent_spec.rb` and `crew_spec.rb` get added cases for the new `stream:` kwarg (no-op when not provided) and the new `tool_calls_history:` return key.

### CI

- `.github/workflows/ci.yml` runs Ruby 3.0, 3.1, 3.2, 3.3 on Linux.
- MCP integration test gated by Ruby ≥ 3.1.

### Coverage target

`simplecov` (already a dev dep) configured to fail CI at <85% line coverage for `lib/rcrewai/{tool_schema,tool_runner,events,mcp}/**`. No coverage bar on legacy files in this PR.

### Out of scope for v1 tests

- Live MCP servers from the wild (Slack, GitHub) — too flaky for CI; the fixture server suffices.
- Real cost figures against provider invoices — only the calculator formula.

---

## Appendix A — Order of work (rough)

1. `ToolSchema` DSL + JSON schema emitter + per-provider schema adapters.
2. Migrate the 7 built-in tools to declare schemas.
3. `Events` module + `LLMClients::Base` new `chat` contract.
4. OpenAI native tools + streaming (reference implementation).
5. `ToolRunner` + extract `LegacyReactRunner` from `Agent#execute_task`.
6. Anthropic, Google, Azure native tools + streaming.
7. Ollama native tools (allowlist) + streaming + ReAct fallback.
8. `Pricing` + cost on `Events::Usage`.
9. MCP transports (stdio, HTTP) + `Client` + `ToolAdapter`.
10. CHANGELOG, `docs/upgrading-to-0.3.md`, `docs/mcp.md`, examples.

The implementation plan (writing-plans skill) will refine this into discrete, testable tasks with explicit dependencies.
