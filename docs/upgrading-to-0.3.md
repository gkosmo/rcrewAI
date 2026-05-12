# Upgrading to RCrewAI 0.3

RCrewAI 0.3 modernizes the LLM layer with native function calling, typed
streaming, and an MCP client. Existing code continues to run, but you can
opt into the new capabilities incrementally.

This guide is split into three parts:

1. **What you must do** — required changes to keep your code working.
2. **What you should do** — recommended changes to take advantage of the
   new behavior.
3. **What you can do** — new capabilities you can adopt at your own pace.

---

## 1. What you must do

### 1a. Custom `LLMClients::Base` subclasses

If you have a custom LLM client that overrides `chat` with a fixed kwarg
list, add `tools:` and `stream:` (or accept `**options`).

**Before:**

```ruby
class MyClient < RCrewAI::LLMClients::Base
  def chat(messages:, temperature: 0.1)
    # ...
  end
end
```

**After:**

```ruby
class MyClient < RCrewAI::LLMClients::Base
  def chat(messages:, tools: nil, tool_choice: :auto, stream: nil, **options)
    # ...
  end

  def supports_native_tools?(model: config.model)
    false  # or true if your provider supports OpenAI-style function calls
  end
end
```

### 1b. Tools without DSL declarations now print a deprecation warning

Tools that don't declare a schema still work (with a permissive fallback
schema) but emit a one-time `[rcrewai] Tool ... has no DSL declarations`
warning on stderr. To clear the warning, declare a schema:

**Before:**

```ruby
class WeatherTool < RCrewAI::Tools::Base
  def initialize
    @name = "weather"
    @description = "Get the weather for a city"
  end

  def execute(city:)
    # ...
  end
end
```

**After:**

```ruby
class WeatherTool < RCrewAI::Tools::Base
  tool_name   "weather"
  description "Get the weather for a city"
  param :city, type: :string, required: true, description: "City name"

  def execute(city:)
    # ...
  end
end
```

---

## 2. What you should do

### 2a. Consume `Agent#execute_task` return as a hash

In 0.3, `execute_task` returns a hash with `:content`, `:tool_calls_history`,
`:usage`, `:iterations`, and `:finish_reason`. The agent still assigns
the plain string content to `task.result`, so old code that reads
`task.result` continues to work.

**Before:**

```ruby
result_string = agent.execute_task(task)
puts result_string
```

**After:**

```ruby
result = agent.execute_task(task)
puts result[:content]
puts "tokens: #{result.dig(:usage, :total_tokens)}"
puts "tool calls: #{result[:tool_calls_history].length}"
```

---

## 3. What you can do (new capabilities)

### 3a. Native function calling

When a tool has a DSL-declared schema and your LLM supports native function
calls, the agent automatically uses the new `ToolRunner` path — no more
`USE_TOOL[name](k=v)` prompt parsing. There's nothing to opt into beyond
declaring the schema (see 1b).

### 3b. Streaming events

Pass a `stream:` lambda to `agent.execute_task` or `crew.execute`. You'll
receive typed events as the LLM produces output:

```ruby
events = []
agent.execute_task(task, stream: ->(e) { events << e })

text = events
  .select { |e| e.is_a?(RCrewAI::Events::TextDelta) }
  .map(&:text).join
```

Event types: `TextDelta`, `ToolCallStart`, `ToolCallResult`, `ToolCallError`,
`Usage` (with `cost_usd`), `IterationStart`, `IterationEnd`, `Error`.

### 3c. Cost tracking

When `Pricing` knows your model, `Events::Usage` carries `cost_usd`:

```ruby
total_cost = 0.0
crew.execute(stream: ->(e) {
  total_cost += e.cost_usd if e.is_a?(RCrewAI::Events::Usage) && e.cost_usd
})
```

Override the table via `RCrewAI.configuration.pricing = { "my-model" => { input: 1.0, output: 5.0 } }`.

### 3d. MCP servers as agent tools

Connect to an MCP server (stdio or HTTP) and pass its tools to your agent:

```ruby
RCrewAI::MCP::Client.with_connection(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]) do |client|
  agent = RCrewAI::Agent.new(name: "fs", role: "...", goal: "...", tools: client.tools)
  task = RCrewAI::Task.new(name: "ls", description: "list /tmp", agent: agent)
  result = agent.execute_task(task)
  puts result[:content]
end
```

See `docs/mcp.md` for the full guide.
