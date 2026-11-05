# Upgrading to RCrewAI 0.8 through 0.11

These releases are almost entirely additive. To see what's new, read the tutorials on
[providers](tutorials/providers.md), [checkpointing](tutorials/checkpointing.md),
[interceptors and events](tutorials/interceptors-and-events.md),
[concurrency](tutorials/concurrency.md) and [live streaming](tutorials/live-streaming.md).

## Check these

**Tools now run in parallel (0.9).** If a model requests several tools in one turn, they
run concurrently. If your tools share state and aren't thread-safe, or call a
rate-limited API, set `parallel_tools: false` on those agents.

**Subclasses overriding `execute_task` (since 0.7.1).** The method is now called with a
`stream:` keyword, so `def execute_task(task)` fails with `wrong number of arguments`:

```ruby
def execute_task(task, stream: nil, **opts)
  super
end
```

**Stream subscribers (0.8).** Delivery is now serialized, so a subscriber's own mutex is
no longer needed. Keeping it is harmless.

**Dropped dependencies (0.8.1).** `anthropic`, `ruby-openai` and `faraday-multipart` are
no longer installed with the gem. If your app uses them directly, add them to your
Gemfile.

## 0.11

**Agents with tools should start working on real providers,** and this release changes how configuration resolves. Check these:

- **`config.model` now takes effect.** It used to be ignored on `:openai`, `:anthropic`,
  `:google` and `:azure`. If you set it, check that it names the model you want, because
  you may have been running on a default.
- **`:ollama`, `:openai_compatible`, `:bedrock` and `:snowflake` now need a model.**
  Without one they raise `ConfigurationError` rather than sending `gpt-4`.
- **`:ollama` no longer needs an API key,** so you can remove any placeholder key.
- **`:openai_responses` now uses `openai_model`.** It always sent `gpt-4` before.

It also updates Anthropic support for current Claude models:

- **Anthropic no longer receives the default `temperature`.** Only a value you set is
  sent. If you set `config.temperature` and use current Claude models, remove it or clear
  it per agent with `llm: { provider: :anthropic, temperature: nil }`.
- **Tool calls now use each provider's real format.** Before, requests after a tool call
  were malformed on every provider. Agents with tools should start working, so check any
  retries or workarounds you added for those failures.
- **The default models changed.** `:anthropic` now defaults to `claude-opus-5-5` and
  `:google` to `gemini-3.8-flash`. If you rely on a default, check the cost and output, or
  set a model explicitly. Claude prices in the built-in table were also corrected, so
  reported costs may change.
- **Delegation and answer revision no longer pass `temperature: 0.2`.** On other providers
  they now use your configured temperature.
