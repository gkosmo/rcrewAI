---
layout: tutorial
title: LLM Providers
description: Configure OpenAI, Anthropic, Google, Azure, Ollama, Bedrock, Snowflake Cortex, OpenAI-compatible endpoints and the Responses API
---

# LLM Providers

RCrewAI has nine providers behind one interface. You choose one globally with
`config.llm_provider`, and any agent can override it.

| `llm_provider` | Needs | API key from |
|---|---|---|
| `:openai` | | `OPENAI_API_KEY` |
| `:openai_responses` | | `OPENAI_API_KEY` |
| `:anthropic` | | `ANTHROPIC_API_KEY` or `CLAUDE_API_KEY` |
| `:google` | | `GOOGLE_API_KEY` or `GEMINI_API_KEY` |
| `:azure` | `base_url`, `deployment_name`, `api_version` | `AZURE_OPENAI_API_KEY` |
| `:ollama` | a model | none |
| `:openai_compatible` | `base_url`, a model | `config.api_key` or `LLM_API_KEY` |
| `:bedrock` | `aws_region`, a model | `config.api_key` or `LLM_API_KEY` |
| `:snowflake` | `snowflake_account`, a model | `config.api_key` or `LLM_API_KEY` |

## Examples

```ruby
# OpenAI
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_model = 'gpt-4o'
end

# Anthropic
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.anthropic_model = 'claude-opus-5-5'
  config.temperature = nil # current Claude models reject temperature
end

# Google
RCrewAI.configure do |config|
  config.llm_provider = :google
  config.google_model = 'gemini-2.5-flash'
end

# Azure OpenAI
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.base_url = 'https://your-resource.openai.azure.com/'
  config.deployment_name = 'your-deployment'
  config.api_version = '2024-10-21'
end

# Ollama (local, no key). Set OLLAMA_HOST or config.base_url if it isn't on
# http://localhost:11434.
RCrewAI.configure do |config|
  config.llm_provider = :ollama
  config.model = 'llama3.1'
end

# Any endpoint speaking OpenAI Chat Completions:
# Together, Groq, Fireworks, vLLM, LiteLLM, OpenRouter, your own gateway
RCrewAI.configure do |config|
  config.llm_provider = :openai_compatible
  config.base_url = 'https://api.groq.com/openai/v1'
  config.api_key = ENV['GROQ_API_KEY']
  config.model = 'your-model'
end

# AWS Bedrock (Converse API)
RCrewAI.configure do |config|
  config.llm_provider = :bedrock
  config.aws_region = 'us-east-1' # or AWS_REGION / AWS_DEFAULT_REGION
  config.api_key = ENV['BEDROCK_API_KEY']
  config.model = 'your-bedrock-model-id'
end

# Snowflake Cortex
RCrewAI.configure do |config|
  config.llm_provider = :snowflake
  config.snowflake_account = 'your-account' # or SNOWFLAKE_ACCOUNT
  config.api_key = ENV['SNOWFLAKE_TOKEN']
  config.model = 'your-cortex-model'
end
```

## Provider limitations

- **Anthropic and `temperature`:** the client sends `config.temperature`, which
  defaults to `0.1`, and current Claude models reject it. Set
  `config.temperature = nil` to leave it out.
- **Bedrock auth:** `api_key` is sent as a bearer token, which covers Bedrock API
  keys and gateways in front of Bedrock. SigV4 signing isn't built in; you can sign
  requests yourself in a [`before_request` hook]({{ site.baseurl }}/tutorials/interceptors-and-events).
- **Responses API:** `:openai_responses` doesn't stream. It shares `openai_model`
  and `openai_api_key` with `:openai`.
- **Live streaming features:** `cancel:` and `cached_tokens` are Anthropic-only. See
  [Live Streaming]({{ site.baseurl }}/tutorials/live-streaming).

## Per-agent overrides

```ruby
writer = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write',
                            llm: :anthropic) # provider only

analyst = RCrewAI::Agent.new(name: 'analyst', role: 'Analyst', goal: 'Analyze',
                             llm: { provider: :openai, model: 'gpt-4o-mini', temperature: 0.2 })
```

`llm:` also takes a pre-built client. An override never changes the global
configuration.

An override inherits the global `temperature`, and passing `temperature: nil` doesn't
clear it. To use a current Claude model on one agent, set `config.temperature = nil`
globally, then give each agent that needs a temperature its own value.
