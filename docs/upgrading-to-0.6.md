# Upgrading to RCrewAI 0.6

RCrewAI 0.6 replaces the placeholder memory with a **cognitive memory** system:
semantic recall (embeddings + cosine), optional SQLite persistence, and four
memory types (short-term, long-term, entity, tool).

**0.6 is backward compatible.** The `RCrewAI::Memory` public API is unchanged,
and the default (`Memory.new` with no config) behaves like before from the
caller's perspective — just with better recall once an embedder is configured.
Everything below is opt-in.

---

## 1. What you must do

Nothing. Upgrade the gem; existing code keeps working:

```ruby
gem 'rcrewai', '~> 0.6'
```

Note: `0.6` adds `sqlite3` as a runtime dependency (used only if you opt into
persistence). It is required lazily, so the in-memory default works even if the
native extension isn't present.

---

## 2. What you can do (new capabilities)

### 2a. Semantic recall via embeddings

By default, memory recall uses lexical (word-overlap) similarity — same as
before. Pass an embedder to get semantic recall, so an agent remembers
conceptually related work even when the wording differs:

```ruby
embedder = RCrewAI::Knowledge::Embedder.new   # OpenAI text-embedding-3-small
agent = RCrewAI::Agent.new(
  name: 'engineer', role: '...', goal: '...',
  memory: { embedder: embedder }
)
```

If embedding fails (no API key, network error), recall automatically falls back
to lexical similarity — memory never breaks agent execution.

### 2b. Persistent memory (SQLite)

Give memory a SQLite store and it survives restarts:

```ruby
store = RCrewAI::Memory::SqliteStore.new(path: '~/.rcrewai/memory.db')
agent = RCrewAI::Agent.new(
  name: 'engineer', role: '...', goal: '...',
  memory: { embedder: embedder, store: store }
)
```

The default store is in-memory (volatile). Any object implementing the store
interface (`add` / `search` / `all` / `delete` / `delete_record`) can be used —
e.g. a future Chroma/pgvector adapter.

### 2c. Memory scoping

Each agent's memory is scoped to its name by default, so agents sharing a
persistent store don't read each other's memories. Override with
`memory: { scope: 'custom' }` if you want deliberate sharing.

### 2d. Memory types (direct access)

The `Memory` facade exposes the underlying types for advanced use:

```ruby
agent.memory.short_term   # recent executions, semantic recall, capped
agent.memory.long_term    # durable insights from successful executions, deduped
agent.memory.entity       # facts about entities (people, systems) seen in work
agent.memory.tool         # tool-call history + outcomes

agent.memory.entity.entities            # => ["Alice", "AWS", ...]
agent.memory.long_term.recall('...', limit: 3)
```

### 2e. Pre-built Memory

You can also construct and pass a `Memory` directly:

```ruby
memory = RCrewAI::Memory.new(scope: 'shared', embedder: embedder, store: store)
agent  = RCrewAI::Agent.new(name: 'a', role: '...', goal: '...', memory: memory)
```

---

## Behavior notes

- `add_execution` writes to short-term always, and (on success) promotes a
  deduped insight to long-term and extracts entities.
- `relevant_executions(task, limit)` recalls across short- and long-term and
  returns the same formatted-string-or-nil shape as before.
- `clear_short_term!` leaves long-term insights intact; `clear_all!` wipes
  everything.
