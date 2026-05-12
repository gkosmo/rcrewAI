# MCP (Model Context Protocol) Support

RCrewAI 0.3 ships a minimal MCP client that lets your agents call tools
hosted by any MCP server — local processes (stdio) or remote services
(streamable HTTP) — without any custom adapter code.

## What is MCP?

[MCP](https://modelcontextprotocol.io) is an open protocol for connecting
language models to tools and data sources. Servers expose tools via a
JSON-RPC schema; clients (like RCrewAI) connect, discover the tools, and
invoke them on the model's behalf.

The big win: any of the dozens of off-the-shelf MCP servers — filesystem,
git, Slack, Postgres, browser automation, custom internal tools — works
with RCrewAI without writing a single line of glue.

## Connecting

### Stdio (local subprocess)

```ruby
require 'rcrewai'

RCrewAI::MCP::Client.with_connection(
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
) do |client|
  puts "connected to #{client.server_name}"
  client.tools.each { |t| puts " - #{t.name}: #{t.description}" }
end
```

### Streamable HTTP (remote)

```ruby
RCrewAI::MCP::Client.with_connection(
  url: "https://mcp.example.com/v1",
  headers: { "Authorization" => "Bearer #{ENV['MCP_TOKEN']}" }
) do |client|
  # ...
end
```

### Manual lifecycle

`with_connection` is the recommended form (auto-closes on block exit), but
you can also drive the lifecycle manually:

```ruby
client = RCrewAI::MCP::Client.connect(command: "ruby", args: ["my_server.rb"])
# ... use client.tools ...
client.close
```

## Tool name prefix

To prevent collisions when an agent uses tools from multiple MCP servers,
tool names are prefixed with the server name:

```
echo-server__echo
filesystem__read_file
filesystem__write_file
git__commit
```

The prefix is `#{server_name}__#{tool_name}`, where `server_name` comes
from the server's own `serverInfo.name`.

## Using MCP tools with an agent

MCP tools are ordinary `RCrewAI::Tools::Base` instances — pass them to
`Agent.new(tools: ...)` like any other tool:

```ruby
RCrewAI::MCP::Client.with_connection(command: "npx", args: [...]) do |client|
  agent = RCrewAI::Agent.new(
    name: "fs_agent",
    role: "Filesystem operator",
    goal: "Read and summarize files",
    tools: client.tools
  )

  task = RCrewAI::Task.new(name: "summarize",
                           description: "Read /tmp/notes.md and summarize",
                           agent: agent)
  result = agent.execute_task(task)
  puts result[:content]
end
```

When `ToolRunner` (the new native-function-calling loop) is selected, the
LLM picks an MCP tool by name, RCrewAI dispatches the call to the MCP
server, threads the result back into the conversation, and continues.

## What's not (yet) supported in 0.3

The 0.3 client is intentionally minimal — it covers `initialize`,
`tools/list`, `tools/call`, and the `notifications/initialized` handshake.
The following are not implemented:

- **Resources** (`resources/list`, `resources/read`)
- **Prompts** (`prompts/list`, `prompts/get`)
- **Server mode** — RCrewAI can be an MCP client, not yet an MCP server
- **OAuth** authentication for HTTP transports
- **Notifications other than `initialized`** (e.g., progress, log)

These will land in follow-up releases as the MCP spec stabilizes.
