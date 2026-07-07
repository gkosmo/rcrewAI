---
layout: tutorial
title: Flows — Event-Driven Workflows
description: Build structured, stateful workflows with start/listen/router, combinators, and persistence
---

# Flows

Crews are great for "have these agents produce these outputs." **Flows** are the
second orchestration pillar — for workflows that need explicit branching, joins,
persistent state, or coordination across multiple crews and plain Ruby steps.

Subclass `RCrewAI::Flow` and wire methods together with a class-level DSL.

## A first flow

```ruby
require 'rcrewai'

class ArticleFlow < RCrewAI::Flow
  start :outline
  def outline
    state.sections = %w[intro body conclusion]
    state.sections.length          # return value is passed to listeners of :outline
  end

  listen :outline
  def draft(section_count)
    state.words = section_count * 100
    state.words
  end

  router :draft
  def review(words)
    words >= 250 ? :publish : :expand   # a router returns a label
  end

  listen :publish
  def publish = state.status = 'published'

  listen :expand
  def expand = state.status = 'needs more work'
end

flow = ArticleFlow.new
flow.kickoff(inputs: { author: 'Ada' })
flow.state.status   # => "published"
flow.state.id       # => automatic UUID
```

## The DSL

- **`start :method`** — an entry point. A flow can have several; all run first.
- **`listen :trigger`** — runs the following method after `:trigger` completes,
  receiving its return value.
- **`router :trigger`** — like `listen`, but the method's return value becomes a
  **label** that other `listen` methods can trigger on. This is how you branch.

### Combining triggers

```ruby
listen and_(:fetch_a, :fetch_b)   # fires once, after BOTH complete
def merge(...); end

listen or_(:cache_hit, :cache_miss)  # fires when EITHER completes
def proceed(...); end
```

## State

`state` is a schemaless object with an automatic UUID. Read and write attributes
directly (`state.foo = 1`), and seed initial values via `kickoff(inputs:)`:

```ruby
flow.kickoff(inputs: { topic: 'ruby', max_words: 800 })
flow.state.topic       # => "ruby"
```

## Persistence — pause and resume

Pass a `state_store:` and a flow's state is saved after each run, so you can
restore it later by id:

```ruby
store = RCrewAI::Flow::FileStateStore.new('tmp/flows')  # or your own #save/#load
flow  = ArticleFlow.new(state_store: store)
flow.kickoff
id = flow.state.id

# ...later, even in a fresh process...
resumed = ArticleFlow.new(state_store: store)
resumed.restore(id)
resumed.state.status   # => recovered
```

Built-in stores: `RCrewAI::Flow::MemoryStateStore` (volatile) and
`RCrewAI::Flow::FileStateStore` (JSON on disk). Any object responding to
`#save(id, hash)` / `#load(id)` works.

## Running a crew inside a flow

A flow step is just a method, so it can kick off a whole crew:

```ruby
class ResearchFlow < RCrewAI::Flow
  def initialize(crew:, **opts)
    super(**opts)
    @crew = crew
  end

  start :run
  def run
    state.crew_result = @crew.execute(inputs: { topic: state.topic })
  end
end
```

## Human feedback

Pause a flow for input with `human_feedback`:

```ruby
listen :draft
def approve(_draft)
  state.approved = human_feedback('Approve this draft?')
end
```

Provide a handler for non-interactive runs:
`ArticleFlow.new(feedback_handler: ->(prompt) { auto_approve(prompt) })`.

## Runnable example

See [`examples/flow_example.rb`](https://github.com/gkosmo/rcrewAI/blob/main/examples/flow_example.rb)
— it runs without an API key.
