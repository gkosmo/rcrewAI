# Harness Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a developer allow, ask about, block and check any tool call an agent makes.

**Architecture:** `RCrewAI::Harness` holds rules and hooks and knows nothing about runners. `ToolExecution`, the one place tools run, applies it: prepare arguments, rules, before hooks, approval, execute, after hooks. Agents without a harness take today's code path.

**Tech Stack:** Ruby >= 3.0, RSpec, RuboCop. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-27-harness-stage-1-design.md`

**Base branch:** this branch, which sits on `fix/harness-gaps` (gkosmo/rcrewAI#61). If #61 changes or merges, rebase before opening a PR.

## Global Constraints

- Behaviour for an agent without a harness does not change, including argument handling and what approval handlers see.
- Strictest applicable rule wins: block, then ask, then allow. Declaration order doesn't matter.
- `default:` is `:ask`. `require_approval_for_tools: true` makes every unblocked call ask.
- A harness refusal reads exactly `REFUSED: Tool '<name>' was not run: <reason>` to the model on both runners and from `use_tool`. Approval refusals keep their current wording.
- A `before` hook passes only by returning `true` or `nil`.
- Hook timeout default: 60 seconds. Hooks on one harness run one at a time.
- Refused calls stay out of `tool_calls_history`.
- Run tests as `ASDF_RUBY_VERSION=3.3.11 bundle exec rspec` (local 3.3.0 is broken). `bundle exec rubocop` must be clean. CI also runs Ruby 3.1 and 3.2.
- Commit messages end with the session's attribution line. Don't push or open a PR without being asked.

## Review Focus

1. A rule misses because the model used an alias: the legacy runner and `use_tool` also find `file_writer` as `filewriter`. Rules must still apply (Task 3).
2. `matching:` names an argument the tool doesn't declare (`path` for `file_path`), so a block silently never fires. Expect `ArgumentError` when the agent is built (Task 3).
3. A rule names a tool the agent doesn't have (typo, or an MCP tool not connected). With `default: :allow` that leaves the real tool open. Expect a warning naming it (Task 3).
4. A logging hook ends in an expression such as `seen << call`, which returns an Array. Expect a refusal that names the hook and says what it returned, not a mystery block (Task 4).
5. Parallel calls queue behind a slow hook. Time spent waiting for the lock must not count against the next hook's timeout (Task 4).

## File Structure

| File | Responsibility |
|---|---|
| `lib/rcrewai/tools/base.rb` (modify) | `prepare_arguments`: coercion split out of execution |
| `lib/rcrewai/harness.rb` (create) | DSL, `decide`, `validate_tools`, `Blocked`, `Call` |
| `lib/rcrewai/harness/rule.rb` (create) | Whether one rule applies to one call |
| `lib/rcrewai/harness/hooks.rb` (create) | Running hooks: lock, timeout, fail-closed results |
| `lib/rcrewai/tool_execution.rb` (modify) | The pipeline |
| `lib/rcrewai/tool_approval.rb`, `events.rb`, `agent.rb`, `tool_runner.rb`, `legacy_react_runner.rb`, `lib/rcrewai.rb` (modify) | Wiring |
| `spec/support/harness_helpers.rb` (create) | Spy tool and scripted LLM shared by the harness specs |

---

### Task 1: Prepare arguments separately from execution

**Files:** Modify `lib/rcrewai/tools/base.rb`. Test: `spec/tools/prepare_arguments_spec.rb`.

**Interfaces — Produces:** `Tools::Base#prepare_arguments(args_hash, reject_undeclared: false) -> Hash{Symbol=>Object}`; raises `Tools::ToolError`. `execute_with_validation(args_hash)` becomes `execute(**prepare_arguments(args_hash))`.

- [ ] **Step 1: Write the failing tests** against a tool declaring `param :path, type: :string, required: true` and `param :limit, type: :integer`:

```ruby
expect(tool.prepare_arguments({ 'path' => 7, 'limit' => '3' })).to eq(path: '7', limit: 3)
expect { tool.prepare_arguments({}) }.to raise_error(RCrewAI::Tools::ToolError, 'missing required param: path')
expect(tool.prepare_arguments({ 'path' => 'a', 'x' => 1 })).to eq(path: 'a')
expect { tool.prepare_arguments({ 'path' => 'a', 'x' => 1 }, reject_undeclared: true) }
  .to raise_error(RCrewAI::Tools::ToolError, 'unknown param: x')
# a tool with no declared params passes everything through, even when rejecting
expect(schemaless.prepare_arguments({ 'x' => 1 }, reject_undeclared: true)).to eq(x: 1)
```

- [ ] **Step 2:** `bundle exec rspec spec/tools/prepare_arguments_spec.rb` → FAIL, `undefined method 'prepare_arguments'`.
- [ ] **Step 3:** Implement, moving the loop out of `execute_with_validation`.
- [ ] **Step 4:** Full suite → 0 failures.
- [ ] **Step 5:** Commit `Split argument preparation out of execute_with_validation`.

### Task 2: Harness rules

**Files:** Create `lib/rcrewai/harness.rb`, `lib/rcrewai/harness/rule.rb`; require from `lib/rcrewai.rb` after `tool_approval`. Test: `spec/harness/rules_spec.rb`.

**Interfaces — Produces:**
- `Harness.new(default: :ask, hook_timeout: 60, &block)`; the block is `instance_eval`ed.
- `allow(*tools, matching: nil, if: nil)`, `ask(*tools, matching: nil, if: nil)`, `block(*tools, matching: nil, if: nil, reason: nil)`. Names are Symbol or String.
- `decide(tool_name, args) -> Harness::Decision(outcome, reason)`; `outcome` is `:allow`, `:ask` or `:block`; `args` has string keys.
- `validate_tools(tools) -> Array<String>` of warnings; raises `ArgumentError` for review focus 2 (only for tools with declared params).

`matching:` semantics: every entry must match. Missing argument: no match. String: `Regexp#match?`. Non-empty array of strings: `any?` for block and ask, `all?` for allow. Anything else, including an empty array: matches for block and ask, not for allow.

- [ ] **Step 1: Write the failing tests:**

```ruby
h = RCrewAI::Harness.new do
  allow :writer
  block :writer, matching: { path: /\.env\z/ }, reason: 'Secrets are read-only.'
  ask :mailer
end
expect(h.decide('writer', { 'path' => 'a.txt' }).outcome).to eq(:allow)
expect(h.decide('writer', { 'path' => '.env' }).to_h).to eq(outcome: :block, reason: 'Secrets are read-only.')
expect(h.decide('writer', {}).outcome).to eq(:allow)
expect(h.decide('mailer', {}).outcome).to eq(:ask)
expect(h.decide('other', {}).outcome).to eq(:ask)
```
Also: declaring `block` before `allow` gives the same results; `default: :allow` and `:block` apply to unlisted tools (the `:block` reason is `No rule allows this tool`); a block without `reason:` says `Blocked by the harness`; arrays `['a.txt', '.env']` block, and don't satisfy `allow ..., matching: { path: /\.txt\z/ }`; values `5`, `nil`, `{}` and `[]` satisfy block and not allow; two `matching:` keys need both; `if:` receives the args and combines with `matching:`; an `if:` that raises yields `:block` with a reason containing `rule condition failed`, for allow rules too.

`ArgumentError` cases: `default: :maybe`; a rule with no tool names; a `matching:` value that isn't a Regexp.

`validate_tools`: a rule for `:writr` returns a warning containing `writr`; `matching: { file: /x/ }` on a tool declaring only `path` raises mentioning `file`.

- [ ] **Step 2:** Run → FAIL, `uninitialized constant RCrewAI::Harness`.
- [ ] **Step 3:** Implement both files.
- [ ] **Step 4:** Spec, full suite and RuboCop pass.
- [ ] **Step 5:** Commit `Add Harness rules`.

### Task 3: Enforce rules on every tool path

**Files:** Modify `tool_execution.rb`, `tool_approval.rb`, `events.rb`, `agent.rb`, `tool_runner.rb`, `legacy_react_runner.rb`. Create `spec/support/harness_helpers.rb`. Test: `spec/integration/harness_spec.rb`.

**Interfaces — Consumes:** Tasks 1 and 2. **Produces:**
- `Agent.new(..., harness: nil)`, `attr_reader :harness`. When given, the constructor calls `validate_tools(tools)` and logs each warning.
- `ToolApproval::Refused#model_message -> String` (returns `message`). `Harness::Blocked < ToolApproval::Refused`: `message` is `Tool '<name>' was not run: <reason>`, `model_message` prefixes `REFUSED: `. Give `Refused#initialize` an optional third `message` argument.
- `ToolRunner` keeps sending `"REFUSED: #{e.message}"`. `LegacyReactRunner`, `use_tool` and `handle_tool_failure` send `e.model_message`.
- `Events::ToolBlocked` with `tool, args, call_id, reason, source` (`:rule` or `:hook`), added to the id-prepending list.

**Pipeline for harness agents** (ignores the `coerce:` flag):
1. If the tool is a `Tools::Base` whose `method(:execute_with_validation).owner == Tools::Base`: `prepare_arguments(args, reject_undeclared: true)`. Otherwise take the arguments as supplied.
2. Snapshot once as a deeply frozen, string-keyed copy (the existing `frozen_copy`). Everything below reads the snapshot.
3. `decide`; `:block` emits `ToolBlocked` and raises `Blocked`.
4. Ask when the outcome is `:ask` or `require_approval_for_tools?`.
5. Execute with a fresh unfrozen deep copy of the snapshot: prepared tools get `execute(**top_level_symbols)`; others get `execute_with_validation(string_keys)` if they have it, else `execute(**top_level_symbols)`.

`harness_helpers.rb` provides `HarnessSpyTool` (`tool_name 'spy_writer'`, `param :path` string required, `param :body` string; records the kwargs of each call under a mutex; returns `"wrote <path>"`) and `HarnessLLM.new(native:, turns:)`, which replays turns, records each request's messages, then answers `FINAL_ANSWER[all done]`. Model them on the helpers at the top of `spec/integration/tool_approval_spec.rb`.

- [ ] **Step 1: Write the failing tests.** Run the first group once with `native: true` and once with `native: false`:
  - blocked call: spy never runs; the model's next request includes `REFUSED: Tool 'spy_writer' was not run: Secrets are read-only.`; `tool_calls_history` is empty; one `ToolBlocked` with `source: :rule`.
  - `allow` runs without calling the handler; `ask` calls it once; an unlisted tool with no handler and non-tty stdin doesn't run.
  - `require_approval_for_tools: true` plus `allow` still asks; plus `block` doesn't ask.
  - missing required and undeclared arguments: tool doesn't run, handler not asked, model sees the `ToolError` text.
  - handler receives coerced values (`'path' => '7'` for an Integer 7, native); a handler that tries to mutate them doesn't change what runs.
  - mutating the model's original argument strings after the check (from the handler, via a captured reference) doesn't change what runs.
  - two parallel native calls, one blocked: only the other runs.
  - `use_tool('spy_writer', path: '.env')` returns the `REFUSED:` string; so does `use_tool('harnessspytool', path: '.env')` (review focus 1), and legacy `USE_TOOL[harnessspytool](path=.env)` is blocked.
  - the human retry in `handle_tool_failure` with new parameters `{"path": ".env"}` is blocked.
  - overriding tool (an `MCP::ToolAdapter` with a stub client, name `srv__send`): `block :srv__send` stops it; when allowed, the client receives exactly the supplied arguments, extra keys included.
  - review focus 2: building an agent with `matching: { file_path: /x/ }` for the spy raises `ArgumentError`. Review focus 3: a rule for `:spy_writr` logs a warning naming it.
  - an agent without a harness: undeclared arguments are still dropped.
- [ ] **Step 2:** Run → FAIL, unknown behaviour for `harness:` (tool runs when it should be blocked).
- [ ] **Step 3:** Implement. Keep the no-harness branch of `ToolExecution#call` as it is today.
- [ ] **Step 4:** Spec, full suite and RuboCop pass; `tool_approval_spec.rb` unchanged and green.
- [ ] **Step 5:** Commit `Enforce harness rules on every tool path`.

### Task 4: Before hooks

**Files:** Create `lib/rcrewai/harness/hooks.rb`; modify `harness.rb`, `tool_execution.rb`, `events.rb`. Test: `spec/harness/before_hooks_spec.rb`.

**Interfaces — Produces:**
- `Harness#before(*tools, &hook)`; no names means every tool.
- `Harness::Call = Struct.new(:tool_name, :args, :agent, :call_id, :result, :error, keyword_init: true)`.
- `Harness#check_before(call) -> Refusal(reason, hook, error) | nil`, delegating to `Hooks`.
- `Events::ToolHookFailed` with `tool, call_id, hook, phase, error`. A hook's label is `before(<names or *>) #<position>`.
- Pipeline: after rules, before approval. A refusal emits `ToolBlocked(source: :hook)` and raises `Blocked`; a raise or timeout also emits `ToolHookFailed(phase: :before)`.

Run each hook on its own thread, as `Agent#ask_handler` does: rescue `StandardError, ScriptError`, kill on timeout. Take the harness mutex first, then start the timer. Add `before`/`after` names to `validate_tools` warnings.

- [ ] **Step 1: Write the failing tests** (through an agent run unless noted):
  - `true` and `nil` pass; `'Looks like a key.'` refuses with that reason.
  - `false`, `:ok` and `[call]` refuse; the reason contains `before(spy_writer) #1`, `returned` and the class name (review focus 4).
  - raising: refused, reason names the hook and error class, `ToolHookFailed` emitted. Hanging with `hook_timeout: 0.05`: refused, reason contains `timed out`. `raise NotImplementedError`: refused.
  - hooks run in declaration order; the first refusal stops later hooks; a hook for another tool doesn't run; a nameless hook runs for all.
  - a rule block runs no hooks; a hook refusal never asks the approval handler.
  - `call.args` is frozen and string-keyed.
  - three parallel calls with a 0.04s hook and `hook_timeout: 0.1`: all run, and hooks never overlap (review focus 5).
- [ ] **Step 2:** Run → FAIL, `undefined method 'before'`.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Spec, full suite and RuboCop pass.
- [ ] **Step 5:** Commit `Add before-tool hooks that fail closed`.

### Task 5: After hooks

**Files:** Modify `harness.rb`, `harness/hooks.rb`, `tool_execution.rb`, `tool_runner.rb`, `legacy_react_runner.rb`, `agent.rb`. Test: `spec/harness/after_hooks_spec.rb`.

**Interfaces — Produces:**
- `Harness#after(*tools, &hook)`; `Harness#run_after(call) -> Array<Hooks::Note(text, hook, error)>`.
- `ToolExecution#call(..., notes: [])` appends note strings to the caller's array, including when it then re-raises the tool's error. Return value is unchanged.
- Runners send the model `[result.to_s, *notes].join("\n")`; on failure the notes follow the existing `ERROR:` / `failed:` text. `use_tool` and the retries log notes.
- A failed after hook's note is `Note: the after hook <label> failed (<ErrorClass or "timed out">). The tool call itself was not undone.` It emits `ToolHookFailed(phase: :after)`. Labels are `after(<names or *>) #<position>`.

- [ ] **Step 1: Write the failing tests** on both runners:
  - a hook returning `'lint: 2 offences'` reaches the model after `wrote a.rb`; `tool_calls_history` result and the `ToolCallResult` event stay `wrote a.rb`.
  - non-String returns add nothing.
  - a raising and a hanging hook: result kept, note present, event emitted, later after hooks still run.
  - a tool that raises: hook sees `call.error`, model gets the error followed by the note.
  - blocked and refused calls run no after hooks.
  - `use_tool` returns the raw result.
  - a legacy turn whose after note is long still ends only after the model has seen it.
- [ ] **Step 2:** Run → FAIL, `undefined method 'after'`.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Spec, full suite and RuboCop pass.
- [ ] **Step 5:** Commit `Add after-tool hooks`.

### Task 6: Strengthen the single-call-site guard, and document

**Files:** Modify `spec/integration/tool_approval_spec.rb` (last example), `README.md`, `CHANGELOG.md`. Create `docs/api/harness.md`.

- [ ] **Step 1:** Replace the guard with an exact allowlist: collect every non-comment, non-`def` line in `lib/**/*.rb` matching `/(\.|&\.)(execute|execute_with_validation)\b|\b(public_send|send)\(:?execute/`, format as `"<path from lib>: <stripped line>"`, and compare the sorted list to a literal `ALLOWED` array. Fill `ALLOWED` from the current output only after reading each entry and confirming it isn't an unguarded tool call (expected others: `task.execute`, `crew.execute`, database `execute`). A comment above it says why a new entry needs that check.
- [ ] **Step 2:** Prove it bites: temporarily add `t.execute(**{})` to `lib/rcrewai/tool_execution.rb`, run → FAIL; remove it, run → PASS.
- [ ] **Step 3:** Write `docs/api/harness.md`: the spec's interface example using real tool names, rule precedence, `matching:` semantics, hook return values, failure behaviour, and a "Not a sandbox" section stating that rules see only names and arguments, don't limit what `code_executor` runs, don't resolve `..` or symlinks, and don't cover `output_file`, memory or guardrails. Link it from the README, and add a CHANGELOG "Added" entry under Unreleased.
- [ ] **Step 4:** Run the doc example in a scratch script against a fake LLM; it must build and block a `.env` write. Full suite and RuboCop pass.
- [ ] **Step 5:** Commit `Guard the tool call site exactly and document the harness`.

### Task 7: Tutorial

Added by the owner when approving the plan.

**Files:** Create `docs/tutorials/agent-harness.md`, `spec/docs/agent_harness_tutorial_spec.rb`. Modify `docs/tutorials/index.md`; link to the tutorial from `docs/api/harness.md`.

**Interfaces — Consumes:** the public interface from Tasks 2 to 5 only.

The tutorial builds one agent step by step, a project assistant that edits files in a working directory, for a Ruby developer who has used rcrewai but not a harness. Front matter and tone follow the other files in `docs/tutorials/`. Sections, in order, each with runnable code and what the reader sees:

1. An agent with `FileReader` and `FileWriter` and no harness: nothing stops a write to `.env`.
2. Rules: allow reads, block secrets and lockfiles with `matching:`, and what the model is told.
3. Asking: unlisted tools ask; writing an `approval_handler`; what happens in a job with no terminal.
4. A before hook that refuses content that looks like a key, and the return-value rule (only `true` or `nil` pass).
5. An after hook that syntax-checks a written Ruby file (`ruby -c`, run with an argument array, not a shell string) and returns the error for the model to fix.
6. Testing your harness without a model: `harness.decide`, and `agent.use_tool`.
7. Not a sandbox: the limits listed in `docs/api/harness.md`, including that built-in file tools' own path restrictions are separate from harness rules.

- [ ] **Step 1: Write the failing test.** It reads the tutorial, evaluates every fenced block tagged ```` ```ruby ```` in order in one shared binding, inside a temporary working directory, with a scripted LLM and no network, and asserts: no block raises; `.env` is never written once the harness is in place; the refusal text appears in what the model received; the after hook's syntax error appears there too. Blocks that can't run in a test (provider configuration) are tagged ```` ```text ```` or preceded by `<!-- not-run -->`.
- [ ] **Step 2:** Run → FAIL, tutorial file missing.
- [ ] **Step 3:** Write the tutorial and add it to the index.
- [ ] **Step 4:** Spec, full suite and RuboCop pass.
- [ ] **Step 5:** Commit `Add the agent harness tutorial`.
