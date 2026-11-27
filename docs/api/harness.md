---
layout: api
title: Tool-call Harness
description: Allow, ask about or block an agent's tool calls, and run hooks around them
---

# Tool-call Harness

An `RCrewAI::Harness` decides, call by call, whether an agent may run a tool. It
applies on both runners, to parallel tool calls and to `Agent#use_tool`,
including its retries. It isn't a sandbox: read [Not a sandbox](#not-a-sandbox)
before relying on it.

To learn it step by step, follow the
[agent harness tutorial]({{ site.baseurl }}/tutorials/agent-harness).

## Example

```ruby
harness = RCrewAI::Harness.new(default: :ask) do
  allow :file_reader, :web_search
  ask   :email_sender
  block :code_executor, reason: 'No code execution here. Describe the change instead.'
  block :file_writer, matching: { file_path: /(\.env|\.lock)\z/ },
                      reason: 'Secrets and lockfiles are read-only.'
  allow :file_writer

  before(:file_writer) do |call|
    call.args['content'].include?('AKIA') ? 'Content looks like a key. Remove it and try again.' : true
  end

  after(:file_writer) do |call|
    "#{call.args['file_path']} has trailing whitespace." if call.args['content'].match?(/[ \t]$/)
  end
end

# Answers the calls that ask. Replace it with your own way of asking a person.
handler = ->(request) { RCrewAI::ToolApproval.refuse("Nobody approved #{request.tool_name}") }

agent = RCrewAI::Agent.new(
  name: 'maintainer', role: 'Maintainer', goal: 'Keep the project tidy',
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new,
    RCrewAI::Tools::WebSearch.new,
    RCrewAI::Tools::EmailSender.new,
    RCrewAI::Tools::CodeExecutor.new
  ],
  harness: harness,
  approval_handler: handler
)
```

A harness is set per agent. There is no global or crew-wide one. Nothing on this
page applies to agents without one.

## Options

```ruby
RCrewAI::Harness.new(default: :ask, hook_timeout: 60) { ... }
```

- `default:` is the outcome when no rule applies: `:allow`, `:ask` (the default)
  or `:block`. With `:ask`, every unlisted tool asks, including MCP tools and
  tools added later.
- `hook_timeout:` is the number of seconds each hook may run. It must be
  positive.

`allow`, `ask`, `block`, `before` and `after` can be written inside the block or
called on the harness.

## Rules

```ruby
allow :file_reader, :web_search
ask   :sql_database, if: ->(args) { !args['query'].match?(/\A\s*select\b/i) }
block :file_writer, matching: { file_path: /\.env\z/ }, reason: 'Secrets are read-only.'
```

Each rule names at least one tool. Names are compared with the tool instance's
`name`, even when `use_tool` or the legacy runner found the tool by its class
name. An MCP tool's name is `server__tool`.

A rule applies when it names the tool, every `matching:` entry matches, and the
`if:` condition, if there is one, returns a truthy value.

Only `block` takes `reason:`. The model reads it, so say what to try instead.

### Precedence

Among the rules that apply, the strictest wins: `block`, then `ask`, then
`allow`. The order you declare them in doesn't change the outcome (if several
block rules apply, the first one's reason is used). When no rule applies, the
outcome is `default:`.

The agent's `require_approval_for_tools: true` still makes every call that isn't
blocked ask. A harness can't loosen it.

### `matching:`

`matching:` takes one Regexp per argument. The Regexp isn't anchored unless you
anchor it. A rule doesn't apply when the argument is missing. That includes an
optional argument the caller left out: a `param`'s `default:` isn't filled in,
so rules don't see it.

The table is about **the value the rules see**. For a [prepared](#the-order-of-one-call)
tool that is the value after coercion, not what the caller sent:

- A `:string` or `:enum` param is converted with `to_s` first, so it is always a
  String. An explicit `nil` becomes `""`: `block ..., matching: { mode: /w/ }`
  doesn't apply to `mode: nil`, and the tool gets `""`. A number, boolean, hash
  or array becomes its text and is matched as text, so `['.env']` becomes
  `[".env"]`, which `/\.env\z/` doesn't match.
- `:integer` and `:number` params become numbers and `:boolean` params become
  `true` or `false` (`nil` becomes `false`), so they fall in the last row.
- `:array` and `:object` params, and the arguments of tools that aren't
  prepared or declare no `param`s, are seen as supplied.

| Argument value | `block` and `ask` rules | `allow` rules |
|---|---|---|
| String | apply if it matches | apply if it matches |
| Non-empty array of strings | apply if any item matches | apply if all items match |
| Anything else: number, boolean, `nil`, hash, other object, empty or mixed array | apply | don't apply |

The last row is a value that can't be checked, so doubt never loosens anything.

#### Checking the argument names

When the agent is built, a `matching:` name that a tool doesn't have raises
`ArgumentError`, since that rule could never apply. A tool added after the agent
was built (task tools are) is checked on each call, and its call is blocked if a
rule for it names an argument it doesn't have.

A tool's arguments are its declared `param`s. For a tool with no declared
`param`s, such as an MCP tool, they are the keys of `properties` under
`parameters` in its `json_schema` (for MCP, the server's `inputSchema`). The
schema is treated as the complete list unless `additionalProperties` is `true`,
even where JSON Schema would allow other names. Only top-level names are read,
not those under `anyOf`, `oneOf`, `allOf` or `patternProperties`, and no values
are checked.

**Names aren't checked for a tool that lists nothing:** no `json_schema`, no
`properties` or empty ones, or `additionalProperties: true` (what an MCP tool
without an `inputSchema` gets). There a misspelt name means the rule silently
never applies, so a `block` rule lets the call through.

If reading a tool's `json_schema` raises, the agent is still built, with a
warning, and calls to that tool are blocked for as long as it raises, if any
`matching:` rule names the tool. (A task run also reads every tool's schema to
pick a runner, so a schema that raises then fails the run, harness or not.)

A rule or hook naming a tool the agent doesn't have is logged as a warning when
the agent is built.

### `if:`

The condition gets a frozen copy of the arguments, with string keys. If it
raises, the call is blocked, whatever the rule's effect. Conditions run on the
thread making the call, have no timeout and aren't serialized, so with parallel
tool calls they must be thread-safe and quick.

## The order of one call

1. **Prepare the arguments, once.** A tool is *prepared* when it uses the base
   `execute_with_validation`: its arguments are coerced to the declared types. A
   missing required argument, an undeclared argument or a value that can't be
   coerced is an ordinary tool error, and nothing else runs. This also happens
   on the legacy runner and in `use_tool`. **The exception is a tool that
   declares no `param`s: nothing is coerced or rejected,** and it gets every
   argument passed through.
2. **Evaluate the rules.** A blocked call stops here.
3. **Run the `before` hooks,** in declaration order. The first refusal stops the
   call.
4. **Ask for approval,** if the outcome is `ask` or the agent requires it. See
   [tool approval]({{ site.baseurl }}/examples/human-in-the-loop). With no
   handler and no terminal, the call is refused.
5. **Run the tool** with the arguments that steps 2 to 4 saw.
6. **Run the `after` hooks.**

Rules, hooks and the approval handler get frozen, string-keyed copies of the
arguments, and the tool gets a fresh copy. Only hashes, arrays and strings are
copied. Any other object (possible through `use_tool`, for example) is shared by
reference: a hook, condition or handler that mutates it changes what the tool
receives, and so can anyone else who holds it. `matching:` treats such a value
as uncheckable.

### What preparing the arguments does and doesn't do

- For a tool with declared `param`s, undeclared arguments are rejected, not
  dropped.
- **Nested keys inside object arguments reach the tool as strings,** even if the
  caller passed symbols. Top-level arguments reach `execute` as keywords. This
  differs from agents without a harness when `use_tool` is given nested symbol
  keys.
- Validation is limited to what the base class does: arrays, objects and enum
  values aren't checked, and an unrecognised boolean becomes `false`.

### Tools that override `execute_with_validation`

A tool that overrides `execute_with_validation` (MCP tools do), or isn't a
`RCrewAI::Tools::Base` and may only have `execute`, isn't prepared. **The harness
does no coercion or argument checks for it beyond what your rules see.** Rules
see the arguments as supplied, with string keys, and the harness passes the tool
a copy of exactly those. What the tool does with them afterwards is its own
behaviour. The names in `matching:` are still
[checked](#checking-the-argument-names) where the tool lists its arguments, but
no values are validated against a schema.

## Hooks

`before` and `after` take tool names. With none, the hook applies to every tool.
Each hook gets a `call` with `tool_name`, `args`, `agent` (the agent's name) and
`call_id` (`nil` on the legacy runner and in `use_tool`). `after` hooks also get
`result` or `error`.

### `before`

| The hook | The call |
|---|---|
| returns `true` or `nil` | goes on |
| returns a String | is refused, with the string as the reason |
| returns anything else, including `false` | is refused |
| raises, calls `exit`, times out or ends its thread | is refused |

Hooks can't change the arguments. Watch for blocks whose last expression is
`false` or another value, such as a logging call: end them with `true`.

### `after`

`after` hooks run once the tool has returned, or raised a `StandardError` or a
`ScriptError` (`NotImplementedError`, for one). **They don't run if the tool
ends any other way:** by raising another exception, such as `SystemStackError`
or `NoMemoryError`, by calling `exit`, through `throw`, or because its thread was
killed. Don't rely on an `after` hook for cleanup or auditing that must happen.
Nor do they run for calls that were refused or had invalid arguments. A
non-empty String
they return is appended to what the model reads, after the result or error
message. Other return values are ignored. Many built-in tools report failures by
returning a message instead of raising, so `call.error` being `nil` doesn't mean
the action worked.

`call.result` is a frozen copy. Plain `Hash`, `Array` and `String` values are
copied, and `nil`, booleans, numbers and symbols are passed as they are.
**Anything else, including subclasses of `Hash`, `Array` or `String`, is given
as its text** (`to_s`), also when it's nested inside the result. `call.error` is
the exception the tool raised.

Notes are added only to what the model reads. `tool_calls_history`, memory and
`ToolCallResult` keep the raw result. When a legacy run reaches its iteration
limit and takes its final answer from the last tool output, that answer has no
notes either. (The model can still repeat a note in its own words.) `use_tool`
returns the result (or raises) as usual and logs the notes.

### Threads and timeouts

- **Each hook runs on its own thread,** so it doesn't see the caller's
  thread-local variables or fiber-local `Thread.current[:key]` values. Pass what
  it needs through the block's closure.
- **Hooks on one harness run one at a time,** even across parallel tool calls or
  agents that share the harness, so they needn't be thread-safe. A slow hook
  delays the others. Time spent waiting for a turn doesn't count against
  `hook_timeout`.
- **A tool call made from inside a hook, through an agent using the same
  harness, is refused.** Threads a hook spawns aren't detected. Their calls
  aren't refused for this reason: a call that needs a hook waits for the one
  that spawned it, so waiting for it there stalls until the timeout, and it can
  still run afterwards. Don't make tool calls from threads started by a hook.
- A hook that times out is killed with `Thread#kill`, then given up to another
  `hook_timeout` seconds to finish its `ensure` blocks. **If it still hasn't
  stopped, every call that a `before` hook applies to is refused, on every agent
  using that harness, until it does.** Meanwhile `after` hooks don't run: each
  leaves a note saying so. A hook that never stops keeps this state for as long
  as the process runs.

### When hooks fail

Hooks fail closed before the tool runs: a broken `before` check never lets a
call through. After it, the side effect has already happened, so **a failing
`after` hook leaves the tool's result standing** and appends a note naming the
hook. Reporting the call as failed would invite the model to repeat it. A failed
`after` hook doesn't stop later ones, unless it's still running.

## What the model and your code see

A call blocked by a rule or refused by a hook reaches the model as:

```
REFUSED: Tool '<name>' was not run: <reason>
```

The run continues. `use_tool` returns the same string. Refused approvals keep
their usual wording. Refused calls aren't added to `tool_calls_history` or to
tool-usage memory.

For calls that run, **`tool_calls_history`, memory and the `ToolCallStart` event
record the arguments as the model sent them** (on the legacy runner, as parsed
from its text), not the prepared ones. `ToolCallStart` is emitted for refused
calls too. Don't read these as what was checked or what the tool received: for
example, the model may send `"5"` where the tool got `5`. `ToolBlocked` and the
approval events carry the checked arguments.

Two events explain why a call didn't run or a hook didn't work:

| Event | When | Fields |
|---|---|---|
| `Events::ToolBlocked` | a rule or `before` hook stopped a call | `tool`, `args`, `call_id`, `reason`, `source` (`:rule` or `:hook`) |
| `Events::ToolHookFailed` | a hook raised, timed out or ended its thread, or an `after` hook couldn't be run | `tool`, `call_id`, `hook` (such as `before(file_writer) #1`), `phase` (`:before` or `:after`), `error` |

A failed `before` hook emits both. A `before` hook that refuses by returning a
value only emits `ToolBlocked`, and so does a call refused because an earlier
hook is still running or because it came from inside a hook. A refused approval
emits the approval events instead. `use_tool` has no event stream, so it emits
none of these.

## Not a sandbox

A harness controls which tool calls start. It doesn't contain what they do.

- **Rules see only tool names and arguments.** They know nothing about the files,
  network or data behind them.
- **They don't limit what a tool does inside.** Allowing `code_executor` allows
  whatever the code does, including writing the files your `file_writer` rules
  protect.
- **A path pattern doesn't resolve `..` or symlinks.** It matches the text of
  the argument. It also doesn't know that two spellings can name one file, such
  as `.ENV` on a case-insensitive filesystem. A pattern that allows paths under
  one directory can be escaped with `..` or a symlink.
- **Writes that aren't tool calls aren't covered:** a task's `output_file`,
  memory and guardrails.
- **Only the agent's tool calls are covered.** Your own code, or a tool that
  calls another tool's `execute` directly, goes around the harness.

If an action must be impossible, don't give the agent a tool that can do it, or
enforce the limit outside Ruby: file permissions, a container, a read-only
database user.
