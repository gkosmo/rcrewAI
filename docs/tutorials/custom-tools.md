---
layout: tutorial
title: Custom Tools Development
description: Build custom tools with the tool DSL, so agents can call your code through native function calling
---

# Custom Tools Development

A tool is a Ruby class the model can call. You declare its name, description, and
parameters, and write `execute`. RCrewAI turns the declaration into a JSON schema
for the provider, coerces the model's arguments to the declared types, and sends
the return value back to the model.

## Table of Contents
1. [Your First Tool](#your-first-tool)
2. [Declaring Parameters](#declaring-parameters)
3. [Configuring a Tool](#configuring-a-tool)
4. [Calling an API](#calling-an-api)
5. [Errors](#errors)
6. [Thread Safety](#thread-safety)
7. [Security](#security)
8. [Testing Tools](#testing-tools)
9. [Tools Without the DSL](#tools-without-the-dsl)
10. [Best Practices](#best-practices)

## Your First Tool

```ruby
require 'rcrewai'

class WordCount < RCrewAI::Tools::Base
  tool_name   'word_count'
  description 'Count the words in a piece of text'
  param :text, type: :string, required: true, description: 'The text to count'

  def execute(text:)
    text.split.length.to_s
  end
end

agent = RCrewAI::Agent.new(
  name: 'editor',
  role: 'Editor',
  goal: 'Keep articles within their word limits',
  tools: [WordCount.new]
)
```

Three things matter here:

- **The description is for the model.** It decides whether the tool gets called, so
  say what the tool does and when to use it.
- **`execute` receives keyword arguments**, one for each declared parameter.
- **Return a string.** Other values are converted with `to_s` before the model sees them.

You can call a tool directly to try it:

```ruby
WordCount.new.execute(text: 'one two three')  # => "3"
WordCount.json_schema
# => { name: "word_count", description: "Count the words in a piece of text",
#      parameters: { type: "object", properties: { text: { ... } }, required: ["text"] } }
```

## Declaring Parameters

```ruby
class SearchOrders < RCrewAI::Tools::Base
  tool_name   'search_orders'
  description 'Search customer orders'

  param :query,  type: :string,  required: true, description: 'Customer name or order number'
  param :limit,  type: :integer, default: 10,    description: 'Maximum results to return'
  param :status, type: :enum,    values: %w[open shipped cancelled]
  param :tags,   type: :array,   items: { type: :string }
  param :open_only, type: :boolean
  param :filters, type: :object, properties: { min_total: { type: 'number' } }

  def execute(query:, limit: 10, status: nil, tags: [], open_only: false, filters: {})
    "Found 0 orders for #{query} (limit #{limit}, status #{status.inspect})"
  end
end
```

The supported types are `:string`, `:integer`, `:number`, `:boolean`, `:array`,
`:object`, and `:enum`.

**`default:` only informs the model.** It appears in the schema, but RCrewAI doesn't
fill it in when the model leaves the argument out, so also give the keyword a default
in `execute`, as `limit: 10` does above. Every parameter that isn't `required: true`
needs one.

Arguments are coerced before `execute` runs, so `"5"` becomes `5` for an `:integer`.
A value that can't be coerced, or a missing required parameter, raises
`RCrewAI::Tools::ToolError`.

The tool name defaults to the class name in snake case, so `tool_name` is optional
for `SearchOrders`.

## Configuring a Tool

Put setup such as credentials and limits in `initialize`, not in parameters the
model can see. Call `super()` with empty parentheses, because the base class takes
no arguments:

```ruby
class InvoiceLookup < RCrewAI::Tools::Base
  tool_name   'invoice_lookup'
  description 'Look up an invoice by its number'
  param :number, type: :string, required: true

  def initialize(client:, max_age_days: 90)
    super()
    @client = client
    @max_age_days = max_age_days
  end

  def execute(number:)
    @client.find_invoice(number, max_age_days: @max_age_days).to_s
  end
end
```

## Calling an API

Tools can use any HTTP client. Faraday is already a dependency of the gem:

```ruby
require 'faraday'
require 'json'

class Weather < RCrewAI::Tools::Base
  tool_name   'weather'
  description 'Get the current weather for a city'
  param :city, type: :string, required: true, description: 'City name, e.g. "Brussels"'

  def initialize(api_key:, base_url: 'https://api.openweathermap.org')
    super()
    @http = Faraday.new(url: base_url, request: { timeout: 10 })
    @api_key = api_key
  end

  def execute(city:)
    response = @http.get('/data/2.5/weather', { q: city, appid: @api_key, units: 'metric' })
    raise RCrewAI::Tools::ToolError, "Weather API returned #{response.status}" unless response.success?

    data = JSON.parse(response.body)
    "#{data['name']}: #{data.dig('main', 'temp')}°C, #{data.dig('weather', 0, 'description')}"
  end
end
```

To use tools that someone else already hosts, connect to an MCP server instead of
writing a wrapper. See the [MCP guide]({{ site.baseurl }}/mcp).

## Errors

Raise an error when a tool can't do its job. Under native function calling, the
exception doesn't fail the task: the model receives `ERROR: <message>` as the tool's
result and can correct itself. Write messages it can act on:

```ruby
class ReadReport < RCrewAI::Tools::Base
  tool_name   'read_report'
  description 'Read a report by its id'
  param :id, type: :string, required: true

  REPORTS = { 'q1' => 'Revenue grew 4%.' }.freeze

  def execute(id:)
    REPORTS.fetch(id) do
      raise RCrewAI::Tools::ToolError, "No report '#{id}'. Available: #{REPORTS.keys.join(', ')}"
    end
  end
end
```

## Thread Safety

When a model requests several tools in one turn, they run concurrently on the same
tool instances. A tool with mutable state must protect it:

```ruby
class Counter < RCrewAI::Tools::Base
  tool_name   'counter'
  description 'Increment a shared counter and return its value'
  param :by, type: :integer, required: true

  def initialize
    super
    @count = 0
    @lock = Mutex.new
  end

  def execute(by:)
    @lock.synchronize { @count += by }.to_s
  end
end
```

If that isn't practical, set `parallel_tools: false` on the agent using the tool.

## Security

Treat tool arguments as untrusted input. They come from the model, and the model's
input may include content from web pages, documents, or users.

```ruby
class ReadDoc < RCrewAI::Tools::Base
  tool_name   'read_doc'
  description 'Read a document from the docs folder'
  param :path, type: :string, required: true, description: 'Path relative to the docs folder'

  def initialize(root:)
    super()
    @root = File.realpath(root)
  end

  def execute(path:)
    full = File.realpath(File.join(@root, path))
    raise RCrewAI::Tools::ToolError, 'Path is outside the docs folder' unless full.start_with?("#{@root}/")

    File.read(full)
  rescue Errno::ENOENT
    raise RCrewAI::Tools::ToolError, "No such document: #{path}"
  end
end
```

- Resolve paths before checking them, as above, so `../` and symlinks can't escape.
- Use parameterized queries, and allowlists for commands, hosts, and table names.
- Keep secrets in `initialize`, and leave them out of return values and error messages.
- For risky actions, require a person to approve them with `require_approval_for_tools: true`.

## Testing Tools

Test `execute_with_validation` with string keys, since that's how the runner calls
your tool, with arguments shaped like the model's JSON:

```ruby
RSpec.describe WordCount do
  subject(:tool) { described_class.new }

  it 'counts words' do
    expect(tool.execute_with_validation('text' => 'one two three')).to eq('3')
  end

  it 'requires text' do
    expect { tool.execute_with_validation({}) }.to raise_error(RCrewAI::Tools::ToolError, /missing required param/)
  end

  it 'publishes its schema' do
    expect(described_class.json_schema[:parameters][:required]).to eq(['text'])
  end
end
```

To test an agent using a tool without calling a real API, pass a fake client through
`llm:`. Anything that responds to `chat` works.

## Tools Without the DSL

Tools written before the DSL still work:

```ruby
class LegacyTool < RCrewAI::Tools::Base
  def initialize
    super
    @name = 'legacy'
    @description = 'A tool that sets its name in initialize'
  end

  def execute(**params)
    validate_params!(params, required: [:input])
    "Got #{params[:input]}"
  end
end
```

A tool like this has no declared parameters, so it prints a warning and gets a
permissive schema: `Tool LegacyTool has no DSL declarations; using permissive schema`.
The model then has no description of its arguments, so add `param` declarations when
you next touch it.

## Best Practices

- **Do one thing per tool.** Several small tools are easier for a model to choose between.
- **Write descriptions for the model.** Include when to use the tool and what each parameter means.
- **Return only what's useful.** Tool output goes into the conversation and costs tokens.
- **Set timeouts on network calls.** A hung tool holds up the whole turn.
- **Make retried actions safe.** A model may call a tool again after an error.

## Next Steps

- [Tools API reference]({{ site.baseurl }}/api/tools)
- [Advanced Agent Configuration]({{ site.baseurl }}/tutorials/advanced-agents)
- [MCP guide]({{ site.baseurl }}/mcp)
