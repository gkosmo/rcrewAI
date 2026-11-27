# Harness stage 1: control over tool calls

Date: 2026-11-27. Status: approved 2026-11-27. Nothing is built.

## Why

The goal is an agent builder where an agent's harness (tools, context,
permissions, hooks, verification, evals) is one definition. Stage 1 covers
permissions and hooks: letting a developer block, gate or check any tool call.
Later stages add evals and verification (2), a Rails builder UI with an approval
inbox (3) and a model that drafts harnesses (4). A UI built before this would
offer settings that nothing enforces.

## Where things stand

- Every tool call in `lib/` goes through `ToolExecution#call`.
  `spec/integration/tool_approval_spec.rb` guards this only partly: it searches
  for `tool.execute` and `execute_with_validation(` and compares file names, so
  `t.execute(...)`, or a second call in an allowed file, would pass. Stage 1 must
  strengthen it.
- Approval is one agent-wide switch (`require_approval_for_tools`) with an
  `approval_handler`. There are no per-tool rules.
- There are no tool hooks. The LLM hooks swallow errors, so they can't block.
- The native runner coerces arguments inside `execute_with_validation`, after
  approval, so a rule checking the raw value could see something other than what
  the tool receives. The legacy runner, `use_tool` and its retries pass
  `coerce: false` and don't coerce at all.
- `execute_with_validation` can be overridden (`MCP::ToolAdapter` does, without
  validating). Base validation doesn't check arrays, objects or enum values,
  turns an unrecognised boolean into `false` and drops undeclared arguments.
- Depends on gkosmo/rcrewAI#61.

## Approaches

| Approach | Trade-off |
|---|---|
| **A. A policy applied inside `ToolExecution`** (picked) | Reuses the single call site, so both runners, `use_tool` and retries are covered. Core changes. |
| B. Wrap each tool in a guard object | No change to execution, but any tool added unwrapped is unguarded, and wrappers must copy names and schemas. |
| C. Act on the event stream | Little new API, but sink errors are reported and skipped, so it can't block reliably. |

## Interface

```ruby
harness = RCrewAI::Harness.new(default: :ask) do
  allow :file_reader, :web_search
  ask   :email_sender
  block :code_executor, reason: 'No code execution here. Describe the change instead.'
  block :file_writer, matching: { file_path: /(\.env|\.lock)\z/ },
                      reason: 'Secrets and lockfiles are read-only.'
  allow :file_writer

  before(:file_writer) { |call| call.args['content'].include?('AKIA') ? 'Content looks like a key.' : true }
  after(:file_writer)  { |call| Lint.run(call.args['file_path']) }
end

agent = RCrewAI::Agent.new(..., harness: harness, approval_handler: handler)
```

## Behaviour

**Rules**
- Tools are matched on the instance's `name`, which for MCP tools is
  `server__tool`.
- A rule applies when its name matches and every `matching:` entry (and the `if:`
  lambda, when given) matches. A missing argument doesn't match.
- *(My call)* `matching:` takes a Regexp per argument, which stage 3 can store as
  source and flags. `if:` is for code-only cases. On an array, a block or ask
  rule applies if any element matches; an allow rule needs all of them to. A
  value that isn't a string (or an array of strings) can't be checked, so block
  and ask rules apply to it and allow rules don't.
- Among applicable rules the strictest wins: block, then ask, then allow. The
  order of declaration doesn't matter.
- No applicable rule means `default:`, which is `:ask` unless set.
- `require_approval_for_tools: true` still means every call that isn't blocked
  asks. A harness can't loosen it.
- An `if:` lambda that raises blocks the call.

**Order of one call (agents with a harness, on every path)**
1. Prepare the arguments once. For tools using the base
   `execute_with_validation`: coerce and validate. A failure, including a missing
   required or an undeclared argument, is an ordinary tool error and nothing else
   runs. *(My call: reject undeclared arguments instead of dropping them.)*
2. Evaluate rules. Blocked calls stop here.
3. Run `before` hooks in declaration order. The first refusal stops the call.
4. Ask for approval if the outcome is ask. People aren't asked about calls that
   would be blocked anyway.
5. Run the tool with the arguments that steps 2 to 4 saw. Checks and handlers get
   frozen copies with string keys, so they can't change them.
6. Run `after` hooks.

*(My call)* A tool that overrides `execute_with_validation`, or only has
`execute`, isn't split apart. Rules see its arguments as supplied (string keys),
and the harness passes it exactly those. Whatever it does with them afterwards is
the tool's own behaviour. Stage 1 adds no schema validation for MCP tools.

**Hooks fail closed**
- A `before` hook passes only by returning `true` or `nil`. A string is a
  refusal with that reason. Any other value, an exception or a timeout refuses.
- Hooks can't change arguments.
- `after` hooks run whether the tool succeeded or raised, and see the result or
  error. A returned string is appended to what the model reads, so lint output
  reaches it. Other return values are ignored.
- If an `after` hook raises or times out, the tool's result stands and a note
  naming the failed hook is appended. The side effect already happened, and
  reporting the call as failed would invite the model to repeat it.
- `before` and `after` with no tool names apply to every tool.

**What the model and the host see**
- A block or hook refusal reaches the model as
  `REFUSED: Tool '<name>' was not run: <reason>` on both runners, and the run
  continues. `use_tool` returns the same string. Refused approvals keep their
  current wording. Each rule's `reason:` should say what to try instead.
- *(My call)* `after` notes are added only to what the model reads, appended to
  the result as text, or to the error message when the tool raised. History,
  memory and `ToolCallResult` keep the raw result. `use_tool` returns or raises
  as it does now and logs the notes.
- Refused calls stay out of `tool_calls_history`.
- New events record rule decisions that block, hook refusals and hook failures,
  so traces can show why a call didn't run.

**Compatibility:** everything above applies only to agents with a harness. Others
behave as they do today, including argument handling and what approval handlers
see.

## Goals
- No path in `lib/` runs a tool without applying the agent's harness.
- What was checked is what runs.
- A broken `before` check never lets a call through.

## Non-goals
- A sandbox. Rules see tool names and arguments only. They don't limit what a
  tool does inside: allowing `code_executor` allows whatever the code does, and
  a path pattern doesn't resolve `..` or symlinks. Docs must say so.
- Writes that aren't tool calls: task `output_file`, memory, guardrails.
- Pausing a run to wait for approval (stage 3).
- Saving, loading or versioning a harness (stage 3).
- Context, verification and evals settings.
- Rails changes. They follow separately.

## Success
Tests show, on both runners, with parallel calls and through `use_tool`: a
blocked call never runs; a raising, hanging or oddly-returning `before` hook
never lets a call run; an argument that changes under coercion is judged by its
coerced value; `after` output reaches the model.

## Decisions (approved by the owner)
1. **Unlisted tools ask.** With no handler and no terminal they are refused.
2. **Rails is a follow-up** after core works: a
   `config.agent_harness = ->(record) {}` hook like `agent_mcp_tools`.

## My calls (change any)
- Per agent only; no global or crew-wide harness.
- Hooks on one harness run one at a time, so they needn't be thread-safe.
- Hook timeout defaults to 60 seconds, like approval.

## Left to the builder
Class and file layout, event names, and how timeouts are implemented.
