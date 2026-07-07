---
layout: tutorial
title: Knowledge (RAG)
description: Ground agents in your own documents with retrieval-augmented generation
---

# Knowledge (RAG)

Give agents access to your own documents. Sources are chunked, embedded, and
stored in a vector store; at execution time the most relevant chunks are
injected into the agent's task prompt automatically.

## Building a knowledge base

```ruby
require 'rcrewai'

kb = RCrewAI::Knowledge::Base.new(sources: [
  RCrewAI::Knowledge::StringSource.new('Refunds are available within 30 days.'),
  RCrewAI::Knowledge::FileSource.new('docs/policy.txt'),
  RCrewAI::Knowledge::PdfSource.new('handbook.pdf'),
  RCrewAI::Knowledge::CsvSource.new('faq.csv'),
  RCrewAI::Knowledge::UrlSource.new('https://example.com/faq')
])
```

## Attaching knowledge

**Agent-level** (role-specific):

```ruby
support = RCrewAI::Agent.new(
  name: 'support', role: 'Support specialist', goal: 'Answer using company policy',
  knowledge: kb
)

# Or pass raw sources and let the agent build the base:
support = RCrewAI::Agent.new(name: 'support', role: '...', goal: '...',
                             knowledge_sources: [RCrewAI::Knowledge::StringSource.new('...')])
```

**Crew-level** (shared with every agent):

```ruby
crew = RCrewAI::Crew.new('support_crew', knowledge: kb)
```

When a task runs, chunks relevant to the task description are retrieved and added
to the prompt under a "Relevant Knowledge" heading.

## Embeddings — pick a provider

Embeddings default to OpenAI's `text-embedding-3-small`. Since 0.6.1 the embedder
is multi-provider:

```ruby
# Local, no API key:
embedder = RCrewAI::Knowledge::Embedder.new(provider: :ollama, model: 'nomic-embed-text')

# Or :azure / :google. (:anthropic has no embeddings API and raises.)
kb = RCrewAI::Knowledge::Base.new(sources: [...], embedder: embedder)
```

Any object responding to `embed(texts) -> [[float, ...], ...]` can be substituted.

## Chunking and the vector store

`Knowledge::Base.new` accepts `chunk_size:` and `overlap:` to tune how documents
are split. The default vector store is in-memory with cosine similarity; the
store is pluggable if you need a different backend.

```ruby
kb = RCrewAI::Knowledge::Base.new(sources: [...], chunk_size: 800, overlap: 100)
kb.search('what is the refund window?', k: 3)   # => top-k relevant chunks
```

## Runnable example

See [`examples/knowledge_rag_example.rb`](https://github.com/gkosmo/rcrewAI/blob/main/examples/knowledge_rag_example.rb)
— it runs without an API key using a fake embedder.
