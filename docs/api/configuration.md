---
layout: api
title: RCrewAI::Configuration
description: Configuration system for LLM providers and settings
---

# RCrewAI::Configuration

The Configuration class manages settings for various LLM providers and global options for RCrewAI.

## Supported Providers

RCrewAI supports the following LLM providers:

- **OpenAI** (GPT-4, GPT-3.5-turbo, etc.)
- **Anthropic** (Claude 3, Claude 2, etc.)
- **Google** (Gemini Pro, PaLM, etc.)
- **Azure OpenAI** (Azure-hosted OpenAI models)
- **Ollama** (Local/self-hosted models)

## Basic Configuration

### Using Environment Variables (Recommended)

Set your API keys as environment variables:

```bash
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export GOOGLE_API_KEY="your-google-key"
export AZURE_OPENAI_API_KEY="your-azure-key"
```

Then configure RCrewAI:

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :openai  # or :anthropic, :google, :azure, :ollama
end
```

### Direct Configuration

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_api_key = "your-openai-key"
  config.openai_model = "gpt-4"
  config.temperature = 0.1
  config.max_tokens = 4000
end
```

## Provider-Specific Configuration

### OpenAI

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.openai_model = 'gpt-4'  # or 'gpt-3.5-turbo', 'gpt-4-turbo'
  config.temperature = 0.1
  config.max_tokens = 4000
end
```

**Available Models:**
- `gpt-4`
- `gpt-4-turbo`
- `gpt-3.5-turbo`
- `gpt-3.5-turbo-16k`

### Anthropic (Claude)

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.anthropic_model = 'claude-3-sonnet-20240229'
  config.temperature = 0.1
  config.max_tokens = 4000
end
```

**Available Models:**
- `claude-3-opus-20240229`
- `claude-3-sonnet-20240229`
- `claude-3-haiku-20240307`
- `claude-2.1`
- `claude-2.0`

### Google (Gemini)

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :google
  config.google_api_key = ENV['GOOGLE_API_KEY']
  config.google_model = 'gemini-pro'
  config.temperature = 0.1
  config.max_tokens = 4000
end
```

**Available Models:**
- `gemini-pro`
- `gemini-pro-vision`
- `text-bison-001`

### Azure OpenAI

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.azure_api_key = ENV['AZURE_OPENAI_API_KEY']
  config.base_url = "https://your-resource.openai.azure.com/"
  config.api_version = "2023-05-15"
  config.deployment_name = "your-deployment-name"
  config.azure_model = 'gpt-4'
end
```

### Ollama (Local Models)

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :ollama
  config.base_url = "http://localhost:11434"  # Default Ollama URL
  config.model = "llama2"  # or any installed Ollama model
  config.temperature = 0.1
end
```

## Configuration Methods

### `RCrewAI.configure`

Configure RCrewAI with a block:

```ruby
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.temperature = 0.2
  config.max_tokens = 2000
end
```

### `RCrewAI.configuration`

Access the current configuration:

```ruby
config = RCrewAI.configuration
puts config.llm_provider  # => :openai
puts config.model         # => "gpt-4"
```

### `RCrewAI.reset_configuration!`

Reset configuration to defaults:

```ruby
RCrewAI.reset_configuration!
```

## Configuration Options

### Core Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `llm_provider` | Symbol | `:openai` | LLM provider to use |
| `temperature` | Float | `0.1` | Sampling temperature (0.0 - 2.0) |
| `max_tokens` | Integer | `4000` | Maximum tokens in response |
| `timeout` | Integer | `120` | Request timeout in seconds |

### Provider-Specific Keys

| Option | Environment Variable | Description |
|--------|---------------------|-------------|
| `openai_api_key` | `OPENAI_API_KEY` | OpenAI API key |
| `anthropic_api_key` | `ANTHROPIC_API_KEY` | Anthropic API key |
| `google_api_key` | `GOOGLE_API_KEY` | Google API key |
| `azure_api_key` | `AZURE_OPENAI_API_KEY` | Azure OpenAI API key |

### Provider-Specific Models

| Option | Default | Description |
|--------|---------|-------------|
| `openai_model` | `gpt-4` | OpenAI model name |
| `anthropic_model` | `claude-3-sonnet-20240229` | Anthropic model name |
| `google_model` | `gemini-pro` | Google model name |
| `azure_model` | `gpt-4` | Azure OpenAI model name |

### Azure-Specific Settings

| Option | Environment Variable | Description |
|--------|---------------------|-------------|
| `base_url` | `LLM_BASE_URL` | Azure OpenAI endpoint URL |
| `api_version` | `AZURE_API_VERSION` | Azure API version |
| `deployment_name` | `AZURE_DEPLOYMENT_NAME` | Azure deployment name |

## Dynamic Provider Switching

You can switch providers at runtime:

```ruby
# Start with OpenAI
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_api_key = ENV['OPENAI_API_KEY']
end

crew = RCrewAI::Crew.new("test_crew")
# ... create agents and tasks

# Switch to Anthropic for specific tasks
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
end

different_crew = RCrewAI::Crew.new("claude_crew")
# This crew will use Claude models
```

## Environment Variables

RCrewAI automatically loads configuration from environment variables:

```bash
# Provider API Keys
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GOOGLE_API_KEY="AIza..."
export AZURE_OPENAI_API_KEY="..."

# Azure Specific
export AZURE_API_VERSION="2023-05-15"
export AZURE_DEPLOYMENT_NAME="gpt-4-deployment"
export LLM_BASE_URL="https://your-resource.openai.azure.com/"

# General fallback
export LLM_API_KEY="fallback-key"
```

## Configuration Validation

RCrewAI validates configuration when `configure` is called:

```ruby
begin
  RCrewAI.configure do |config|
    config.llm_provider = :invalid_provider
  end
rescue RCrewAI::ConfigurationError => e
  puts "Configuration error: #{e.message}"
end
```

## Multiple Configurations

For applications that need multiple configurations:

```ruby
# Save current config
old_config = RCrewAI.configuration.dup

# Configure for specific task
RCrewAI.configure do |config|
  config.llm_provider = :anthropic
  config.temperature = 0.8
end

# Do work with Claude...

# Restore original config
RCrewAI.reset_configuration!
# Re-apply old config...
```

## Best Practices

1. **Use Environment Variables**: Store API keys in environment variables, not in code
2. **Provider Selection**: Choose providers based on task requirements:
   - OpenAI GPT-4: General-purpose, high quality
   - Claude: Great for analysis and reasoning
   - Gemini: Good for creative tasks
   - Azure: Enterprise requirements
   - Ollama: Privacy-sensitive or offline use
3. **Temperature Settings**: 
   - Low (0.1-0.3): Factual, consistent outputs
   - Medium (0.5-0.7): Balanced creativity and consistency  
   - High (0.8-1.0): Creative, varied outputs
4. **Model Selection**: Use the most capable model your budget allows
5. **Timeout Settings**: Set appropriate timeouts for your use case

## Troubleshooting

### Common Issues

**"API key must be set" Error**
```ruby
# Ensure API key is set
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.openai_api_key = ENV['OPENAI_API_KEY']  # Make sure this env var exists
end
```

**"Unsupported provider" Error**
```ruby
# Check supported providers
puts RCrewAI.configuration.supported_providers
# => [:openai, :anthropic, :google, :azure, :ollama]
```

**Azure Configuration Issues**
```ruby
RCrewAI.configure do |config|
  config.llm_provider = :azure
  config.azure_api_key = ENV['AZURE_OPENAI_API_KEY']
  config.base_url = "https://your-resource.openai.azure.com/"  # Include trailing slash
  config.api_version = "2023-05-15"  # Use supported API version
  config.deployment_name = "your-deployment-name"  # Exact deployment name
end
```