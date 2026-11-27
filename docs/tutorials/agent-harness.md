---
layout: tutorial
title: Building an Agent Harness
description: Block, ask about and check an agent's tool calls, one step at a time, with a project assistant that edits files
---

# Building an Agent Harness

A harness decides, call by call, whether an agent may run a tool, and can run your
code before and after each call. In this tutorial you give a project assistant
two file tools, watch it overwrite a secrets file, and then add a harness one
piece at a time. The [harness API page]({{ site.baseurl }}/api/harness) has the
full reference.

You need to know how to build an agent with tools. No LLM or API key is needed: a
small scripted class stands in for the model, so you choose exactly what the
"model" tries to do. A harness is **not a sandbox**, and the
[last section](#7-not-a-sandbox) says what it can't stop.

## Table of Contents
- [Setup](#setup)
- [1. An Agent With No Harness](#1-an-agent-with-no-harness)
- [2. Rules](#2-rules)
- [3. Asking](#3-asking)
- [4. A Before Hook](#4-a-before-hook)
- [5. An After Hook](#5-an-after-hook)
- [6. Testing Your Harness Without a Model](#6-testing-your-harness-without-a-model)
- [7. Not a Sandbox](#7-not-a-sandbox)

## Setup

The code creates, overwrites and deletes files in the current directory, so run
it in a new, empty one. The blocks build on each other. Paste them in order into
one file, `assistant.rb`, and run it from an empty directory **next to** that
file:

```bash
mkdir assistant-demo
cd assistant-demo
ruby ../assistant.rb
```

The script refuses to start in a directory that isn't empty, so to run it again
after adding a step, use another new directory.

Start with a pretend project. Every secret in this tutorial is fake.

```ruby
require 'rcrewai'

raise 'Run this in an empty directory: it overwrites files' unless Dir.empty?('.')

File.write('.env', "API_TOKEN=fake-original-token\n")
File.write('Gemfile.lock', "GEM\n  specs:\n    rake (13.2.1)\n")
File.write('README.md', "# Demo project\n")
File.write('scratch.log', "debug output\n")
```

Next, the stand-in model. An agent accepts any object with a `chat` method as its
`llm:`. This one requests the tool calls you give it, one per turn, prints what
comes back, and then answers.

```ruby
class ScriptedModel
  def initialize(*calls)
    @calls = calls
  end

  def supports_native_tools?(**)
    true
  end

  def chat(messages:, **)
    last = messages.last
    puts "model reads: #{last[:content]}" if last[:role] == 'tool'

    tool, arguments = @calls.shift
    return { content: 'Done.', tool_calls: [], finish_reason: :stop, usage: {} } unless tool

    { content: nil, finish_reason: :tool_calls, usage: {},
      tool_calls: [{ id: "call_#{@calls.size}", name: tool, arguments: arguments }] }
  end
end
```

To use a real model later, leave `llm:` out and configure a provider (see
[LLM Providers]({{ site.baseurl }}/tutorials/providers)). Nothing about the
harness changes.

```text
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.api_key = ENV.fetch('ANTHROPIC_API_KEY')
end
```

## 1. An Agent With No Harness

The assistant gets `FileReader` and `FileWriter`. By default both accept only
`.txt`, `.md`, `.json`, `.yaml`, `.yml`, `.csv` and `.log` files. A project
assistant has to edit Ruby files, and a `Gemfile` has no extension at all, so
open both tools up with `allowed_extensions: ['*']`.

```ruby
def file_tools
  [RCrewAI::Tools::FileReader.new(allowed_extensions: ['*']),
   RCrewAI::Tools::FileWriter.new(allowed_extensions: ['*'])]
end

def assistant(model, tools: file_tools, **options)
  RCrewAI::Agent.new(name: 'assistant', role: 'Project assistant',
                     goal: 'Keep the project in working order',
                     tools: tools, llm: model, **options)
end

def work(agent)
  task = RCrewAI::Task.new(name: 'chore', description: 'Tidy up the project',
                           expected_output: 'A short summary')
  agent.execute_task(task)
end
```

Now have the model replace the secrets file:

```ruby
work(assistant(ScriptedModel.new(
  ['file_writer', { 'file_path' => '.env', 'content' => "API_TOKEN=overwritten-by-the-model\n" }]
)))

puts File.read('.env')
```

You see this. Here and below, the output leaves out the agent's log lines and the
extra lines of each tool result, such as file sizes and times:

<!-- output -->
```text
model reads: Content successfully written to .env
API_TOKEN=overwritten-by-the-model
```

Nothing stopped it. With the default extension list, `FileWriter` would have
refused `.env`, but only because that name has no extension. The list is about
file types, not secrets: it lets `credentials.yml` and `.env.json` through.

Put the original back. None of the model's later attempts changes it.

```ruby
File.write('.env', "API_TOKEN=fake-original-token\n")
```

## 2. Rules

A rule says `allow`, `ask` or `block` for the tools it names. `matching:` narrows
it to calls whose argument matches a Regexp.

The pattern is the part to get right. `/\.env\z/` looks like it protects env
files, but it misses `.env.local` and, on a case-insensitive filesystem such as
the macOS default, `.ENV`, which is the same file as `.env`. Compare it with the
pattern this tutorial uses:

```ruby
SECRETS   = %r{(\A|/)\.env[^/]*\z}i
LOCKFILES = %r{(\.lock|(\A|/)(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml))\z}i

naive = /\.env\z/
['.env', '.env.local', '.ENV', 'config/.env.production', 'production.env'].each do |path|
  puts format('%-23s naive: %-5s SECRETS: %s', path, naive.match?(path), SECRETS.match?(path))
end
```

<!-- output -->
```text
.env                    naive: true  SECRETS: true
.env.local              naive: false SECRETS: true
.ENV                    naive: false SECRETS: true
config/.env.production  naive: false SECRETS: true
production.env          naive: true  SECRETS: false
```

Know exactly what each one covers:

- `SECRETS` covers a path whose **last part starts with `.env`**, in any letter
  case, with `/` between directories. That includes `.envrc` and
  `.env.example`. It does **not** cover `production.env`, files inside a
  directory called `.env`, or other secrets such as `config/master.key`,
  `secrets.yml` or an SSH key. Add what your project has.
- `LOCKFILES` covers any path ending in `.lock` (`Gemfile.lock`, `yarn.lock`,
  `Cargo.lock`, `poetry.lock`, `composer.lock`), plus files called
  `package-lock.json`, `npm-shrinkwrap.json` or `pnpm-lock.yaml`. It does **not**
  cover `go.sum` or `bun.lockb`.

Now the harness. Allow the file tools, keep them away from env files, and make
lockfiles read-only. Env files are blocked for reading too, because whatever a
tool reads is sent to your model provider.

```ruby
harness = RCrewAI::Harness.new(default: :ask) do
  allow :file_reader, :file_writer

  block :file_reader, :file_writer,
        matching: { file_path: SECRETS },
        reason: '.env files are off limits. Ask the user to change them.'

  block :file_writer,
        matching: { file_path: LOCKFILES },
        reason: 'Lockfiles are generated. Change the manifest and ask the user to update the lockfile.'
end
```

Both `allow` and `block` apply to a write to `.env`. The strictest rule wins
(`block`, then `ask`, then `allow`), so the order you declare them in doesn't
matter.

Pass the harness to the agent and let the model try its luck:

```ruby
work(assistant(ScriptedModel.new(
  ['file_reader', { 'file_path' => '.env' }],
  ['file_writer', { 'file_path' => '.env', 'content' => "API_TOKEN=second-attempt\n" }],
  ['file_writer', { 'file_path' => 'Gemfile.lock', 'content' => "GEM\n" }],
  ['file_reader', { 'file_path' => 'Gemfile.lock' }],
  ['file_writer', { 'file_path' => 'notes.md', 'content' => "Checked the project.\n" }]
), harness: harness))
```

<!-- output -->
```text
model reads: REFUSED: Tool 'file_reader' was not run: .env files are off limits. Ask the user to change them.
model reads: REFUSED: Tool 'file_writer' was not run: .env files are off limits. Ask the user to change them.
model reads: REFUSED: Tool 'file_writer' was not run: Lockfiles are generated. Change the manifest and ask the user to update the lockfile.
model reads: File: Gemfile.lock
model reads: Content successfully written to notes.md
```

A blocked call doesn't raise and doesn't end the run. The model gets
`REFUSED: Tool '<name>' was not run: <reason>` as the tool's result and carries
on. It reads your `reason:`, so say what to do instead.

A misspelt argument name doesn't pass silently here. `FileWriter` has no `path`
argument, so a rule with `matching: { path: SECRETS }` could never apply, and
`Agent.new` raises `ArgumentError`. Names can't be checked for a tool that doesn't
list its arguments: see
[checking the argument names]({{ site.baseurl }}/api/harness#checking-the-argument-names).

## 3. Asking

The harness was built with `default: :ask`, so a call that no rule covers needs
approval. That includes every tool you add later. Here is a new one with no
safety checks of its own:

```ruby
class FileDeleter < RCrewAI::Tools::Base
  tool_name   'file_deleter'
  description 'Delete a file in the project'
  param :file_path, type: :string, required: true, description: 'The file to delete'

  def execute(file_path:)
    File.delete(file_path)
    "Deleted #{file_path}"
  end
end
```

Rules apply only to the tools they name, so your `.env` rules don't cover this
one. Give it its own block rule, so that nobody can approve deleting an env file
or a lockfile by mistake. Rules can be added to a harness after it's built:

```ruby
harness.block :file_deleter, matching: { file_path: SECRETS }, reason: '.env files are off limits.'
harness.block :file_deleter, matching: { file_path: LOCKFILES }, reason: 'Keep the lockfiles.'

tools = file_tools + [FileDeleter.new]
```

### A job with no terminal

With no `approval_handler`, on the agent or in `RCrewAI.configure`, the agent asks
at the terminal: you get a prompt, and by default no answer within 60 seconds
means no. In a cron job, a background worker or CI there is no terminal, so the
call is **refused at once**. To see that when you run the script by hand, take its
terminal away for one run:

```ruby
terminal = $stdin
$stdin = File.open(File::NULL)
begin
  work(assistant(ScriptedModel.new(['file_deleter', { 'file_path' => 'scratch.log' }]),
                 tools: tools, harness: harness))
ensure
  $stdin.close
  $stdin = terminal
end

puts "scratch.log exists: #{File.exist?('scratch.log')}"
```

<!-- output -->
```text
model reads: REFUSED: Tool 'file_deleter' was not run because approval was refused: No approval handler is configured and there is no terminal to ask
scratch.log exists: true
```

### Writing an approval handler

A handler is anything with `call(request)`. The request has `tool_name`,
`arguments` (frozen, with string keys), `agent` and `call_id`. Answer with
`RCrewAI::ToolApproval.approve` or `RCrewAI::ToolApproval.refuse(reason)`. Only an
explicit yes runs the tool: an exception, a timeout or any other answer refuses.

This one needs no person. It approves one deletion that is known to be safe and
refuses the rest:

```ruby
DISPOSABLE = ['scratch.log'].freeze

reviewer = lambda do |request|
  path = request.arguments['file_path']
  if request.tool_name == 'file_deleter' && DISPOSABLE.include?(path)
    RCrewAI::ToolApproval.approve
  else
    RCrewAI::ToolApproval.refuse("#{request.tool_name} on #{path} needs a person to agree. Leave it and say so.")
  end
end

work(assistant(ScriptedModel.new(
  ['file_deleter', { 'file_path' => '.env' }],
  ['file_deleter', { 'file_path' => 'README.md' }],
  ['file_deleter', { 'file_path' => 'scratch.log' }]
), tools: tools, harness: harness, approval_handler: reviewer))

puts "README.md exists: #{File.exist?('README.md')}, scratch.log exists: #{File.exist?('scratch.log')}"
```

<!-- output -->
```text
model reads: REFUSED: Tool 'file_deleter' was not run: .env files are off limits.
model reads: REFUSED: Tool 'file_deleter' was not run because approval was refused: file_deleter on README.md needs a person to agree. Leave it and say so.
model reads: Deleted scratch.log
README.md exists: true, scratch.log exists: false
```

The block rule refused the first call before the handler saw it. The list holds
exact paths on purpose: a check such as `path.start_with?('tmp/')` would approve
`tmp/../README.md`.

To ask a person through chat or a web page, post the request there, wait for the
reply and return it. The handler has `approval_timeout` seconds to answer: 60
unless you set it on the agent or in the configuration. See
[Human-in-the-Loop]({{ site.baseurl }}/examples/human-in-the-loop).

## 4. A Before Hook

A `before` hook runs your own code on each call the rules didn't block, before
anyone is asked to approve it. Use one when you want to work out the refusal
yourself. This one refuses file content that looks like a key:

```ruby
KEY_SHAPES = /AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\bsk-[A-Za-z0-9_-]{20,}/

harness.before(:file_writer) do |call|
  if call.args['content'].match?(KEY_SHAPES)
    'The content looks like it contains a key. Read it from an environment variable instead.'
  else
    true
  end
end

work(assistant(ScriptedModel.new(
  ['file_writer', { 'file_path' => 'config.rb', 'content' => "KEY = 'AKIAFAKEFAKEFAKEFAKE'\n" }],
  ['file_writer', { 'file_path' => 'config.rb', 'content' => "KEY = ENV.fetch('ACCESS_KEY')\n" }]
), tools: tools, harness: harness))

puts File.read('config.rb')
```

<!-- output -->
```text
model reads: REFUSED: Tool 'file_writer' was not run: The content looks like it contains a key. Read it from an environment variable instead.
model reads: Content successfully written to config.rb
KEY = ENV.fetch('ACCESS_KEY')
```

This catches three shapes and nothing else: an `AKIA` access key ID, a PEM
private key header, and `sk-` followed by at least 20 letters, digits, `_` or
`-`. Other kinds of key pass, as does one that
is encoded, or split between a write and a later append (`mode: 'a'`). The hook
sees one call's content, not the finished file, and it only guards `file_writer`.

### Only `true` or `nil` lets a call run

| The hook | The call |
|---|---|
| returns `true` or `nil` | goes on |
| returns a String | is refused, with the string as the reason |
| returns anything else, including `false` | is refused |
| raises, calls `exit`, times out or ends its thread | is refused |

A broken check never lets a call through. The catch is that a block returns its
last expression. This hook looks right, but for clean content `include?` returns
`false`, so it refuses every clean write:

```ruby
sloppy = RCrewAI::Harness.new(default: :allow) do
  before(:file_writer) { |call| call.args['content'].include?('AKIA') && 'Looks like a key.' }
end

work(assistant(ScriptedModel.new(
  ['file_writer', { 'file_path' => 'clean.md', 'content' => "Nothing secret here.\n" }]
), harness: sloppy))
```

<!-- output -->
```text
model reads: REFUSED: Tool 'file_writer' was not run: The before hook before(file_writer) #1 returned a value of class FalseClass; only true or nil let a call run, and a String refuses it with that reason
```

Write both branches out, as the first hook does. The same applies when the last
line of a hook is a logging call that returns something else: end it with `true`.

## 5. An After Hook

An `after` hook runs once the tool has. It can't undo the call, but a String it
returns is added to what the model reads. Use that to report problems while the
model can still fix them. This one syntax-checks every Ruby file the assistant
writes:

```ruby
require 'open3'
require 'rbconfig'

harness.after(:file_writer) do |call|
  path = call.args['file_path']
  next unless path.end_with?('.rb') && File.file?(path)

  output, status = Open3.capture2e(RbConfig.ruby, '-c', '--', path)
  "ruby -c found a syntax error in #{path}. Fix the file:\n#{output}" unless status.success?
end
```

The path comes from the model, so how you run the command matters:

- `capture2e` gets **separate arguments, not one command string**, so no shell
  runs. A file called `x; echo oops.rb` is only a strange file name. With
  `` `ruby -c #{path}` `` the shell would run the part after the `;`.
- `--` ends Ruby's options. Without it, a path starting with `-` is read as an
  option instead of the file, and the check can pass without looking at the file.
- `ruby -c` parses the file without running it. `RbConfig.ruby` is the Ruby that
  is running your script.

`call.error` is `nil` even when `FileWriter` fails, because it reports a failure
by returning a message. So the hook checks that the file exists.

The model writes a broken file, reads the error and fixes it:

```ruby
work(assistant(ScriptedModel.new(
  ['file_writer', { 'file_path' => 'greeter.rb', 'content' => "def greet(name)\n  \"Hello, \#{name}\"\n" }],
  ['file_writer', { 'file_path' => 'greeter.rb', 'content' => "def greet(name)\n  \"Hello, \#{name}\"\nend\n" }]
), tools: tools, harness: harness))

puts File.read('greeter.rb')
```

<!-- output -->
```text
model reads: Content successfully written to greeter.rb
ruby -c found a syntax error in greeter.rb. Fix the file:
```

Ruby's own error message follows that line. It reports the syntax error in
`greeter.rb` with a line number, in wording that depends on your Ruby version.
The second write gets no note, and the final `puts` shows the fixed file.

The broken file **was** written: use a `before` hook for anything that must never
reach the disk. If an `after` hook raises or times out, the result stands and the model is
told that the hook failed. `after` hooks don't run in every case, so don't rely on
one for auditing: see [`after`]({{ site.baseurl }}/api/harness#after).

## 6. Testing Your Harness Without a Model

A harness is ordinary Ruby, so test it like the rest of your code. In your own
project, build it in a method that your app and your tests both call.

### `harness.decide`: the rules only

`decide` takes a tool name and arguments and returns the `outcome` (`:allow`,
`:ask` or `:block`) and, for a block, the `reason`. Nothing runs, which makes it
good for a table of cases:

```ruby
[
  ['file_reader',   'README.md',      :allow],
  ['file_reader',   '.ENV',           :block],
  ['file_writer',   'app/.env.local', :block],
  ['file_writer',   'yarn.lock',      :block],
  ['file_reader',   'yarn.lock',      :allow],
  ['file_deleter',  'old_notes.md',   :ask],
  ['email_sender',  'draft.txt',      :ask]
].each do |tool, path, expected|
  actual = harness.decide(tool, { 'file_path' => path }).outcome
  raise "#{tool} #{path}: expected #{expected}, got #{actual}" unless actual == expected

  puts "#{tool} #{path} => #{actual}"
end
```

<!-- output -->
```text
file_reader README.md => allow
file_reader .ENV => block
file_writer app/.env.local => block
file_writer yarn.lock => block
file_reader yarn.lock => allow
file_deleter old_notes.md => ask
email_sender draft.txt => ask
```

`decide` checks **the rules and nothing else**. It runs no hooks, asks no one,
doesn't convert the arguments to the tool's types and doesn't check argument
names. So `decide('file_writer', {})` says `:allow`, since a `matching:` rule
doesn't apply without its argument, although a real call without a path would
fail before reaching the rules.

### `agent.use_tool`: the whole call

`use_tool` runs one call the way a task run would: arguments, rules, `before`
hooks, approval, the tool, then `after` hooks. A refusal comes back as a String.
**An allowed call really runs the tool**, so run these tests in a temporary
directory.

```ruby
tester = assistant(ScriptedModel.new, tools: tools, harness: harness,
                                      approval_handler: ->(_request) { false })

refusals = [
  tester.use_tool('file_writer', file_path: '.env', content: 'x'),
  tester.use_tool('file_writer', file_path: 'test.md', content: 'AKIAFAKEFAKEFAKEFAKE'),
  tester.use_tool('file_deleter', file_path: 'README.md')
]
raise 'a call got through' unless refusals.all? { |result| result.start_with?('REFUSED:', "Tool '") }

puts refusals
```

<!-- output -->
```text
REFUSED: Tool 'file_writer' was not run: .env files are off limits. Ask the user to change them.
REFUSED: Tool 'file_writer' was not run: The content looks like it contains a key. Read it from an environment variable instead.
Tool 'file_deleter' was not run because approval was refused: The approval handler did not answer yes
```

A refusal by a rule or hook starts with `REFUSED:`. A refused approval has its own
wording here. `after` hook notes aren't part of what `use_tool` returns. They are
written to the agent's log. In RSpec, use the same calls with `expect`, and also
check that the file is unchanged.

## 7. Not a Sandbox

A harness controls which tool calls start. It doesn't contain what they do.

**Rules see only the tool name and the arguments.** They know nothing about the
file behind a path. Suppose the project already contains a symlink to `.env`:

```ruby
File.symlink('.env', 'settings.md')

puts harness.decide('file_writer', { 'file_path' => 'settings.md' }).outcome
puts tester.use_tool('file_reader', file_path: 'settings.md')
```

<!-- output -->
```text
allow
File: settings.md
API_TOKEN=fake-original-token
```

The path doesn't match `SECRETS`, so the read returns the secret. A write is
allowed too, and would change `.env`. Hard links do the same.

**A path pattern doesn't resolve `..` either.** It only matches text. Blocking by
the last part of the name, as `SECRETS` does, survives `docs/../.env`. A rule
that *allows* everything under one directory doesn't:

```ruby
docs_only = RCrewAI::Harness.new(default: :block) do
  allow :file_writer, matching: { file_path: %r{\Adocs/} }
end

puts docs_only.decide('file_writer', { 'file_path' => 'docs/../Gemfile.lock' }).outcome
```

<!-- output -->
```text
allow
```

**Only the agent's tool calls are covered.** Your own code, or a tool that calls
another tool's `execute` directly, goes around the harness:

```ruby
RCrewAI::Tools::FileWriter.new(allowed_extensions: ['*'])
                          .execute(file_path: 'Gemfile.lock', content: "# no harness was asked\n")

puts File.read('Gemfile.lock')
```

<!-- output -->
```text
# no harness was asked
```

The other limits:

- **A tool can do anything inside a call.** If you allow `code_executor`, you
  allow whatever the code does, including writing the files your `file_writer`
  rules protect. The same goes for any tool that runs commands, copies files or
  searches file contents.
- **Writes that aren't tool calls aren't covered:** a task's `output_file`, memory
  and guardrails.
- **A new tool needs its own rules.** Your `file_writer` rules say nothing about
  another tool that writes files. `default: :ask` or `:block` stops it from
  running unnoticed.

### The file tools' own path checks are separate

`FileReader` and `FileWriter` have checks of their own. They have nothing to do
with your rules: changing the harness doesn't change them. Don't count on them to
keep the assistant inside the project:

- Both compare the start of the path **as text** with the current directory. From
  `assistant-demo`, a path into a neighbouring `assistant-demo-old` directory
  passes.
- `FileReader` resolves symlinks before that comparison. `FileWriter` expands
  `..` but **doesn't resolve symlinks**, so a link that points outside the project
  lets it write outside the project.
- `allowed_extensions: ['*']` turns the file type check off.

If something must be impossible, enforce it outside Ruby: run the assistant in a
container that has only the files it may touch, set file permissions, and keep
real secrets out of that directory. Or don't give the agent a tool that can do it.

## Next Steps

- [Tool-call Harness API]({{ site.baseurl }}/api/harness): precedence, `if:`
  conditions, events, hook timeouts and threads
- [Custom Tools]({{ site.baseurl }}/tutorials/custom-tools): build tools with
  declared parameters, which the harness can check
- [Interceptors and Events]({{ site.baseurl }}/tutorials/interceptors-and-events):
  watch `ToolBlocked` and `ToolHookFailed` events during a run
