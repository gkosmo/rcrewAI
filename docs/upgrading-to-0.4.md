# Upgrading to RCrewAI 0.4

RCrewAI 0.4 closes the feature-parity gap with the modern CrewAI framework. It
adds CrewAI's second pillar — **Flows** — alongside **Knowledge (RAG)**,
structured task output, guardrails, planning, and training/testing.

**0.4 is fully backward compatible.** There are no breaking changes: existing
0.3 code runs unchanged. Everything below is opt-in.

Each new capability has a runnable example under `examples/` — see the links
throughout.

---

## 1. What you must do

Nothing. Upgrade the gem and your existing code keeps working:

```ruby
gem 'rcrewai', '~> 0.4'
```

---

## 2. What you can do (new capabilities)

### 2a. Per-agent LLM

Give each agent its own provider/model instead of only the global default.
Pass a provider symbol, an options hash, or a pre-built client:

```ruby
worker  = RCrewAI::Agent.new(name: 'worker', role: '...', goal: '...',
                             llm: { provider: :openai, model: 'gpt-4o-mini' })
manager = RCrewAI::Agent.new(name: 'manager', role: '...', goal: '...',
                             llm: { provider: :anthropic, model: 'claude-3-opus-20240229' })
```

Omitting `llm:` keeps the global `RCrewAI.configure` behavior. Overrides never
mutate the global configuration.

### 2b. Structured output, guardrails, and file output

Post-process a task's result after the agent produces it:

```ruby
task = RCrewAI::Task.new(
  name: 'extract', description: '...', agent: agent,

  # Validate & coerce against a JSON schema. Non-conforming output re-runs the
  # agent with the error fed back. Parsed object on task.structured_output.
  output_schema: { type: 'object', properties: { title: { type: 'string' } },
                   required: ['title'] },

  # Validate & transform. ->(output) { [ok, value_or_error] }. Retries up to
  # guardrail_max_retries (default 3) with the reason fed back to the agent.
  guardrail: ->(out) { [out.length < 5000, 'too long'] },

  # Persist the result (parent dirs created unless create_directory: false).
  output_file: 'out/report.md', markdown: true
)

task.execute
task.structured_output  # => { "title" => "..." }
task.raw_result         # => the unprocessed string the agent produced
```

See `examples/structured_output_example.rb`.

### 2c. Knowledge (RAG)

Ground agents in your own documents. Sources are chunked, embedded, and stored
in an in-memory cosine vector store; relevant chunks are injected into each
task's prompt automatically.

```ruby
kb = RCrewAI::Knowledge::Base.new(sources: [
  RCrewAI::Knowledge::StringSource.new('Refunds within 30 days.'),
  RCrewAI::Knowledge::FileSource.new('docs/policy.txt'),
  RCrewAI::Knowledge::PdfSource.new('handbook.pdf'),
  RCrewAI::Knowledge::UrlSource.new('https://example.com/faq')
])

# Agent-level (role-specific):
agent = RCrewAI::Agent.new(name: 'support', role: '...', goal: '...', knowledge: kb)

# Or pass raw sources and let the agent build the base:
agent = RCrewAI::Agent.new(name: 'support', role: '...', goal: '...',
                           knowledge_sources: [RCrewAI::Knowledge::StringSource.new('...')])

# Crew-level knowledge is shared with every agent:
crew = RCrewAI::Crew.new('support', knowledge: kb)
```

Embeddings default to OpenAI's `text-embedding-3-small`; pass a custom
`embedder:` (anything responding to `embed(texts)`) to swap the backend.
See `examples/knowledge_rag_example.rb`.

### 2d. Planning

Have a planner pass draft a per-task plan before execution:

```ruby
crew = RCrewAI::Crew.new('research_crew', planning: true)
# Optionally use a dedicated (stronger) planner model:
crew = RCrewAI::Crew.new('research_crew', planning: true,
                         planning_llm: { provider: :anthropic, model: 'claude-3-opus-20240229' })
```

The plan is folded into each task's description. Planning is best-effort: a
planner error or unparseable output leaves tasks unchanged.

### 2e. Training & testing

Iterate on a crew with feedback, or score repeated runs:

```ruby
# Run N times, collect feedback after each run, persist to JSON.
crew.train(n_iterations: 3, filename: 'training.json')

# Provide feedback programmatically instead of prompting a human:
crew.train(n_iterations: 3, filename: 'training.json',
           feedback: ->(iteration, result) { "run #{iteration}: #{result[:success_rate]}%" })

# Run N times and score each run (defaults to success_rate).
crew.test(n_iterations: 5)
# => { iterations: 5, scores: [...], average_score: 92.0 }
```

See `examples/planning_and_training_example.rb`.

### 2f. Flows

Flows are an event-driven workflow engine — the biggest addition in 0.4.
Subclass `RCrewAI::Flow` and wire methods with a class-level DSL:

```ruby
class ArticleFlow < RCrewAI::Flow
  start :outline
  def outline
    state.sections = %w[intro body conclusion]
    state.sections.length
  end

  listen :outline
  def draft(section_count)
    state.words = section_count * 100
    state.words
  end

  router :draft
  def review(words)
    words >= 250 ? :publish : :expand
  end

  listen :publish
  def publish = state.status = 'published'

  listen :expand
  def expand = state.status = 'needs more work'
end

flow = ArticleFlow.new
flow.kickoff(inputs: { author: 'me' })
flow.state.status   # => "published"
```

- `start` / `listen` / `router` wire methods into a graph; a listener receives
  its trigger's return value, and a router's return becomes a label listeners
  fire on.
- Combine triggers with `and_(:a, :b)` (all) and `or_(:a, :b)` (any).
- **State** is a schemaless object with a UUID, seedable via `kickoff(inputs:)`.
- **Persistence**: pass `state_store:`
  (`RCrewAI::Flow::FileStateStore.new(dir)` or your own `#save`/`#load`) and
  call `flow.restore(id)` to resume.
- Invoke a `Crew` inside any step, or pause with `human_feedback('Approve?')`.

See `examples/flow_example.rb`.

---

## When to use Flows vs. Crews

- **Crew** — a team of agents collaborating on a set of tasks (sequential,
  hierarchical, or async). Reach for a crew when the work is "have these agents
  produce these outputs."
- **Flow** — explicit, branching orchestration with state. Reach for a flow
  when you need conditional paths, joins, persistence/resumption, or you want to
  coordinate multiple crews and plain Ruby steps.

They compose: a Flow step can kick off a Crew.
