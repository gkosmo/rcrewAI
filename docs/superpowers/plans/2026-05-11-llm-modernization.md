# LLM Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReAct-style prompt-parsed tool calls with native function calling across all five LLM providers, add a typed streaming event model, and add an MCP client — without breaking existing user code.

**Architecture:** Dual-mode `ToolRunner` (native) + `LegacyReactRunner` (existing `USE_TOOL[]` fallback), driven from a refactored `Agent#execute_task`. A new `RCrewAI::Events` typed stream flows from per-provider SSE parsers through the runner to user-supplied sinks. MCP servers (stdio + HTTP) connect via a small JSON-RPC client and surface their tools as ordinary `Tools::Base` instances.

**Tech Stack:** Ruby 3.0+, Faraday (existing), concurrent-ruby (existing), webmock + VCR (existing dev deps). No new gem dependencies — SSE parsing and JSON-RPC are hand-rolled (~100 LOC each).

**Spec:** `docs/superpowers/specs/2026-05-11-llm-modernization-design.md`

**Versioning:** Currently `0.2.1`. This work ships as **`0.3.0`** (minor bump, two minor breaking changes called out below).

**Phases:**
- **Phase 1 (Tasks 1-5)** — Foundation: schema DSL, events, SSE parser, pricing, new chat contract. Ships nothing user-visible yet.
- **Phase 2 (Tasks 6-10)** — Native tools + streaming across all five providers + ToolRunner + Agent/Crew refactor. **Releasable as `0.3.0-rc1`.**
- **Phase 3 (Tasks 11-12)** — MCP client + docs/examples/CHANGELOG. **Releasable as `0.3.0`.**

A phase boundary is a clean checkpoint: commit, run the full suite, optionally cut a tag.

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `lib/rcrewai/tool_schema.rb` | Class-level DSL on `Tools::Base` + canonical JSON schema emitter |
| `lib/rcrewai/provider_schema.rb` | Reshape canonical schema → per-provider format |
| `lib/rcrewai/events.rb` | Typed event classes (`TextDelta`, `ToolCallStart`, …) + sink fan-out helper |
| `lib/rcrewai/sse_parser.rb` | Reusable SSE line/event parser used by all LLM clients and MCP HTTP transport |
| `lib/rcrewai/pricing.rb` | Per-model price table + `cost_for(model, usage)` helper |
| `lib/rcrewai/tool_runner.rb` | Native function-calling loop |
| `lib/rcrewai/legacy_react_runner.rb` | Extracted `USE_TOOL[]` loop from `agent.rb` (behavior-preserving) |
| `lib/rcrewai/mcp.rb` | MCP module entry + autoload glue |
| `lib/rcrewai/mcp/client.rb` | JSON-RPC client + handshake + `tools/list` + `tools/call` |
| `lib/rcrewai/mcp/transport/stdio.rb` | Stdio transport (Process.spawn + IO pipes) |
| `lib/rcrewai/mcp/transport/http.rb` | Streamable HTTP transport (Faraday + SSE) |
| `lib/rcrewai/mcp/tool_adapter.rb` | Wrap an MCP tool as `Tools::Base` |
| `docs/upgrading-to-0.3.md` | Migration guide |
| `docs/mcp.md` | MCP user docs |
| `examples/native_tools_example.rb` | Shows native tool calling end-to-end |
| `examples/streaming_example.rb` | Shows event streaming + cost tracking |
| `examples/mcp_example.rb` | Shows connecting to an MCP server |
| `spec/fixtures/mcp_servers/echo_server.rb` | Minimal Ruby stdio MCP server for tests |
| `spec/fixtures/llm_responses/**` | Recorded JSON / SSE bodies for client unit tests |

### Modified files

| Path | Change |
|---|---|
| `lib/rcrewai.rb` | Require new modules in dependency order |
| `lib/rcrewai/version.rb` | `"0.2.1"` → `"0.3.0"` |
| `lib/rcrewai/configuration.rb` | Add `pricing`, `ollama_native_tools`, `log_level` accessors |
| `lib/rcrewai/llm_clients/base.rb` | New `chat(messages:, tools: nil, stream: nil, **)` contract + `supports_native_tools?` |
| `lib/rcrewai/llm_clients/openai.rb` | Native tools + streaming (reference impl) |
| `lib/rcrewai/llm_clients/anthropic.rb` | Native tools + streaming + prompt-caching hook |
| `lib/rcrewai/llm_clients/google.rb` | Native tools + streaming |
| `lib/rcrewai/llm_clients/azure.rb` | Mostly inherits; auth shape only |
| `lib/rcrewai/llm_clients/ollama.rb` | Native tools (allowlist) + streaming |
| `lib/rcrewai/agent.rb` | Delegate execution to `ToolRunner` / `LegacyReactRunner`; new `tool_calls_history:` in return |
| `lib/rcrewai/crew.rb` | Accept `stream:` kwarg in `execute`; fan out to sinks |
| `lib/rcrewai/tools/*.rb` (7 files) | Add DSL declarations |
| `CHANGELOG.md` | 0.3.0 entry with breaking changes called out |
| `rcrewai.gemspec` | (no change unless we discover one; flagged in Task 12) |

---

# Phase 1 — Foundation

## Task 1: Tool Schema DSL

**Files:**
- Create: `lib/rcrewai/tool_schema.rb`
- Create: `lib/rcrewai/provider_schema.rb`
- Create: `spec/tool_schema_spec.rb`
- Create: `spec/provider_schema_spec.rb`
- Modify: `lib/rcrewai/tools/base.rb` (extend, do not break existing API)
- Modify: `lib/rcrewai.rb` (require new files)

- [ ] **Step 1.1: Write failing spec for canonical schema emission**

Create `spec/tool_schema_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::ToolSchema do
  describe 'DSL on Tools::Base subclass' do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name        "demo_tool"
        description      "A demo tool"
        param :query,       type: :string,  required: true, description: "A query"
        param :max_results, type: :integer, default: 10,    description: "How many"
        param :tags,        type: :array,   items: { type: :string }
        param :verbose,     type: :boolean, default: false
        param :mode,        type: :enum,    values: %w[fast slow]

        def execute(query:, max_results: 10, tags: [], verbose: false, mode: "fast")
          { query: query, max_results: max_results }
        end
      end
    end

    it 'exposes tool_name and description' do
      expect(tool_class.tool_name).to eq("demo_tool")
      expect(tool_class.description).to eq("A demo tool")
    end

    it 'emits canonical JSON schema' do
      schema = tool_class.json_schema
      expect(schema[:name]).to eq("demo_tool")
      expect(schema[:description]).to eq("A demo tool")
      expect(schema.dig(:parameters, :type)).to eq("object")
      expect(schema.dig(:parameters, :required)).to eq(["query"])
      props = schema.dig(:parameters, :properties)
      expect(props[:query]).to eq(type: "string", description: "A query")
      expect(props[:max_results]).to include(type: "integer", default: 10)
      expect(props[:tags]).to include(type: "array", items: { type: "string" })
      expect(props[:verbose]).to include(type: "boolean", default: false)
      expect(props[:mode]).to include(type: "string", enum: %w[fast slow])
    end

    it 'instance exposes json_schema' do
      expect(tool_class.new.json_schema).to eq(tool_class.json_schema)
    end
  end

  describe 'fallback when no DSL declared' do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        def execute(**params); params; end
      end
    end

    it 'returns a permissive schema' do
      schema = tool_class.json_schema
      expect(schema[:parameters]).to eq(
        type: "object",
        additionalProperties: true
      )
    end

    it 'prints deprecation warning once per class' do
      expect { tool_class.json_schema }.to output(/no DSL declarations/).to_stderr
      expect { tool_class.json_schema }.not_to output.to_stderr
    end
  end

  describe '#execute_with_validation' do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name "v"
        description "v"
        param :n, type: :integer, required: true
        def execute(n:); n * 2; end
      end
    end

    it 'coerces string integers' do
      expect(tool_class.new.execute_with_validation({ "n" => "7" })).to eq(14)
    end

    it 'raises ToolError on missing required' do
      expect { tool_class.new.execute_with_validation({}) }
        .to raise_error(RCrewAI::Tools::ToolError, /missing required param: n/i)
    end

    it 'raises ToolError on wrong type' do
      expect { tool_class.new.execute_with_validation({ "n" => "abc" }) }
        .to raise_error(RCrewAI::Tools::ToolError, /n must be integer/i)
    end
  end
end
```

- [ ] **Step 1.2: Run spec; expect failure**

Run: `bundle exec rspec spec/tool_schema_spec.rb`
Expected: `uninitialized constant RCrewAI::ToolSchema`

- [ ] **Step 1.3: Implement `lib/rcrewai/tool_schema.rb`**

```ruby
# frozen_string_literal: true

module RCrewAI
  module ToolSchema
    TYPE_MAP = {
      string: "string", integer: "integer", number: "number",
      boolean: "boolean", array: "array", object: "object", enum: "string"
    }.freeze

    def self.extended(base)
      base.instance_variable_set(:@params, [])
      base.instance_variable_set(:@tool_name, nil)
      base.instance_variable_set(:@description, nil)
    end

    def tool_name(name = nil)
      return @tool_name || name_default if name.nil?
      @tool_name = name.to_s
    end

    def description(desc = nil)
      return @description || "" if desc.nil?
      @description = desc.to_s
    end

    def param(name, type:, required: false, default: nil, description: nil, items: nil, values: nil, properties: nil)
      @params ||= []
      @params << {
        name: name, type: type, required: required, default: default,
        description: description, items: items, values: values, properties: properties
      }
    end

    def params
      @params || []
    end

    def json_schema
      props = {}
      required = []
      params.each do |p|
        entry = { type: TYPE_MAP.fetch(p[:type]) }
        entry[:description] = p[:description] if p[:description]
        entry[:default]     = p[:default]     unless p[:default].nil?
        entry[:items]       = stringify_type(p[:items])   if p[:items]
        entry[:enum]        = p[:values]      if p[:type] == :enum
        entry[:properties]  = p[:properties]  if p[:properties]
        props[p[:name]] = entry
        required << p[:name].to_s if p[:required]
      end

      if params.empty?
        warn_once_no_dsl!
        return {
          name: tool_name,
          description: description,
          parameters: { type: "object", additionalProperties: true }
        }
      end

      {
        name: tool_name,
        description: description,
        parameters: {
          type: "object",
          properties: props,
          required: required
        }
      }
    end

    private

    def name_default
      name.to_s.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    def stringify_type(h)
      return h unless h.is_a?(Hash) && h[:type].is_a?(Symbol)
      h.merge(type: TYPE_MAP.fetch(h[:type]))
    end

    def warn_once_no_dsl!
      return if @warned_no_dsl
      @warned_no_dsl = true
      Kernel.warn "[rcrewai] Tool #{name} has no DSL declarations; using permissive schema. See docs/upgrading-to-0.3.md"
    end
  end
end
```

- [ ] **Step 1.4: Extend `Tools::Base` to include the DSL and validation**

Modify `lib/rcrewai/tools/base.rb`. Add at top of file (after `require`s) and inside the class:

```ruby
require_relative '../tool_schema'

module RCrewAI
  module Tools
    class Base
      extend RCrewAI::ToolSchema

      def name
        @name ||= self.class.tool_name
      end

      def description
        @description ||= self.class.description
      end

      def json_schema
        self.class.json_schema
      end

      def execute_with_validation(args_hash)
        coerced = {}
        schema_params = self.class.params

        if schema_params.empty?
          # Permissive: pass through symbolized
          coerced = args_hash.transform_keys(&:to_sym)
          return execute(**coerced)
        end

        schema_params.each do |p|
          key_str = p[:name].to_s
          key_sym = p[:name].to_sym
          if args_hash.key?(key_str) || args_hash.key?(key_sym)
            raw = args_hash[key_str] || args_hash[key_sym]
            coerced[key_sym] = coerce(raw, p[:type], p[:name])
          elsif p[:required]
            raise ToolError, "missing required param: #{p[:name]}"
          end
        end

        execute(**coerced)
      end

      private

      def coerce(value, type, name)
        case type
        when :integer
          return value if value.is_a?(Integer)
          Integer(value.to_s)
        when :number
          return value if value.is_a?(Numeric)
          Float(value.to_s)
        when :boolean
          return value if [true, false].include?(value)
          %w[true 1 yes].include?(value.to_s.downcase)
        when :string, :enum
          value.to_s
        when :array, :object
          value
        else
          value
        end
      rescue ArgumentError, TypeError
        raise ToolError, "#{name} must be #{type}, got #{value.inspect}"
      end

      # ... existing code (initialize, execute, validate_params!, etc.) UNCHANGED ...
    end
  end
end
```

Keep the `initialize`, `execute`, `validate_params!`, `self.available_tools`, `self.create_tool`, `self.list_available_tools` methods exactly as they are today — only add the new code above.

- [ ] **Step 1.5: Add require in `lib/rcrewai.rb`**

Insert `require_relative 'rcrewai/tool_schema'` immediately before `require_relative 'rcrewai/tools/base'` in `lib/rcrewai.rb`.

- [ ] **Step 1.6: Run spec; expect pass**

Run: `bundle exec rspec spec/tool_schema_spec.rb`
Expected: all green.

- [ ] **Step 1.7: Write failing spec for provider-schema reshape**

Create `spec/provider_schema_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::ProviderSchema do
  let(:canonical) do
    {
      name: "search",
      description: "Search",
      parameters: {
        type: "object",
        properties: { q: { type: "string", description: "query" } },
        required: ["q"]
      }
    }
  end

  it 'reshapes for OpenAI' do
    expect(described_class.for(:openai, canonical)).to eq(
      type: "function",
      function: canonical
    )
  end

  it 'reshapes for Anthropic' do
    out = described_class.for(:anthropic, canonical)
    expect(out).to eq(
      name: "search",
      description: "Search",
      input_schema: canonical[:parameters]
    )
  end

  it 'reshapes for Google' do
    out = described_class.for(:google, canonical)
    expect(out).to eq(
      function_declarations: [{
        name: "search",
        description: "Search",
        parameters: canonical[:parameters]
      }]
    )
  end

  it 'reshapes for Ollama (same as OpenAI minus wrapper)' do
    out = described_class.for(:ollama, canonical)
    expect(out).to eq(type: "function", function: canonical)
  end

  it 'raises on unknown provider' do
    expect { described_class.for(:unknown, canonical) }
      .to raise_error(ArgumentError, /unknown provider/i)
  end
end
```

- [ ] **Step 1.8: Implement `lib/rcrewai/provider_schema.rb`**

```ruby
# frozen_string_literal: true

module RCrewAI
  module ProviderSchema
    module_function

    def for(provider, canonical)
      case provider.to_sym
      when :openai, :azure, :ollama
        { type: "function", function: canonical }
      when :anthropic
        {
          name: canonical[:name],
          description: canonical[:description],
          input_schema: canonical[:parameters]
        }
      when :google
        {
          function_declarations: [{
            name: canonical[:name],
            description: canonical[:description],
            parameters: canonical[:parameters]
          }]
        }
      else
        raise ArgumentError, "unknown provider #{provider.inspect}"
      end
    end

    def for_many(provider, canonicals)
      if provider.to_sym == :google
        { function_declarations: canonicals.map { |c| for(:google, c)[:function_declarations].first } }
      else
        canonicals.map { |c| for(provider, c) }
      end
    end
  end
end
```

- [ ] **Step 1.9: Add require in `lib/rcrewai.rb`**

Insert `require_relative 'rcrewai/provider_schema'` immediately after the `tool_schema` require.

- [ ] **Step 1.10: Run spec; expect pass**

Run: `bundle exec rspec spec/provider_schema_spec.rb`
Expected: all green.

- [ ] **Step 1.11: Commit**

```bash
git add lib/rcrewai/tool_schema.rb lib/rcrewai/provider_schema.rb \
        lib/rcrewai/tools/base.rb lib/rcrewai.rb \
        spec/tool_schema_spec.rb spec/provider_schema_spec.rb
git commit -m "feat(tool_schema): add DSL and per-provider schema reshape"
```

---

## Task 2: Events, SSE parser, Pricing

**Files:**
- Create: `lib/rcrewai/events.rb`
- Create: `lib/rcrewai/sse_parser.rb`
- Create: `lib/rcrewai/pricing.rb`
- Create: `spec/events_spec.rb`
- Create: `spec/sse_parser_spec.rb`
- Create: `spec/pricing_spec.rb`
- Modify: `lib/rcrewai.rb` (require new files)

- [ ] **Step 2.1: Write failing spec for events**

Create `spec/events_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::Events do
  it 'TextDelta carries text + agent + iteration' do
    e = described_class::TextDelta.new(text: "hi", agent: "a", iteration: 0, timestamp: Time.now)
    expect(e.text).to eq("hi")
    expect(e.agent).to eq("a")
    expect(e.iteration).to eq(0)
  end

  describe '.fan_out' do
    it 'forwards events to every sink' do
      received_a, received_b = [], []
      sink_a = ->(e) { received_a << e }
      sink_b = ->(e) { received_b << e }
      fan = described_class.fan_out([sink_a, sink_b])

      e = described_class::TextDelta.new(text: "x", agent: "a", iteration: 0, timestamp: Time.now)
      fan.call(e)
      expect(received_a).to eq([e])
      expect(received_b).to eq([e])
    end

    it 'isolates one sink raising from the others' do
      received = []
      bad  = ->(_) { raise "boom" }
      good = ->(e) { received << e }
      fan = described_class.fan_out([bad, good])
      e = described_class::TextDelta.new(text: "x", agent: "a", iteration: 0, timestamp: Time.now)
      expect { fan.call(e) }.not_to raise_error
      expect(received).to eq([e])
    end
  end
end
```

- [ ] **Step 2.2: Run spec; expect failure**

Run: `bundle exec rspec spec/events_spec.rb`
Expected: `uninitialized constant RCrewAI::Events`

- [ ] **Step 2.3: Implement `lib/rcrewai/events.rb`**

```ruby
# frozen_string_literal: true

module RCrewAI
  module Events
    BaseAttrs = %i[type timestamp agent iteration].freeze

    Event           = Struct.new(*BaseAttrs, keyword_init: true)
    TextDelta       = Struct.new(*BaseAttrs, :text,                                  keyword_init: true)
    TextDone        = Struct.new(*BaseAttrs, :text,                                  keyword_init: true)
    ToolCallStart   = Struct.new(*BaseAttrs, :tool, :args, :call_id,                 keyword_init: true)
    ToolCallResult  = Struct.new(*BaseAttrs, :tool, :call_id, :result, :duration_ms, keyword_init: true)
    ToolCallError   = Struct.new(*BaseAttrs, :tool, :call_id, :error,                keyword_init: true)
    Thinking        = Struct.new(*BaseAttrs, :text,                                  keyword_init: true)
    Usage           = Struct.new(*BaseAttrs, :prompt_tokens, :completion_tokens, :total_tokens, :cost_usd, keyword_init: true)
    IterationStart  = Struct.new(*BaseAttrs, :iteration_index,                       keyword_init: true)
    IterationEnd    = Struct.new(*BaseAttrs, :finish_reason,                         keyword_init: true)
    Error           = Struct.new(*BaseAttrs, :error,                                 keyword_init: true)

    # Returns a Proc that forwards each event to every sink, isolating exceptions.
    def self.fan_out(sinks)
      sinks = Array(sinks).compact
      lambda do |event|
        sinks.each do |s|
          begin
            s.call(event)
          rescue StandardError => e
            Kernel.warn "[rcrewai] event sink raised: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 2.4: Run spec; expect pass**

Run: `bundle exec rspec spec/events_spec.rb`
Expected: all green.

- [ ] **Step 2.5: Write failing spec for SSE parser**

Create `spec/sse_parser_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::SSEParser do
  it 'parses a simple data event' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("data: hello\n\n")
    expect(events).to eq([{ event: "message", data: "hello" }])
  end

  it 'splits multi-line data with newlines preserved' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("data: one\ndata: two\n\n")
    expect(events.first[:data]).to eq("one\ntwo")
  end

  it 'respects event: field' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("event: ping\ndata: {}\n\n")
    expect(events.first[:event]).to eq("ping")
  end

  it 'handles chunked feeds across event boundary' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("data: par")
    p.feed("tial\n")
    p.feed("\n")
    expect(events.first[:data]).to eq("partial")
  end

  it 'ignores comment lines' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed(": heartbeat\n\ndata: x\n\n")
    expect(events.length).to eq(1)
    expect(events.first[:data]).to eq("x")
  end
end
```

- [ ] **Step 2.6: Implement `lib/rcrewai/sse_parser.rb`**

```ruby
# frozen_string_literal: true

module RCrewAI
  # Minimal Server-Sent Events line parser per https://html.spec.whatwg.org/multipage/server-sent-events.html
  # Feed bytes via #feed(chunk); yields { event: String, data: String } per complete event.
  class SSEParser
    def initialize(&block)
      @on_event = block
      @buffer = +""
      @event = "message"
      @data_lines = []
    end

    def feed(chunk)
      @buffer << chunk
      while (idx = @buffer.index("\n"))
        line = @buffer.slice!(0, idx + 1).chomp
        if line.empty?
          dispatch
        elsif line.start_with?(":")
          # comment line, ignore
        elsif (colon = line.index(":"))
          field = line[0...colon]
          value = line[(colon + 1)..]
          value = value[1..] if value.start_with?(" ")
          handle_field(field, value)
        else
          handle_field(line, "")
        end
      end
    end

    private

    def handle_field(field, value)
      case field
      when "event" then @event = value
      when "data"  then @data_lines << value
      end
    end

    def dispatch
      return if @data_lines.empty?
      @on_event.call(event: @event, data: @data_lines.join("\n"))
      @event = "message"
      @data_lines = []
    end
  end
end
```

- [ ] **Step 2.7: Run spec; expect pass**

Run: `bundle exec rspec spec/sse_parser_spec.rb`
Expected: all green.

- [ ] **Step 2.8: Write failing spec for pricing**

Create `spec/pricing_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::Pricing do
  it 'computes cost for a known model' do
    cost = described_class.cost_for("gpt-4o", prompt_tokens: 1_000_000, completion_tokens: 1_000_000)
    expect(cost).to be > 0
  end

  it 'returns nil for unknown model' do
    cost = described_class.cost_for("definitely-not-real", prompt_tokens: 1, completion_tokens: 1)
    expect(cost).to be_nil
  end

  it 'accepts user overrides from configuration' do
    RCrewAI.configuration.pricing = { "totally-fake" => { input: 1.0, output: 2.0 } }
    cost = described_class.cost_for("totally-fake", prompt_tokens: 1_000_000, completion_tokens: 1_000_000)
    expect(cost).to eq(3.0)
  ensure
    RCrewAI.configuration.pricing = nil
  end
end
```

- [ ] **Step 2.9: Implement `lib/rcrewai/pricing.rb`**

```ruby
# frozen_string_literal: true

module RCrewAI
  module Pricing
    # Prices in USD per 1M tokens. List prices as of 2026-05; users can override.
    DEFAULT_PRICES = {
      # OpenAI
      "gpt-4o"            => { input: 2.50, output: 10.00 },
      "gpt-4o-mini"       => { input: 0.15, output: 0.60 },
      "gpt-4-turbo"       => { input: 10.00, output: 30.00 },
      "gpt-4"             => { input: 30.00, output: 60.00 },
      "gpt-3.5-turbo"     => { input: 0.50, output: 1.50 },
      # Anthropic
      "claude-opus-4-7"   => { input: 15.00, output: 75.00 },
      "claude-sonnet-4-6" => { input: 3.00,  output: 15.00 },
      "claude-haiku-4-5"  => { input: 0.80,  output: 4.00 },
      "claude-3-5-sonnet-20241022" => { input: 3.00, output: 15.00 },
      "claude-3-haiku-20240307"    => { input: 0.25, output: 1.25 },
      # Google
      "gemini-1.5-pro"    => { input: 1.25, output: 5.00 },
      "gemini-1.5-flash"  => { input: 0.075, output: 0.30 }
    }.freeze

    module_function

    def cost_for(model, prompt_tokens:, completion_tokens:)
      table = RCrewAI.configuration.pricing || {}
      entry = table[model] || DEFAULT_PRICES[model]
      return nil unless entry
      ((prompt_tokens * entry[:input]) + (completion_tokens * entry[:output])) / 1_000_000.0
    end
  end
end
```

- [ ] **Step 2.10: Add `pricing` accessor to Configuration**

Modify `lib/rcrewai/configuration.rb`:

```ruby
# In the attr_accessor lines near the top:
attr_accessor :pricing, :ollama_native_tools, :log_level

# In initialize, add at the bottom of the body (before load_from_env):
@pricing = nil
@ollama_native_tools = nil  # nil = auto-detect via allowlist
@log_level = :info
```

- [ ] **Step 2.11: Add requires in `lib/rcrewai.rb`**

Add these in order after `require_relative 'rcrewai/configuration'`:

```ruby
require_relative 'rcrewai/events'
require_relative 'rcrewai/sse_parser'
require_relative 'rcrewai/pricing'
```

- [ ] **Step 2.12: Run spec; expect pass**

Run: `bundle exec rspec spec/pricing_spec.rb spec/events_spec.rb spec/sse_parser_spec.rb`
Expected: all green.

- [ ] **Step 2.13: Commit**

```bash
git add lib/rcrewai/events.rb lib/rcrewai/sse_parser.rb lib/rcrewai/pricing.rb \
        lib/rcrewai/configuration.rb lib/rcrewai.rb \
        spec/events_spec.rb spec/sse_parser_spec.rb spec/pricing_spec.rb
git commit -m "feat(core): add Events, SSE parser, and Pricing modules"
```

---

## Task 3: New LLMClients::Base contract

**Files:**
- Modify: `lib/rcrewai/llm_clients/base.rb`
- Create: `spec/llm_clients/base_spec.rb`

This task only updates the abstract contract — provider implementations come in later tasks. We add new optional kwargs (`tools:`, `tool_choice:`, `stream:`) and a `supports_native_tools?` method with sensible defaults. Existing callers pass nothing extra and keep working.

- [ ] **Step 3.1: Write failing spec**

Create `spec/llm_clients/base_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::LLMClients::Base do
  let(:config) { RCrewAI.configuration.tap { |c| c.api_key = "x"; c.model = "m" } }

  it 'chat raises NotImplementedError by default' do
    expect { described_class.new(config).chat(messages: []) }
      .to raise_error(NotImplementedError)
  end

  it 'chat accepts tools and stream kwargs without ArgumentError' do
    subclass = Class.new(described_class) do
      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **opts)
        { content: "ok", tool_calls: [], usage: {}, finish_reason: :stop, model: "m", provider: :test }
      end
      def validate_config!; end
    end
    out = subclass.new(config).chat(messages: [], tools: [{ name: "x" }], stream: ->(_) {})
    expect(out[:content]).to eq("ok")
  end

  it 'supports_native_tools? defaults to true' do
    subclass = Class.new(described_class) do
      def chat(messages:, **opts); end
      def validate_config!; end
    end
    expect(subclass.new(config).supports_native_tools?(model: "m")).to be true
  end
end
```

- [ ] **Step 3.2: Run spec; expect failure**

Run: `bundle exec rspec spec/llm_clients/base_spec.rb`
Expected: failures on the new signature.

- [ ] **Step 3.3: Update `lib/rcrewai/llm_clients/base.rb`**

Replace the `def chat` signature with the new one, and add `supports_native_tools?`:

```ruby
def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
  raise NotImplementedError, "Subclasses must implement #chat method"
end

def supports_native_tools?(model: config.model)
  true
end
```

Leave everything else in the file unchanged.

- [ ] **Step 3.4: Run spec; expect pass**

Run: `bundle exec rspec spec/llm_clients/base_spec.rb`
Expected: all green.

- [ ] **Step 3.5: Run full existing suite for regressions**

Run: `bundle exec rspec`
Expected: all green. If any existing `chat` mocks/stubs break because they don't accept `tools:`/`stream:`, fix them by using `**opts` in the subclass override.

- [ ] **Step 3.6: Commit**

```bash
git add lib/rcrewai/llm_clients/base.rb spec/llm_clients/base_spec.rb
git commit -m "feat(llm_clients): new chat() contract with tools and stream kwargs"
```

---

## Task 4: Migrate built-in tools to DSL

**Files:**
- Modify: `lib/rcrewai/tools/web_search.rb`
- Modify: `lib/rcrewai/tools/file_reader.rb`
- Modify: `lib/rcrewai/tools/file_writer.rb`
- Modify: `lib/rcrewai/tools/sql_database.rb`
- Modify: `lib/rcrewai/tools/email_sender.rb`
- Modify: `lib/rcrewai/tools/code_executor.rb`
- Modify: `lib/rcrewai/tools/pdf_processor.rb`
- Create: `spec/tools/builtin_tools_schema_spec.rb`

We add 3-7 lines of DSL to each tool. The `execute` method body is unchanged.

- [ ] **Step 4.1: Write failing spec that asserts every built-in tool has a non-permissive schema**

Create `spec/tools/builtin_tools_schema_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe "built-in tool schemas" do
  RCrewAI::Tools::Base.available_tools.each do |klass|
    describe klass do
      it 'declares a tool_name' do
        expect(klass.tool_name).not_to be_empty
      end

      it 'declares a description' do
        expect(klass.description).not_to be_empty
      end

      it 'declares at least one param' do
        expect(klass.params).not_to be_empty
      end

      it 'emits a non-permissive JSON schema' do
        schema = klass.json_schema
        expect(schema.dig(:parameters, :additionalProperties)).to be_nil
        expect(schema.dig(:parameters, :properties)).to be_a(Hash)
      end
    end
  end
end
```

- [ ] **Step 4.2: Run spec; expect failures across all 7 tools**

Run: `bundle exec rspec spec/tools/builtin_tools_schema_spec.rb`
Expected: 7 × 4 = 28 failures (permissive schema, empty params).

- [ ] **Step 4.3: Migrate `web_search.rb`**

Modify `lib/rcrewai/tools/web_search.rb`. Inspect the existing `execute` signature to determine params, then add at top of class body (right after `class WebSearch < Base`):

```ruby
tool_name        "web_search"
description      "Search the web using DuckDuckGo and return top results"
param :query,       type: :string,  required: true,
                    description: "Search query"
param :max_results, type: :integer, default: 10,
                    description: "Number of results to return (1-25)"
```

Leave everything else unchanged.

- [ ] **Step 4.4: Migrate `file_reader.rb`**

```ruby
tool_name        "file_reader"
description      "Read the contents of a text file from disk"
param :path,     type: :string, required: true,
                 description: "Absolute or relative path to the file"
param :encoding, type: :string, default: "utf-8",
                 description: "Text encoding"
```

- [ ] **Step 4.5: Migrate `file_writer.rb`**

```ruby
tool_name        "file_writer"
description      "Write content to a text file on disk"
param :path,     type: :string,  required: true, description: "Path to write to"
param :content,  type: :string,  required: true, description: "Content to write"
param :append,   type: :boolean, default: false, description: "Append instead of overwrite"
```

- [ ] **Step 4.6: Migrate `sql_database.rb`**

```ruby
tool_name        "sql_database"
description      "Execute a read-only SQL query and return rows as JSON"
param :query,             type: :string, required: true,
                          description: "SQL query (SELECT only by default)"
param :connection_string, type: :string, required: false,
                          description: "Optional override for the configured DB URL"
```

- [ ] **Step 4.7: Migrate `email_sender.rb`**

```ruby
tool_name        "email_sender"
description      "Send an email via configured SMTP"
param :to,      type: :string,  required: true, description: "Recipient address"
param :subject, type: :string,  required: true, description: "Email subject"
param :body,    type: :string,  required: true, description: "Email body (plain text)"
param :html,    type: :boolean, default: false, description: "Treat body as HTML"
```

- [ ] **Step 4.8: Migrate `code_executor.rb`**

```ruby
tool_name        "code_executor"
description      "Execute code in a sandboxed subprocess"
param :code,     type: :string, required: true, description: "Source code to run"
param :language, type: :enum,   required: true, values: %w[ruby python javascript bash],
                 description: "Language of the code"
param :timeout,  type: :integer, default: 30, description: "Max execution seconds"
```

- [ ] **Step 4.9: Migrate `pdf_processor.rb`**

```ruby
tool_name        "pdf_processor"
description      "Extract text from a PDF file"
param :path,      type: :string,  required: true, description: "Path to the PDF"
param :max_pages, type: :integer, default: 100,   description: "Maximum pages to read"
```

- [ ] **Step 4.10: Run spec; expect pass**

Run: `bundle exec rspec spec/tools/builtin_tools_schema_spec.rb`
Expected: all green.

- [ ] **Step 4.11: Run full suite for regressions**

Run: `bundle exec rspec`
Expected: all green. If any tool spec breaks because `name` is now derived from `tool_name`, fix the assertion to use the declared name.

- [ ] **Step 4.12: Commit**

```bash
git add lib/rcrewai/tools/*.rb spec/tools/builtin_tools_schema_spec.rb
git commit -m "feat(tools): declare DSL schemas for all built-in tools"
```

---

## Task 5: Phase 1 checkpoint

- [ ] **Step 5.1: Run full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 5.2: Confirm no behavior change for existing users**

Run an existing example end-to-end (mock or real LLM) to confirm nothing observable has changed yet:

```bash
ruby examples/async_execution_example.rb 2>&1 | head -30
```

Expected: same output as before this branch.

- [ ] **Step 5.3: Tag phase boundary**

```bash
git tag phase-1-foundation
```

Phase 1 complete. New infrastructure exists but no user-visible behavior has changed. Move to Phase 2.

---

# Phase 2 — Native tools + streaming + runner refactor

## Task 6: OpenAI native tools + streaming (reference impl)

**Files:**
- Modify: `lib/rcrewai/llm_clients/openai.rb`
- Create: `spec/llm_clients/openai_spec.rb`
- Create: `spec/fixtures/llm_responses/openai/tool_call.json`
- Create: `spec/fixtures/llm_responses/openai/stream_text.sse`
- Create: `spec/fixtures/llm_responses/openai/stream_tool_call.sse`

- [ ] **Step 6.1: Capture fixture: non-streamed tool call response**

Create `spec/fixtures/llm_responses/openai/tool_call.json`:

```json
{
  "id": "chatcmpl-xyz",
  "model": "gpt-4o",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_1",
        "type": "function",
        "function": { "name": "web_search", "arguments": "{\"query\":\"ruby\"}" }
      }]
    },
    "finish_reason": "tool_calls"
  }],
  "usage": { "prompt_tokens": 50, "completion_tokens": 10, "total_tokens": 60 }
}
```

- [ ] **Step 6.2: Capture fixture: streamed text response**

Create `spec/fixtures/llm_responses/openai/stream_text.sse`:

```
data: {"id":"1","choices":[{"index":0,"delta":{"role":"assistant","content":"Hel"},"finish_reason":null}]}

data: {"id":"1","choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":null}]}

data: {"id":"1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}

data: [DONE]

```

- [ ] **Step 6.3: Capture fixture: streamed tool call**

Create `spec/fixtures/llm_responses/openai/stream_tool_call.sse`:

```
data: {"id":"1","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"web_search","arguments":""}}]},"finish_reason":null}]}

data: {"id":"1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"que"}}]},"finish_reason":null}]}

data: {"id":"1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ry\":\"ruby\"}"}}]},"finish_reason":null}]}

data: {"id":"1","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":40,"completion_tokens":12,"total_tokens":52}}

data: [DONE]

```

- [ ] **Step 6.4: Write failing spec**

Create `spec/llm_clients/openai_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::OpenAI do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :openai
      c.openai_api_key = "test-key"
      c.openai_model = "gpt-4o"
    end
  end
  let(:client) { described_class.new(config) }

  describe '#chat with tools (non-streaming)' do
    it 'sends tools in OpenAI shape and returns tool_calls' do
      tool_schema = {
        name: "web_search",
        description: "Search",
        parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
      }

      stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with(body: hash_including(
          "model"  => "gpt-4o",
          "tools"  => [{ "type" => "function", "function" => tool_schema.transform_keys(&:to_s) }]
        ))
        .to_return(status: 200, body: File.read("spec/fixtures/llm_responses/openai/tool_call.json"),
                   headers: { "Content-Type" => "application/json" })

      result = client.chat(messages: [{ role: "user", content: "hi" }], tools: [tool_schema])

      expect(stub).to have_been_requested
      expect(result[:content]).to be_nil
      expect(result[:tool_calls]).to eq([{
        id: "call_1", name: "web_search", arguments: { "query" => "ruby" }
      }])
      expect(result[:finish_reason]).to eq(:tool_calls)
      expect(result[:usage]).to eq(prompt_tokens: 50, completion_tokens: 10, total_tokens: 60)
    end
  end

  describe '#chat with stream:' do
    it 'emits TextDelta events and returns final assembled result' do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 200, body: File.read("spec/fixtures/llm_responses/openai/stream_text.sse"),
                   headers: { "Content-Type" => "text/event-stream" })

      events = []
      result = client.chat(messages: [{ role: "user", content: "hi" }],
                           stream: ->(e) { events << e })

      text_events = events.select { |e| e.is_a?(RCrewAI::Events::TextDelta) }
      expect(text_events.map(&:text)).to eq(%w[Hel lo])
      expect(result[:content]).to eq("Hello")
      expect(result[:finish_reason]).to eq(:stop)
      expect(events.last).to be_a(RCrewAI::Events::Usage)
    end

    it 'assembles streamed tool_call arguments' do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 200, body: File.read("spec/fixtures/llm_responses/openai/stream_tool_call.sse"),
                   headers: { "Content-Type" => "text/event-stream" })

      events = []
      result = client.chat(messages: [{ role: "user", content: "search" }],
                           tools: [{ name: "web_search", description: "x",
                                     parameters: { type: "object", properties: {}, required: [] } }],
                           stream: ->(e) { events << e })

      expect(result[:tool_calls]).to eq([{ id: "call_1", name: "web_search", arguments: { "query" => "ruby" } }])
      expect(result[:finish_reason]).to eq(:tool_calls)
    end
  end

  describe '#supports_native_tools?' do
    it 'returns true for any OpenAI model' do
      expect(client.supports_native_tools?(model: "gpt-4o")).to be true
    end
  end
end
```

- [ ] **Step 6.5: Run spec; expect failure**

Run: `bundle exec rspec spec/llm_clients/openai_spec.rb`
Expected: failures (current OpenAI client doesn't accept `tools:`, no streaming).

- [ ] **Step 6.6: Rewrite `lib/rcrewai/llm_clients/openai.rb`**

Replace the file body (keeping the class name and module) with:

```ruby
# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'base'
require_relative '../events'
require_relative '../sse_parser'
require_relative '../provider_schema'
require_relative '../pricing'

module RCrewAI
  module LLMClients
    class OpenAI < Base
      BASE_URL = 'https://api.openai.com/v1'

      def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
        payload = {
          model: config.model,
          messages: messages,
          temperature: options[:temperature] || config.temperature,
          max_tokens: options[:max_tokens] || config.max_tokens
        }.compact

        if tools && !tools.empty?
          payload[:tools] = ProviderSchema.for_many(:openai, tools)
          payload[:tool_choice] = tool_choice if tool_choice != :auto
        end

        if stream
          payload[:stream] = true
          payload[:stream_options] = { include_usage: true }
          stream_chat(payload, stream)
        else
          plain_chat(payload)
        end
      end

      def supports_native_tools?(model: config.model)
        true
      end

      private

      def plain_chat(payload)
        url = "#{BASE_URL}/chat/completions"
        log_request(:post, url, payload)
        response = http_client.post(url, payload, build_headers.merge(auth_header))
        body = handle_response(response)
        normalize_non_streaming(body)
      end

      def stream_chat(payload, sink)
        url = "#{BASE_URL}/chat/completions"
        log_request(:post, url, payload)

        assembled_text = +""
        tool_calls_by_index = {}
        final_usage = nil
        finish_reason = nil

        parser = SSEParser.new do |sse|
          next if sse[:data] == "[DONE]"
          data = JSON.parse(sse[:data])
          choice = data.dig("choices", 0) || {}
          delta = choice["delta"] || {}

          if delta["content"]
            assembled_text << delta["content"]
            sink.call(Events::TextDelta.new(
              type: :text_delta, timestamp: Time.now, agent: nil, iteration: nil,
              text: delta["content"]
            ))
          end

          Array(delta["tool_calls"]).each do |tc|
            idx = tc["index"]
            tool_calls_by_index[idx] ||= { id: nil, name: nil, arguments: +"" }
            tool_calls_by_index[idx][:id]   ||= tc["id"]
            tool_calls_by_index[idx][:name] ||= tc.dig("function", "name")
            tool_calls_by_index[idx][:arguments] << (tc.dig("function", "arguments") || "")
          end

          finish_reason ||= choice["finish_reason"]&.to_sym

          if data["usage"]
            final_usage = {
              prompt_tokens:     data["usage"]["prompt_tokens"],
              completion_tokens: data["usage"]["completion_tokens"],
              total_tokens:      data["usage"]["total_tokens"]
            }
          end
        end

        streaming_post(url, payload) do |chunk|
          parser.feed(chunk)
        end

        tool_calls = tool_calls_by_index.values.map do |tc|
          { id: tc[:id], name: tc[:name], arguments: tc[:arguments].empty? ? {} : JSON.parse(tc[:arguments]) }
        end

        if final_usage
          sink.call(Events::Usage.new(
            type: :usage, timestamp: Time.now, agent: nil, iteration: nil,
            prompt_tokens: final_usage[:prompt_tokens],
            completion_tokens: final_usage[:completion_tokens],
            total_tokens: final_usage[:total_tokens],
            cost_usd: Pricing.cost_for(config.model,
                                        prompt_tokens: final_usage[:prompt_tokens],
                                        completion_tokens: final_usage[:completion_tokens])
          ))
        end

        {
          content: assembled_text.empty? ? nil : assembled_text,
          tool_calls: tool_calls,
          usage: final_usage || {},
          finish_reason: finish_reason || :stop,
          model: config.model,
          provider: :openai
        }
      end

      def streaming_post(url, payload, &on_chunk)
        conn = Faraday.new do |f|
          f.request :json
          f.options.timeout = config.timeout
          f.adapter Faraday.default_adapter
        end
        conn.post(url) do |req|
          req.headers = build_headers.merge(auth_header)
          req.body = payload.to_json
          req.options.on_data = proc { |chunk, _| on_chunk.call(chunk) }
        end
      end

      def normalize_non_streaming(body)
        choice = body.dig("choices", 0) || {}
        msg = choice["message"] || {}
        tool_calls = Array(msg["tool_calls"]).map do |tc|
          {
            id: tc["id"],
            name: tc.dig("function", "name"),
            arguments: JSON.parse(tc.dig("function", "arguments") || "{}")
          }
        end
        {
          content: msg["content"],
          tool_calls: tool_calls,
          usage: {
            prompt_tokens:     body.dig("usage", "prompt_tokens"),
            completion_tokens: body.dig("usage", "completion_tokens"),
            total_tokens:      body.dig("usage", "total_tokens")
          },
          finish_reason: (choice["finish_reason"] || "stop").to_sym,
          model: body["model"] || config.model,
          provider: :openai
        }
      end

      def auth_header
        { 'Authorization' => "Bearer #{config.openai_api_key || config.api_key}" }
      end

      def validate_config!
        raise ConfigurationError, "OpenAI API key required" unless config.openai_api_key || config.api_key
        raise ConfigurationError, "Model required" unless config.model
      end
    end
  end
end
```

- [ ] **Step 6.7: Run spec; expect pass**

Run: `bundle exec rspec spec/llm_clients/openai_spec.rb`
Expected: all green.

- [ ] **Step 6.8: Commit**

```bash
git add lib/rcrewai/llm_clients/openai.rb spec/llm_clients/openai_spec.rb \
        spec/fixtures/llm_responses/openai/
git commit -m "feat(openai): native tool calling and SSE streaming"
```

---

## Task 7: ToolRunner + LegacyReactRunner

**Files:**
- Create: `lib/rcrewai/tool_runner.rb`
- Create: `lib/rcrewai/legacy_react_runner.rb`
- Create: `spec/tool_runner_spec.rb`
- Create: `spec/legacy_react_runner_spec.rb`
- Modify: `lib/rcrewai.rb`

The `LegacyReactRunner` is a straight extraction of the existing prompt-template + regex-parsing code from `agent.rb` (lines ~280-360). Behavior must be identical; we just move it to its own class.

- [ ] **Step 7.1: Write failing spec for ToolRunner happy path**

Create `spec/tool_runner_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

class FakeTool < RCrewAI::Tools::Base
  tool_name "echo"
  description "echo args back"
  param :msg, type: :string, required: true
  def execute(msg:); "echoed: #{msg}"; end
end

RSpec.describe RCrewAI::ToolRunner do
  let(:tool) { FakeTool.new }
  let(:agent) do
    double("Agent",
           name: "a",
           memory: double("Memory", add_tool_usage: nil),
           require_approval_for_tools?: false)
  end

  context 'when LLM responds with a tool_call then a final answer' do
    let(:llm) do
      responses = [
        { content: nil, tool_calls: [{ id: "c1", name: "echo", arguments: { "msg" => "hi" } }],
          usage: {}, finish_reason: :tool_calls, model: "m", provider: :test },
        { content: "Done.", tool_calls: [], usage: {},
          finish_reason: :stop, model: "m", provider: :test }
      ]
      llm = double("LLM")
      allow(llm).to receive(:chat) { responses.shift }
      llm
    end

    it 'runs to completion in 2 iterations with tool result threaded in' do
      events = []
      runner = described_class.new(agent: agent, llm: llm, tools: [tool],
                                   event_sink: ->(e) { events << e })
      result = runner.run(messages: [{ role: "user", content: "echo hi" }])

      expect(result[:content]).to eq("Done.")
      expect(result[:iterations]).to eq(2)
      expect(result[:tool_calls_history]).to eq([
        { tool: "echo", args: { "msg" => "hi" }, result: "echoed: hi", duration_ms: kind_of(Integer) }
      ])
      types = events.map { |e| e.class }
      expect(types).to include(RCrewAI::Events::ToolCallStart, RCrewAI::Events::ToolCallResult)
    end

    it 'records tool usage in agent memory' do
      expect(agent.memory).to receive(:add_tool_usage).with("echo", { "msg" => "hi" }, "echoed: hi")
      runner = described_class.new(agent: agent, llm: llm, tools: [tool])
      runner.run(messages: [{ role: "user", content: "echo hi" }])
    end
  end

  context 'when a tool raises' do
    let(:bad_tool) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name "bad"
        description "bad"
        param :x, type: :string, required: true
        def execute(x:); raise "boom"; end
      end.new
    end

    let(:llm) do
      responses = [
        { content: nil, tool_calls: [{ id: "c1", name: "bad", arguments: { "x" => "y" } }],
          usage: {}, finish_reason: :tool_calls, model: "m", provider: :test },
        { content: "Recovered.", tool_calls: [], usage: {},
          finish_reason: :stop, model: "m", provider: :test }
      ]
      double("LLM").tap { |l| allow(l).to receive(:chat) { responses.shift } }
    end

    it 'emits ToolCallError, threads error back into messages, continues' do
      events = []
      runner = described_class.new(agent: agent, llm: llm, tools: [bad_tool],
                                   event_sink: ->(e) { events << e })
      result = runner.run(messages: [{ role: "user", content: "go" }])

      expect(result[:content]).to eq("Recovered.")
      expect(events.any? { |e| e.is_a?(RCrewAI::Events::ToolCallError) }).to be true
    end
  end

  context 'when max_iterations is reached' do
    let(:llm) do
      always_tool = {
        content: nil, tool_calls: [{ id: "c", name: "echo", arguments: { "msg" => "x" } }],
        usage: {}, finish_reason: :tool_calls, model: "m", provider: :test
      }
      double("LLM").tap { |l| allow(l).to receive(:chat).and_return(always_tool) }
    end

    it 'stops after max_iterations and returns best-effort' do
      runner = described_class.new(agent: agent, llm: llm, tools: [tool], max_iterations: 3)
      result = runner.run(messages: [{ role: "user", content: "loop" }])
      expect(result[:iterations]).to eq(3)
      expect(result[:finish_reason]).to eq(:max_iterations)
    end
  end
end
```

- [ ] **Step 7.2: Run spec; expect failure**

Run: `bundle exec rspec spec/tool_runner_spec.rb`
Expected: `uninitialized constant RCrewAI::ToolRunner`

- [ ] **Step 7.3: Implement `lib/rcrewai/tool_runner.rb`**

```ruby
# frozen_string_literal: true

require_relative 'events'
require_relative 'provider_schema'

module RCrewAI
  class ToolRunner
    DEFAULT_MAX_ITERATIONS = 10

    def initialize(agent:, llm:, tools:, max_iterations: DEFAULT_MAX_ITERATIONS, event_sink: nil)
      @agent = agent
      @llm = llm
      @tools = tools
      @tools_by_name = tools.each_with_object({}) { |t, h| h[t.name] = t }
      @max_iterations = max_iterations
      @sink = event_sink || ->(_) {}
    end

    def run(messages:)
      msgs = messages.dup
      history = []
      iter = 0
      total_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }

      while iter < @max_iterations
        iter += 1
        emit(Events::IterationStart, iteration_index: iter)

        response = @llm.chat(
          messages: msgs,
          tools: @tools.map(&:json_schema),
          stream: ->(e) { tagged = retag(e, iter); @sink.call(tagged) }
        )
        accumulate_usage(total_usage, response[:usage])

        if response[:tool_calls].nil? || response[:tool_calls].empty?
          emit(Events::IterationEnd, finish_reason: response[:finish_reason], iteration: iter)
          return finalize(content: response[:content], history: history, iter: iter,
                          finish_reason: response[:finish_reason], usage: total_usage)
        end

        # append assistant tool-call message
        msgs << { role: "assistant", content: response[:content], tool_calls: response[:tool_calls] }

        response[:tool_calls].each do |tc|
          tool = @tools_by_name[tc[:name]]
          emit(Events::ToolCallStart, tool: tc[:name], args: tc[:arguments], call_id: tc[:id], iteration: iter)

          if tool.nil?
            err = "tool not found: #{tc[:name]}"
            emit(Events::ToolCallError, tool: tc[:name], call_id: tc[:id], error: err, iteration: iter)
            msgs << tool_result_message(tc[:id], "ERROR: #{err}")
            next
          end

          started = monotonic_ms
          begin
            result = tool.execute_with_validation(tc[:arguments] || {})
            duration = monotonic_ms - started
            @agent.memory.add_tool_usage(tc[:name], tc[:arguments], result) if @agent.respond_to?(:memory) && @agent.memory
            emit(Events::ToolCallResult, tool: tc[:name], call_id: tc[:id], result: result,
                 duration_ms: duration, iteration: iter)
            history << { tool: tc[:name], args: tc[:arguments], result: result, duration_ms: duration }
            msgs << tool_result_message(tc[:id], result.to_s)
          rescue StandardError => e
            emit(Events::ToolCallError, tool: tc[:name], call_id: tc[:id], error: e.message, iteration: iter)
            msgs << tool_result_message(tc[:id], "ERROR: #{e.message}")
          end
        end

        emit(Events::IterationEnd, finish_reason: :tool_calls, iteration: iter)
      end

      finalize(content: nil, history: history, iter: iter, finish_reason: :max_iterations, usage: total_usage)
    end

    private

    def tool_result_message(call_id, content)
      { role: "tool", tool_call_id: call_id, content: content }
    end

    def emit(klass, **attrs)
      @sink.call(klass.new(timestamp: Time.now, agent: @agent.respond_to?(:name) ? @agent.name : nil,
                           iteration: attrs.delete(:iteration), type: klass.name.split("::").last.downcase.to_sym, **attrs))
    end

    def retag(event, iter)
      event.agent = @agent.respond_to?(:name) ? @agent.name : nil if event.respond_to?(:agent=)
      event.iteration = iter if event.respond_to?(:iteration=) && event.iteration.nil?
      event
    end

    def accumulate_usage(total, partial)
      return unless partial.is_a?(Hash)
      total[:prompt_tokens]     += partial[:prompt_tokens]     || 0
      total[:completion_tokens] += partial[:completion_tokens] || 0
      total[:total_tokens]      += partial[:total_tokens]      || 0
    end

    def finalize(content:, history:, iter:, finish_reason:, usage:)
      { content: content, tool_calls_history: history, usage: usage, iterations: iter, finish_reason: finish_reason }
    end

    def monotonic_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
    end
  end
end
```

- [ ] **Step 7.4: Run spec; expect pass**

Run: `bundle exec rspec spec/tool_runner_spec.rb`
Expected: all green.

- [ ] **Step 7.5: Extract LegacyReactRunner from agent.rb**

Read `lib/rcrewai/agent.rb` lines 280-360 (the prompt-building + `USE_TOOL[]` regex-scanning section). Copy that code into `lib/rcrewai/legacy_react_runner.rb` with this skeleton:

```ruby
# frozen_string_literal: true

require_relative 'events'

module RCrewAI
  class LegacyReactRunner
    def initialize(agent:, llm:, tools:, max_iterations: 10, event_sink: nil)
      @agent = agent
      @llm = llm
      @tools = tools
      @max_iterations = max_iterations
      @sink = event_sink || ->(_) {}
    end

    def run(messages:)
      # MOVE the existing prompt-building, LLM call, regex scanning, and
      # tool dispatch logic from Agent#execute_task verbatim. Wrap iterations
      # in Events::IterationStart / IterationEnd. Emit Events::TextDone with
      # the final content. Return shape:
      #   { content:, tool_calls_history:, usage:, iterations:, finish_reason: }
    end

    # ... helper methods extracted from agent.rb (parse_tool_params, etc.) ...
  end
end
```

Fill the body by copying from `agent.rb` exactly. The goal is **behavior-preserving** extraction. Reference `Agent#use_tool` through the injected `@agent`.

- [ ] **Step 7.6: Write spec that pins legacy behavior**

Create `spec/legacy_react_runner_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::LegacyReactRunner do
  let(:tool) { FakeTool.new }  # defined in tool_runner_spec.rb; load helper or inline-define
  let(:agent) { double("Agent", name: "a", memory: double(add_tool_usage: nil),
                        available_tools_description: "- echo: echo") }

  it 'parses USE_TOOL[name](k=v) and threads the result' do
    responses = [
      { content: "Reasoning... USE_TOOL[echo](msg=hi)\nDone", usage: {}, finish_reason: :stop, model: "m", provider: :test, tool_calls: [] }
    ]
    llm = double("LLM").tap { |l| allow(l).to receive(:chat) { responses.shift } }

    runner = described_class.new(agent: agent, llm: llm, tools: [tool])
    result = runner.run(messages: [{ role: "user", content: "x" }])

    expect(result[:content]).to include("Done")
    expect(result[:tool_calls_history].first[:tool]).to eq("echo")
  end
end
```

Re-define `FakeTool` here if not shared via `spec/support/`.

- [ ] **Step 7.7: Run spec; expect pass**

Run: `bundle exec rspec spec/legacy_react_runner_spec.rb`
Expected: all green.

- [ ] **Step 7.8: Add requires in `lib/rcrewai.rb`**

Add after `require_relative 'rcrewai/pricing'`:

```ruby
require_relative 'rcrewai/tool_runner'
require_relative 'rcrewai/legacy_react_runner'
```

- [ ] **Step 7.9: Commit**

```bash
git add lib/rcrewai/tool_runner.rb lib/rcrewai/legacy_react_runner.rb \
        lib/rcrewai.rb spec/tool_runner_spec.rb spec/legacy_react_runner_spec.rb
git commit -m "feat(runner): add ToolRunner and extract LegacyReactRunner"
```

---

## Task 8: Agent refactor + Crew streaming pass-through

**Files:**
- Modify: `lib/rcrewai/agent.rb`
- Modify: `lib/rcrewai/crew.rb`
- Create: `spec/agent_streaming_spec.rb`
- Modify: `spec/agent_spec.rb` (add cases for tool_calls_history and stream pass-through)

- [ ] **Step 8.1: Refactor `Agent#execute_task`**

Modify `lib/rcrewai/agent.rb`. Replace the body of `execute_task` so that, instead of building a giant prompt and regex-scanning, it picks a runner:

```ruby
def execute_task(task, stream: nil, **opts)
  llm = @llm_client
  initial_messages = build_initial_messages(task)
  sink = stream || ->(_) {}

  mode = if llm.supports_native_tools?(model: @llm_client.config.model) && @tools.all? { |t| t.json_schema }
           :native_tools
         else
           :react_legacy
         end
  @logger.info "[rcrewai] agent=#{name} mode=#{mode} provider=#{llm.config.llm_provider}"

  runner_class = mode == :native_tools ? ToolRunner : LegacyReactRunner
  runner = runner_class.new(agent: self, llm: llm, tools: @tools,
                            max_iterations: opts.fetch(:max_iterations, 10),
                            event_sink: sink)

  result = runner.run(messages: initial_messages)
  # Preserve existing return-shape; add tool_calls_history
  build_task_result(task, result)
end

def require_approval_for_tools?
  @require_approval_for_tools && @human_input_enabled
end

private

def build_initial_messages(task)
  # Build [{ role: "system", content: ... }, { role: "user", content: task.description }]
  # The system prompt should include role, goal, backstory, and (for native mode) NO USE_TOOL
  # instructions. LegacyReactRunner injects its own USE_TOOL prompt section as today.
  system = <<~SYS
    You are #{role}. Goal: #{goal}. #{backstory}
    You may call tools by name when needed.
  SYS
  [{ role: "system", content: system }, { role: "user", content: task.description }]
end

def build_task_result(task, runner_result)
  # Match the historical return-shape of execute_task. Add :tool_calls_history.
  {
    task: task.name,
    agent: name,
    content: runner_result[:content],
    tool_calls_history: runner_result[:tool_calls_history],
    usage: runner_result[:usage],
    iterations: runner_result[:iterations],
    finish_reason: runner_result[:finish_reason]
  }
end
```

Keep `use_tool`, `available_tools_description`, human-approval helpers, and delegation methods exactly as they are. Delete only the prompt-building and `USE_TOOL[]` parsing methods that are now duplicated in `LegacyReactRunner`. (Audit: any method that LegacyReactRunner calls on `@agent` must remain.)

- [ ] **Step 8.2: Add streaming to Crew**

Modify `lib/rcrewai/crew.rb`. In `def execute(...)`:

```ruby
def execute(stream: nil, async: false, max_concurrency: 1, timeout: nil, &block)
  sinks = []
  sinks << block if block_given?
  sinks << stream if stream && stream != true
  sinks.concat(Array(stream)) if stream.is_a?(Array)
  fan = sinks.empty? ? nil : Events.fan_out(sinks.flatten)

  # ... existing logic, but each task execution passes stream: fan ...
  # e.g. agent.execute_task(task, stream: fan)
end
```

Existing callers that don't pass `stream:` are unaffected (fan is `nil`).

- [ ] **Step 8.3: Write streaming spec**

Create `spec/agent_streaming_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe "Agent streaming pass-through" do
  it 'forwards events from runner to user sink' do
    # Stub LLM to return a single text-only response
    fake_llm = double("LLM")
    allow(fake_llm).to receive(:supports_native_tools?).and_return(true)
    allow(fake_llm).to receive(:config).and_return(RCrewAI.configuration)
    allow(fake_llm).to receive(:chat) do |**kwargs|
      kwargs[:stream]&.call(RCrewAI::Events::TextDelta.new(
        type: :text_delta, timestamp: Time.now, agent: nil, iteration: nil, text: "hi"))
      { content: "hi", tool_calls: [], usage: {}, finish_reason: :stop, model: "m", provider: :openai }
    end

    agent = RCrewAI::Agent.new(name: "a", role: "r", goal: "g", tools: [])
    agent.instance_variable_set(:@llm_client, fake_llm)

    task = RCrewAI::Task.new(name: "t", description: "say hi", agent: agent, expected_output: "x")

    received = []
    agent.execute_task(task, stream: ->(e) { received << e })

    text_events = received.select { |e| e.is_a?(RCrewAI::Events::TextDelta) }
    expect(text_events.map(&:text)).to include("hi")
    expect(text_events.first.agent).to eq("a")
  end
end
```

- [ ] **Step 8.4: Run new + existing specs; fix regressions**

Run: `bundle exec rspec`
Expected: all green. Existing `agent_spec.rb` tests that asserted exact `USE_TOOL[]` prompt strings need updating to use a stubbed LLM that returns either `:tool_calls` (native) or the legacy text format.

- [ ] **Step 8.5: Commit**

```bash
git add lib/rcrewai/agent.rb lib/rcrewai/crew.rb \
        spec/agent_streaming_spec.rb spec/agent_spec.rb
git commit -m "feat(agent): delegate to ToolRunner/LegacyReactRunner; add stream: pass-through"
```

---

## Task 9: Anthropic native tools + streaming + caching hook

**Files:**
- Modify: `lib/rcrewai/llm_clients/anthropic.rb`
- Create: `spec/llm_clients/anthropic_spec.rb`
- Create: `spec/fixtures/llm_responses/anthropic/tool_call.json`
- Create: `spec/fixtures/llm_responses/anthropic/stream_tool_call.sse`

Anthropic differences vs. OpenAI:
- Tools live at `tools:` top-level (not wrapped in `{type: "function", function: ...}`).
- Tool schema field is `input_schema`, not `parameters`.
- Stream events use `content_block_delta` with `delta.type = "text_delta"` or `"input_json_delta"`.
- Tool calls arrive as `content` blocks with `type: "tool_use"`.

- [ ] **Step 9.1: Capture fixture: non-streamed tool call**

Create `spec/fixtures/llm_responses/anthropic/tool_call.json`:

```json
{
  "id": "msg_1",
  "model": "claude-sonnet-4-6",
  "role": "assistant",
  "content": [
    { "type": "tool_use", "id": "toolu_1", "name": "web_search", "input": { "query": "ruby" } }
  ],
  "stop_reason": "tool_use",
  "usage": { "input_tokens": 50, "output_tokens": 10 }
}
```

- [ ] **Step 9.2: Capture fixture: streamed tool call**

Create `spec/fixtures/llm_responses/anthropic/stream_tool_call.sse`:

```
event: message_start
data: {"type":"message_start","message":{"id":"m","model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":40,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"web_search","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"ruby\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":12}}

event: message_stop
data: {"type":"message_stop"}

```

- [ ] **Step 9.3: Write failing spec**

Create `spec/llm_clients/anthropic_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'
require 'webmock/rspec'

RSpec.describe RCrewAI::LLMClients::Anthropic do
  let(:config) do
    RCrewAI.configuration.tap do |c|
      c.llm_provider = :anthropic
      c.anthropic_api_key = "k"
      c.anthropic_model = "claude-sonnet-4-6"
    end
  end
  let(:client) { described_class.new(config) }

  it 'sends tools at top level with input_schema and parses tool_use blocks' do
    tool_schema = {
      name: "web_search", description: "Search",
      parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
    }

    stub = stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(body: hash_including(
        "model" => "claude-sonnet-4-6",
        "tools" => [{ "name" => "web_search", "description" => "Search",
                      "input_schema" => { "type" => "object",
                                          "properties" => { "query" => { "type" => "string" } },
                                          "required" => ["query"] } }]
      ))
      .to_return(status: 200, body: File.read("spec/fixtures/llm_responses/anthropic/tool_call.json"),
                 headers: { "Content-Type" => "application/json" })

    result = client.chat(messages: [{ role: "user", content: "hi" }], tools: [tool_schema])

    expect(stub).to have_been_requested
    expect(result[:tool_calls]).to eq([{ id: "toolu_1", name: "web_search", arguments: { "query" => "ruby" } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
    expect(result[:usage]).to eq(prompt_tokens: 50, completion_tokens: 10, total_tokens: 60)
  end

  it 'assembles streamed input_json_delta into a tool_call' do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200,
                 body: File.read("spec/fixtures/llm_responses/anthropic/stream_tool_call.sse"),
                 headers: { "Content-Type" => "text/event-stream" })

    events = []
    result = client.chat(
      messages: [{ role: "user", content: "x" }],
      tools: [{ name: "web_search", description: "x",
                parameters: { type: "object", properties: {}, required: [] } }],
      stream: ->(e) { events << e }
    )

    expect(result[:tool_calls]).to eq([{ id: "toolu_1", name: "web_search", arguments: { "query" => "ruby" } }])
    expect(result[:finish_reason]).to eq(:tool_calls)
  end

  it 'attaches cache_control to large system blocks when cache_system: true' do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(body: hash_including(
        "system" => [hash_including("cache_control" => { "type" => "ephemeral" })]
      ))
      .to_return(status: 200, body: '{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}',
                 headers: { "Content-Type" => "application/json" })

    client.chat(messages: [{ role: "system", content: "BIG SYSTEM" * 200 },
                           { role: "user",   content: "hi" }],
                cache_system: true)
  end
end
```

- [ ] **Step 9.4: Rewrite `lib/rcrewai/llm_clients/anthropic.rb`**

Implement following the OpenAI shape but with Anthropic mapping. Key points:

```ruby
# In chat(...):
#  - Extract system message; if cache_system: true, wrap as
#      [{ "type" => "text", "text" => sys, "cache_control" => { "type" => "ephemeral" } }]
#  - tools: ProviderSchema.for_many(:anthropic, tools) if tools
#  - For streaming: parse named SSE events ("content_block_start",
#    "content_block_delta", "message_delta", "message_stop"); accumulate
#    text deltas into assembled_text and input_json_delta into the right
#    tool_use block (index → tool_call slot).
#  - normalize_non_streaming walks response["content"] and picks out
#    `tool_use` blocks → tool_calls, `text` blocks → content.
#  - finish_reason mapping: "tool_use" → :tool_calls, "end_turn" → :stop, "max_tokens" → :length
```

Reuse the existing `validate_config!` and headers (x-api-key, anthropic-version). Use `RCrewAI::SSEParser` for stream parsing. Emit `Events::TextDelta` from `text_delta` deltas; emit `Events::Usage` from `message_delta.usage`.

The full reference shape — model on the same skeleton as OpenAI in Task 6.6 with the differences above.

- [ ] **Step 9.5: Run spec; expect pass**

Run: `bundle exec rspec spec/llm_clients/anthropic_spec.rb`
Expected: all green.

- [ ] **Step 9.6: Commit**

```bash
git add lib/rcrewai/llm_clients/anthropic.rb spec/llm_clients/anthropic_spec.rb \
        spec/fixtures/llm_responses/anthropic/
git commit -m "feat(anthropic): native tools, streaming, and prompt-caching hook"
```

---

## Task 10: Google + Azure + Ollama native tools + streaming

**Files:**
- Modify: `lib/rcrewai/llm_clients/google.rb`
- Modify: `lib/rcrewai/llm_clients/azure.rb`
- Modify: `lib/rcrewai/llm_clients/ollama.rb`
- Create: `spec/llm_clients/google_spec.rb`
- Create: `spec/llm_clients/azure_spec.rb`
- Create: `spec/llm_clients/ollama_spec.rb`
- Create: `spec/fixtures/llm_responses/google/tool_call.json`
- Create: `spec/fixtures/llm_responses/google/stream.sse`
- Create: `spec/fixtures/llm_responses/ollama/tool_call.json`

This task is repeated three times (one provider at a time). Each follows the same pattern as Tasks 6 and 9: capture fixture → write failing spec → implement → run.

### Google (Gemini)

- [ ] **Step 10.1: Implement Google client following the per-provider shape**

Gemini specifics:
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key=API_KEY` (non-streaming) or `:streamGenerateContent?alt=sse&key=API_KEY` (streaming).
- Tools: top-level `tools: [{ function_declarations: [...] }]` (use `ProviderSchema.for_many(:google, tools)` which already returns this shape from one list).
- Tool calls arrive as `candidates[].content.parts[].functionCall`.
- Usage: `usageMetadata.{promptTokenCount,candidatesTokenCount,totalTokenCount}`.
- Finish reason: `STOP` → `:stop`, `MAX_TOKENS` → `:length`, `FUNCTION_CALL`/`TOOL_USE` → `:tool_calls`.

- [ ] **Step 10.2: Capture fixture + write spec mirroring OpenAI shape; run; pass; commit**

```bash
git add lib/rcrewai/llm_clients/google.rb spec/llm_clients/google_spec.rb \
        spec/fixtures/llm_responses/google/
git commit -m "feat(google): native tools and streaming"
```

### Azure

- [ ] **Step 10.3: Implement Azure client**

Azure uses the OpenAI wire format with a different base URL and auth header. Strategy: have `Azure` subclass `OpenAI` and override only:
- `BASE_URL` → built from `config.azure_endpoint` + `/openai/deployments/#{deployment}/chat/completions?api-version=#{config.api_version}`
- `auth_header` → `{ 'api-key' => config.azure_api_key }`
- `validate_config!` → require `azure_api_key`, `azure_endpoint`, `deployment_name`, `api_version`

Add a smoke-test spec asserting the URL is constructed correctly and `auth_header` uses `api-key`.

- [ ] **Step 10.4: Spec, run, commit**

```bash
git add lib/rcrewai/llm_clients/azure.rb spec/llm_clients/azure_spec.rb
git commit -m "feat(azure): inherit OpenAI native tools and streaming"
```

### Ollama

- [ ] **Step 10.5: Implement Ollama client**

Ollama specifics:
- `POST http://host:port/api/chat` — body `{ model, messages, tools, stream: bool }`.
- Non-streaming returns one JSON document with `message.content` and `message.tool_calls`.
- Streaming is **line-delimited JSON** (not SSE) — feed lines through a plain JSON-per-line parser, not the SSEParser.
- Tools shape matches OpenAI (`{type:"function", function:{...}}`).
- Native-tools allowlist for `supports_native_tools?`:

```ruby
NATIVE_TOOL_MODELS = %w[
  llama3.1 llama3.1:8b llama3.1:70b llama3.1:405b
  llama3.2 llama3.2:1b llama3.2:3b
  qwen2.5 qwen2.5:7b qwen2.5:14b qwen2.5:32b qwen2.5:72b
  mistral-nemo mistral-large
  command-r command-r-plus
  firefunction-v2
].freeze

def supports_native_tools?(model: config.model)
  return RCrewAI.configuration.ollama_native_tools unless RCrewAI.configuration.ollama_native_tools.nil?
  base = model.to_s.split(":").first
  NATIVE_TOOL_MODELS.any? { |m| m == model || m.split(":").first == base }
end
```

- [ ] **Step 10.6: Spec — assert allowlist + ReAct fallback selection; run; commit**

```bash
git add lib/rcrewai/llm_clients/ollama.rb spec/llm_clients/ollama_spec.rb \
        spec/fixtures/llm_responses/ollama/
git commit -m "feat(ollama): native tools (allowlist) and streaming"
```

- [ ] **Step 10.7: Phase 2 checkpoint**

Run: `bundle exec rspec`
Expected: all green.

Run all three examples to confirm no end-to-end regressions:

```bash
ruby examples/async_execution_example.rb 2>&1 | head -30
ruby examples/human_in_the_loop_example.rb 2>&1 | head -30
ruby examples/hierarchical_crew_example.rb 2>&1 | head -30
```

Tag:

```bash
git tag phase-2-providers
```

Phase 2 complete. The gem could now ship as `0.3.0-rc1` with native tools and streaming everywhere. MCP comes next.

---

# Phase 3 — MCP client + docs + release

## Task 11: MCP client + transports + ToolAdapter

**Files:**
- Create: `lib/rcrewai/mcp.rb`
- Create: `lib/rcrewai/mcp/client.rb`
- Create: `lib/rcrewai/mcp/transport/stdio.rb`
- Create: `lib/rcrewai/mcp/transport/http.rb`
- Create: `lib/rcrewai/mcp/tool_adapter.rb`
- Create: `spec/mcp/client_spec.rb`
- Create: `spec/mcp/transport/stdio_spec.rb`
- Create: `spec/mcp/transport/http_spec.rb`
- Create: `spec/mcp/tool_adapter_spec.rb`
- Create: `spec/fixtures/mcp_servers/echo_server.rb`
- Modify: `lib/rcrewai.rb` (autoload MCP module)

- [ ] **Step 11.1: Write the fixture MCP server**

Create `spec/fixtures/mcp_servers/echo_server.rb`:

```ruby
#!/usr/bin/env ruby
# Minimal stdio MCP server: implements initialize, tools/list, tools/call (for one tool: echo).
require 'json'

$stdout.sync = true

loop do
  line = $stdin.gets
  break if line.nil?
  req = JSON.parse(line)
  id = req["id"]

  case req["method"]
  when "initialize"
    puts({ jsonrpc: "2.0", id: id, result: {
      protocolVersion: "2024-11-05",
      capabilities: { tools: {} },
      serverInfo: { name: "echo-server", version: "0.1" }
    }}.to_json)
  when "tools/list"
    puts({ jsonrpc: "2.0", id: id, result: {
      tools: [{
        name: "echo",
        description: "Echoes its input",
        inputSchema: { type: "object", properties: { message: { type: "string" } }, required: ["message"] }
      }]
    }}.to_json)
  when "tools/call"
    msg = req.dig("params", "arguments", "message")
    puts({ jsonrpc: "2.0", id: id, result: {
      content: [{ type: "text", text: "echo: #{msg}" }]
    }}.to_json)
  when "notifications/initialized"
    # no response for notifications
  else
    puts({ jsonrpc: "2.0", id: id, error: { code: -32601, message: "method not found" } }.to_json)
  end
end
```

Make it executable: `chmod +x spec/fixtures/mcp_servers/echo_server.rb`.

- [ ] **Step 11.2: Write failing client spec**

Create `spec/mcp/client_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::MCP::Client do
  let(:server_path) { File.expand_path("../fixtures/mcp_servers/echo_server.rb", __dir__) }

  it 'handshakes, lists tools, and calls a tool' do
    client = described_class.connect(command: "ruby", args: [server_path])
    expect(client.server_name).to eq("echo-server")
    expect(client.tools.map(&:name)).to eq(["echo-server__echo"])

    tool = client.tools.first
    result = tool.execute(message: "hello")
    expect(result).to include("echo: hello")
  ensure
    client&.close
  end

  it 'with_connection auto-closes on block exit' do
    described_class.with_connection(command: "ruby", args: [server_path]) do |client|
      expect(client.tools).not_to be_empty
    end
  end

  it 'translates MCP inputSchema to canonical JSON schema for tool adapters' do
    described_class.with_connection(command: "ruby", args: [server_path]) do |client|
      schema = client.tools.first.json_schema
      expect(schema[:name]).to eq("echo-server__echo")
      expect(schema[:parameters]).to include(
        type: "object",
        properties: { "message" => { "type" => "string" } },
        required: ["message"]
      )
    end
  end
end
```

- [ ] **Step 11.3: Implement `lib/rcrewai/mcp/transport/stdio.rb`**

```ruby
# frozen_string_literal: true

require 'json'

module RCrewAI
  module MCP
    module Transport
      class Stdio
        def initialize(command:, args: [], env: {})
          @command = command
          @args = args
          @env = env
          @stdin = nil
          @stdout = nil
          @pid = nil
        end

        def open
          @stdin, @stdout, _stderr_thread, wait_thr = open_pipes
          @pid = wait_thr.pid
          ObjectSpace.define_finalizer(self, self.class.finalize(@pid))
        end

        def send_line(json)
          @stdin.write(json + "\n")
          @stdin.flush
        end

        def recv_line
          @stdout.gets
        end

        def close
          return unless @pid
          Process.kill("TERM", @pid) rescue nil
          @stdin&.close rescue nil
          @stdout&.close rescue nil
          @pid = nil
        end

        def self.finalize(pid)
          proc { Process.kill("KILL", pid) rescue nil }
        end

        private

        def open_pipes
          require 'open3'
          stdin, stdout, stderr, wait_thr = Open3.popen3(@env, @command, *@args)
          stderr_thread = Thread.new { stderr.each_line { |l| Kernel.warn "[mcp-stderr] #{l}" } }
          [stdin, stdout, stderr_thread, wait_thr]
        end
      end
    end
  end
end
```

- [ ] **Step 11.4: Implement `lib/rcrewai/mcp/transport/http.rb`**

```ruby
# frozen_string_literal: true

require 'faraday'
require_relative '../../sse_parser'

module RCrewAI
  module MCP
    module Transport
      class Http
        def initialize(url:, headers: {})
          @url = url
          @headers = headers
          @queue = Queue.new
          @sse_thread = nil
        end

        def open
          @http = Faraday.new(url: @url) do |f|
            f.adapter Faraday.default_adapter
          end
          @sse_thread = Thread.new { start_sse_stream }
        end

        def send_line(json)
          @http.post("") do |req|
            req.headers.merge!(@headers).merge!("Content-Type" => "application/json")
            req.body = json
          end
        end

        def recv_line
          @queue.pop
        end

        def close
          @sse_thread&.kill
          @queue.close if @queue.respond_to?(:close)
        end

        private

        def start_sse_stream
          parser = SSEParser.new do |evt|
            @queue << evt[:data] + "\n" if evt[:event] == "message" || evt[:event].nil?
          end
          @http.get("") do |req|
            req.headers.merge!(@headers).merge!("Accept" => "text/event-stream")
            req.options.on_data = proc { |chunk, _| parser.feed(chunk) }
          end
        end
      end
    end
  end
end
```

- [ ] **Step 11.5: Implement `lib/rcrewai/mcp/client.rb`**

```ruby
# frozen_string_literal: true

require 'json'
require_relative 'transport/stdio'
require_relative 'transport/http'
require_relative 'tool_adapter'

module RCrewAI
  module MCP
    class Error < RCrewAI::Error; end

    class Client
      attr_reader :server_name, :tools

      def self.connect(**opts)
        new(**opts).tap(&:open)
      end

      def self.with_connection(**opts)
        c = connect(**opts)
        yield c
      ensure
        c&.close
      end

      def initialize(command: nil, args: [], env: {}, url: nil, headers: {})
        @transport = if url
                       Transport::Http.new(url: url, headers: headers)
                     else
                       Transport::Stdio.new(command: command, args: args, env: env)
                     end
        @request_id = 0
        @tools = []
        @server_name = nil
      end

      def open
        @transport.open
        handshake
        load_tools
      end

      def close
        @transport.close
      end

      def call_tool(name, args)
        result = request("tools/call", { name: strip_prefix(name), arguments: args })
        result.dig("content", 0, "text") || result["content"]
      end

      private

      def handshake
        info = request("initialize", {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          clientInfo: { name: "rcrewai", version: RCrewAI::VERSION }
        })
        @server_name = info.dig("serverInfo", "name") || "mcp"
        notify("notifications/initialized", {})
      end

      def load_tools
        result = request("tools/list", {})
        @tools = Array(result["tools"]).map { |t| ToolAdapter.new(self, t, @server_name) }
      end

      def request(method, params)
        @request_id += 1
        msg = { jsonrpc: "2.0", id: @request_id, method: method, params: params }
        @transport.send_line(msg.to_json)
        reply = JSON.parse(@transport.recv_line)
        raise Error, reply["error"]["message"] if reply["error"]
        reply["result"]
      end

      def notify(method, params)
        msg = { jsonrpc: "2.0", method: method, params: params }
        @transport.send_line(msg.to_json)
      end

      def strip_prefix(prefixed_name)
        prefixed_name.sub(/^#{Regexp.escape(@server_name)}__/, "")
      end
    end
  end
end
```

- [ ] **Step 11.6: Implement `lib/rcrewai/mcp/tool_adapter.rb`**

```ruby
# frozen_string_literal: true

require_relative '../tools/base'

module RCrewAI
  module MCP
    class ToolAdapter < RCrewAI::Tools::Base
      def initialize(client, mcp_tool_descriptor, server_name)
        @client = client
        @descriptor = mcp_tool_descriptor
        @server_name = server_name
        @name = "#{server_name}__#{mcp_tool_descriptor["name"]}"
        @description = mcp_tool_descriptor["description"].to_s
      end

      def name; @name; end
      def description; @description; end

      def json_schema
        {
          name: @name,
          description: @description,
          parameters: stringify_keys(@descriptor["inputSchema"] || { "type" => "object", "additionalProperties" => true })
        }
      end

      def execute(**args)
        @client.call_tool(@name, args)
      end

      def execute_with_validation(args_hash)
        execute(**args_hash.transform_keys(&:to_sym))
      end

      private

      def stringify_keys(h)
        return h unless h.is_a?(Hash)
        h.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify_keys(v) }
      end
    end
  end
end
```

- [ ] **Step 11.7: Implement `lib/rcrewai/mcp.rb` (module entry)**

```ruby
# frozen_string_literal: true

require_relative 'mcp/client'

module RCrewAI
  module MCP
  end
end
```

- [ ] **Step 11.8: Add require in `lib/rcrewai.rb`**

Add at end of `lib/rcrewai.rb`:

```ruby
require_relative 'rcrewai/mcp'
```

- [ ] **Step 11.9: Run client spec; expect pass**

Run: `bundle exec rspec spec/mcp/client_spec.rb`
Expected: all green.

- [ ] **Step 11.10: Write transport unit specs**

Create `spec/mcp/transport/stdio_spec.rb` — assert that `Stdio` spawns the subprocess, can round-trip a line, and kills the pid on `close`. Use the echo_server fixture or a one-liner ruby `-e 'puts gets'`.

Create `spec/mcp/transport/http_spec.rb` — use webmock to stub `GET` (SSE) + `POST` and assert round-trip behavior.

- [ ] **Step 11.11: Write end-to-end integration spec**

Create `spec/integration/mcp_end_to_end_spec.rb`:

```ruby
# frozen_string_literal: true
require 'spec_helper'

RSpec.describe "MCP end-to-end" do
  let(:server_path) { File.expand_path("../fixtures/mcp_servers/echo_server.rb", __dir__) }

  it 'lets an agent call an MCP tool via the ToolRunner' do
    RCrewAI::MCP::Client.with_connection(command: "ruby", args: [server_path]) do |client|
      # Stub the LLM to invoke the MCP echo tool then stop
      llm = double("LLM")
      allow(llm).to receive(:supports_native_tools?).and_return(true)
      allow(llm).to receive(:config).and_return(RCrewAI.configuration)
      sequence = [
        { content: nil, tool_calls: [{ id: "1", name: "echo-server__echo", arguments: { "message" => "hi" } }],
          usage: {}, finish_reason: :tool_calls, model: "m", provider: :openai },
        { content: "Done.", tool_calls: [], usage: {},
          finish_reason: :stop, model: "m", provider: :openai }
      ]
      allow(llm).to receive(:chat) { sequence.shift }

      agent = RCrewAI::Agent.new(name: "a", role: "r", goal: "g", tools: client.tools)
      agent.instance_variable_set(:@llm_client, llm)

      task = RCrewAI::Task.new(name: "t", description: "echo hi", agent: agent, expected_output: "x")
      result = agent.execute_task(task)

      expect(result[:content]).to eq("Done.")
      expect(result[:tool_calls_history].first[:result]).to include("echo: hi")
    end
  end
end
```

- [ ] **Step 11.12: Run full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 11.13: Commit**

```bash
git add lib/rcrewai/mcp* lib/rcrewai.rb spec/mcp spec/integration/mcp_end_to_end_spec.rb \
        spec/fixtures/mcp_servers/
git commit -m "feat(mcp): client + stdio/HTTP transports + ToolAdapter"
```

---

## Task 12: Docs, CHANGELOG, examples, version bump

**Files:**
- Modify: `lib/rcrewai/version.rb`
- Modify: `CHANGELOG.md`
- Create: `docs/upgrading-to-0.3.md`
- Create: `docs/mcp.md`
- Create: `examples/native_tools_example.rb`
- Create: `examples/streaming_example.rb`
- Create: `examples/mcp_example.rb`

- [ ] **Step 12.1: Bump version**

```ruby
# lib/rcrewai/version.rb
module RCrewAI
  VERSION = "0.3.0"
end
```

- [ ] **Step 12.2: Write CHANGELOG entry**

Prepend to `CHANGELOG.md`:

```markdown
## 0.3.0 — 2026-XX-XX

### Added
- Native function calling across all five providers (OpenAI, Anthropic, Google, Azure, Ollama). Tools declare a JSON schema via the new DSL (`tool_name`, `description`, `param`) on `Tools::Base`.
- Typed streaming event model (`RCrewAI::Events::*`) covering text deltas, tool-call lifecycle, usage, and errors. Pass `stream:` to `crew.execute` or `agent.execute_task`.
- MCP (Model Context Protocol) client. Connect to stdio or HTTP MCP servers and expose their tools as ordinary RCrewAI tools.
- Per-model price table and `cost_usd` on `Events::Usage` for cost tracking.
- `Tools::Base#execute_with_validation` coerces and validates args against the DSL schema.

### Changed
- `Agent#execute_task` now delegates to `ToolRunner` (native function calling) or `LegacyReactRunner` (existing `USE_TOOL[]` parsing, used as fallback for legacy Ollama models or tools without a DSL declaration).
- `Agent#execute_task` return value now includes `tool_calls_history:`.
- `LLMClients::Base#chat` gains `tools:`, `tool_choice:`, and `stream:` keyword arguments.

### Breaking
- Subclasses of `LLMClients::Base` that override `chat` with an explicit kwarg list must add `tools: nil, stream: nil` to the signature (or accept `**options`).
- Tools without DSL declarations now receive a permissive fallback schema and emit a one-time deprecation warning to stderr.

### Migration
- See `docs/upgrading-to-0.3.md` for step-by-step migration.
```

- [ ] **Step 12.3: Write `docs/upgrading-to-0.3.md`**

Content: full migration guide. Sections: "What you must do", "What you should do (recommended)", "What you can do (new capabilities)". Each section has before/after Ruby snippets:

- Custom tool migration (5-line DSL diff).
- Streaming adoption snippet.
- MCP adoption snippet.
- LLMClient subclass kwarg fix snippet.

- [ ] **Step 12.4: Write `docs/mcp.md`**

Content: what is MCP, why use it, how to connect (stdio + HTTP examples), how the MCP tool name prefix works, lifecycle (connect/close/with_connection), what's not supported in 0.3 (resources, prompts, server mode, OAuth).

- [ ] **Step 12.5: Write `examples/native_tools_example.rb`**

Full runnable example showing an agent with a DSL-declared tool, OpenAI provider, no streaming. Comment headers explain each section.

- [ ] **Step 12.6: Write `examples/streaming_example.rb`**

Full runnable example using `crew.execute(stream: ...)` with multiple sinks (one prints text, one tracks cost via `Events::Usage`).

- [ ] **Step 12.7: Write `examples/mcp_example.rb`**

Full runnable example using `RCrewAI::MCP::Client.with_connection` against a public MCP server (e.g., filesystem). Include the npm install/npx command in a comment.

- [ ] **Step 12.8: Run full suite + examples smoke check**

```bash
bundle exec rspec
ruby -Ilib -e "require 'rcrewai'; puts RCrewAI::VERSION"  # expects 0.3.0
```

- [ ] **Step 12.9: Commit**

```bash
git add lib/rcrewai/version.rb CHANGELOG.md \
        docs/upgrading-to-0.3.md docs/mcp.md \
        examples/native_tools_example.rb examples/streaming_example.rb examples/mcp_example.rb
git commit -m "chore(release): docs, examples, and version bump for 0.3.0"
```

- [ ] **Step 12.10: Phase 3 / release tag**

```bash
git tag v0.3.0
```

---

# Appendix — Cross-cutting concerns

## Test fixtures organization

```
spec/fixtures/
├── llm_responses/
│   ├── openai/{tool_call.json, stream_text.sse, stream_tool_call.sse}
│   ├── anthropic/{tool_call.json, stream_tool_call.sse}
│   ├── google/{tool_call.json, stream.sse}
│   └── ollama/{tool_call.json}
└── mcp_servers/echo_server.rb
```

## CI requirements (out of scope for this plan but called out)

- `.github/workflows/ci.yml` should run `bundle exec rspec` on Ruby 3.0–3.3 matrix.
- MCP integration test requires Ruby — already covered by the matrix.
- VCR cassettes for live-provider integration are recorded with `RECORD=true` and committed.

## What this plan does NOT change

- Async executor (`async_executor.rb`)
- Process types / hierarchical orchestration (`process.rb`)
- Memory (`memory.rb`)
- Human-in-the-loop core (`human_input.rb`) — only consumed
- CLI (`cli.rb`)

These are working today and out of scope. Touch only if a regression surfaces.
