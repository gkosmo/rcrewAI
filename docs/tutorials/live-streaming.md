---
layout: tutorial
title: Live Streaming
description: Stream Anthropic replies with cancellation, connection reuse, per-call models and cached token counts
---

# Live Streaming

These features are for real-time callers such as voice agents, where a reply may need
to stop as soon as the user interrupts. They work on the Anthropic client's `chat`
method, not through `crew.execute`.

```ruby
client = RCrewAI::LLMClient.for_provider(:anthropic)
token = RCrewAI::CancelToken.new

begin
  client.chat(
    messages: [{ role: 'user', content: 'Tell me a story' }],
    model: 'claude-haiku-5-5', # for this call only
    cancel: token,
    stream: lambda do |event|
      print event.text if event.is_a?(RCrewAI::Events::TextDelta)
    end
  )
rescue RCrewAI::StreamCancelled
  puts '(interrupted)'
end
```

## Cancelling

Call `token.cancel!` from the stream callback, another thread or another fiber. The
stream stops at the next chunk, the connection closes, and the caller gets
`RCrewAI::StreamCancelled`. Inside an Async reactor, stopping the calling task does the
same.

## Connection reuse

Streaming requests from one client share a keep-alive connection, so back-to-back turns
skip TCP and TLS setup. Reuse the client between turns to get this. Streaming doesn't
block other fibers inside an Async reactor on Ruby 3.2 or later.

## Cached tokens

`usage[:cached_tokens]` in the result, and `cached_tokens` on the `Usage` event, report
Anthropic's `cache_read_input_tokens`.

## Custom endpoint

The Anthropic client uses `config.base_url` when it's set, for example to go through a
gateway.
