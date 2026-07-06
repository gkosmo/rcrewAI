# Cognitive Memory: Semantic, Persistent, Multi-Type Agent Memory

**Date:** 2026-07-06
**Status:** Approved design (pending implementation)
**Target version:** `rcrewai` 0.6.0 (current is 0.5.0)
**Scope:** Replace the placeholder `RCrewAI::Memory` with a cognitive memory system modeled on CrewAI's memory taxonomy — short-term (semantic recent recall), long-term (persistent insights), entity memory, and tool-usage memory — backed by embeddings and a persistent SQLite vector store. No new external dependencies; reuses the in-repo `Knowledge::Embedder` and cosine-search infrastructure.

---

## Motivation

The current `RCrewAI::Memory` is a placeholder. It matches "relevant" past executions with word-overlap similarity (`common_words / total_words`) plus a hardcoded keyword/stopword list and a `classify_task_type` that greps the description for words like "research" or "write". Nothing is embedded; nothing is persisted; everything is lost when the process exits. It is the weakest module in the codebase and it undercuts the framework's core promise — agents that learn from what they've done.

Meanwhile CrewAI has advanced *past* the version this project ported: its 2026 "cognitive memory" work adds semantic recall, distinct memory types (short-term, long-term, entity), and persistence. This is genuine parity work, not gold-plating — and the infrastructure to do it well already exists in-repo (`Knowledge::Embedder`, cosine `Knowledge::Store`), so we compose rather than build from scratch.

## Goals

1. **Semantic recall.** Replace word-overlap with embedding-based similarity so an agent recalls conceptually related past work, not just keyword-overlapping work.
2. **Persistence.** Memory survives process restarts via a SQLite-backed vector store (no external service).
3. **Memory types.** Model CrewAI's taxonomy: short-term, long-term, entity, and tool-usage memory, each with clear write/read semantics.
4. **Backward compatibility.** The existing `Memory` public API (`add_execution`, `add_tool_usage`, `relevant_executions`, `tool_usage_for`, `clear_*!`, `stats`) keeps working, so `Agent` and the runners need no changes to function.
5. **No new hard dependencies.** SQLite via Ruby's stdlib-adjacent `sqlite3` gem (already common in Ruby projects) — but the store is pluggable, and the default remains in-memory so the gem works with zero setup.

## Non-goals

- External vector databases (Chroma/Qdrant/pgvector). The pluggable store interface leaves room for them later; we ship SQLite + in-memory.
- Reranking, query rewriting, or summarization of memories (CrewAI has some of this; it's a follow-up).
- Multi-tenant / shared cross-agent memory servers.

## Decisions captured during brainstorming

| # | Decision | Choice |
|---|----------|--------|
| 1 | Similarity mechanism | Embeddings + cosine, reusing `Knowledge::Embedder` and the cosine math already in `Knowledge::Store`. |
| 2 | Persistence | Pluggable vector store; ship `InMemoryStore` (default) and `SqliteStore`. |
| 3 | Memory taxonomy | Four types: `ShortTermMemory`, `LongTermMemory`, `EntityMemory`, `ToolMemory`. |
| 4 | Backward compat | Keep the `Memory` facade and its current method signatures; delegate internally to the new types. |
| 5 | Default behavior | Zero-config: in-memory store, embeddings only if an embedder is available/keyed; graceful fallback to the current lexical similarity when no embedder. |
| 6 | Embedding failures | Never fatal. If embedding fails (no key, network), fall back to lexical similarity so agents still run. |
| 7 | Namespacing | Memories are scoped by agent (role/name) so one agent's memory doesn't leak into another, matching CrewAI's per-role collections. |

## Architecture

```
RCrewAI::Memory  (facade — preserves today's public API)
  ├── ShortTermMemory   recent executions, semantic recall, capped, volatile-by-default
  ├── LongTermMemory    durable insights from successful executions, persistent
  ├── EntityMemory      facts about entities (people, systems, concepts) extracted from work
  └── ToolMemory        tool-call history + outcomes (replaces @tool_usage)

Each memory type holds:
  - a VectorStore  (InMemoryStore | SqliteStore)   ← persistence + search
  - an Embedder    (Knowledge::Embedder | nil)     ← semantic vectors
  - a lexical fallback (current word-overlap)       ← when no embedder
```

### Storage: `Memory::VectorStore`

A small interface (mirrors `Knowledge::Store` so they can converge later):

```ruby
store.add(id:, text:, vector:, metadata:)   # upsert a record
store.search(vector, k:, scope:)            # cosine top-k, filtered by scope
store.all(scope:)                           # enumerate (for stats / lexical fallback)
store.delete(scope:)                        # clear a scope
```

- **`InMemoryStore`** — array of records; cosine in Ruby (lift the existing private cosine out of `Knowledge::Store` into a shared `Similarity` helper). Default.
- **`SqliteStore`** — one row per memory: `id, scope, type, text, vector (blob), metadata (json), created_at`. Vectors stored as packed floats (`Array#pack('e*')`). Cosine computed in Ruby over candidate rows filtered by `scope`/`type` (fine for the thousands-of-memories scale agents produce; a real ANN index is a later optimization). Opened at a configurable path (default `~/.rcrewai/memory.db` or `:memory:`).

### Embeddings

Reuse `Knowledge::Embedder`. The memory system takes an optional `embedder:`; when present, `add_*` embeds the text and stores the vector, and recall embeds the query. When absent (no key, or explicitly disabled), the store keeps `vector: nil` and recall falls back to the current lexical similarity over `store.all`. This keeps the zero-config path working.

### The four memory types

- **ShortTermMemory** — every execution is written here; recall returns the top-k semantically similar recent items. Capped (default 100) and, by default, uses the in-memory store (volatile). This is the direct upgrade of today's `@short_term` + `relevant_executions`.
- **LongTermMemory** — successful executions promote a distilled "insight" record (task type, what worked, result summary) into a persistent store, deduped by similarity so we don't store near-identical insights repeatedly. Upgrade of today's `@long_term`.
- **EntityMemory** — optional lightweight entity extraction (heuristic first: capitalized noun phrases / quoted terms; pluggable LLM extractor later) so agents accumulate facts about recurring entities. New capability.
- **ToolMemory** — replaces `@tool_usage`; same API (`add_tool_usage`, `tool_usage_for`) but persistable and searchable.

### Facade: `RCrewAI::Memory`

Keeps today's signatures, delegating to the types:

```ruby
Memory.new(embedder: nil, store: nil, scope: nil, short_term_limit: 100)

add_execution(task, result, execution_time)   # -> ShortTerm + (if success) LongTerm + Entity
add_tool_usage(tool_name, params, result)      # -> ToolMemory
relevant_executions(task, limit = 3)           # -> semantic recall across Short+Long, formatted string|nil
tool_usage_for(tool_name, limit = 5)           # -> ToolMemory
clear_short_term! / clear_all! / stats         # -> delegate
```

`Agent#initialize` gains optional `memory:` config (embedder/store/persistence) but defaults to the zero-config in-memory, lexical-fallback behavior — so existing code is unchanged.

## Backward compatibility & migration

- The `Memory` public API is preserved exactly; `agent.rb` and the runners are untouched functionally.
- Default construction (`Memory.new` with no args) behaves like today from the caller's perspective — just with better recall when an embedder is configured, and identical lexical recall when not.
- `relevant_executions` still returns the same formatted-string-or-nil shape consumed at `agent.rb:241`.

## Testing strategy

- **Unit**: each memory type with a fake deterministic embedder (as `knowledge_spec.rb` already does) — assert semantic recall ranks the conceptually-closest item first, not the keyword-overlapping one.
- **Persistence**: `SqliteStore` round-trip — write memories, reopen the DB, recall survives.
- **Fallback**: with no embedder, recall still returns results via lexical similarity (proves the graceful path).
- **Facade compat**: the existing `memory_spec.rb` expectations continue to pass (or are updated only where the placeholder behavior was clearly a bug).
- **Agent integration**: an agent with `reasoning`/knowledge off recalls a semantically-related prior execution injected into its context.

## Dependencies

- `sqlite3` gem — added as a runtime dependency, but only required lazily inside `SqliteStore` so the gem loads and the in-memory path works even if it's absent. (If we'd rather avoid the dependency entirely, the fallback is a JSON-file-backed store; SQLite is preferred for query/scale.)

## Rollout

Ship in `0.6.0`. `docs/upgrading-to-0.6.md` documents opt-in persistence and embeddings; the default path is unchanged, so it's a no-action upgrade for existing users.
