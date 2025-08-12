---
layout: api
title: Tools System
description: Comprehensive guide to RCrewAI's tool system and built-in tools
---

# Tools System

RCrewAI's tool system allows agents to interact with external systems, APIs, files, and perform specialized tasks. Tools extend agent capabilities beyond just generating text.

## Overview

Tools in RCrewAI are:
- **Secure**: Built-in security controls and validation
- **Extensible**: Easy to create custom tools
- **Integrated**: Seamlessly work with agent reasoning
- **Robust**: Error handling and recovery mechanisms

## Built-in Tools

### WebSearch

Search the web for information using DuckDuckGo.

```ruby
search_tool = RCrewAI::Tools::WebSearch.new(max_results: 10, timeout: 30)

# Agent usage
agent = RCrewAI::Agent.new(
  name: "researcher",
  role: "Research Analyst", 
  goal: "Find information on any topic",
  tools: [search_tool]
)
```

**Parameters:**
- `query` (required): Search query string
- `max_results` (optional): Maximum number of results (default: 5)

**Example Agent Usage:**
```
Agent reasoning: "I need to research AI trends"
Agent action: USE_TOOL[websearch](query=AI trends 2024, max_results=5)
```

**Features:**
- No API key required (uses DuckDuckGo)
- Extracts titles, URLs, and snippets
- Handles rate limiting and errors
- Clean, formatted results

### FileReader

Read contents from files with security controls.

```ruby
reader_tool = RCrewAI::Tools::FileReader.new(
  max_file_size: 5_000_000,  # 5MB limit
  allowed_extensions: %w[.txt .md .json .csv .log]
)

agent = RCrewAI::Agent.new(
  name: "analyst",
  role: "Data Analyst",
  goal: "Analyze file contents",
  tools: [reader_tool]
)
```

**Parameters:**
- `file_path` (required): Path to file to read
- `encoding` (optional): File encoding (default: utf-8)
- `lines` (optional): Read only N lines

**Security Features:**
- File size limits
- Extension restrictions
- Directory traversal protection  
- Working directory enforcement

**Example Usage:**
```
USE_TOOL[filereader](file_path=data.csv, lines=100)
```

### FileWriter

Write content to files with security and validation.

```ruby
writer_tool = RCrewAI::Tools::FileWriter.new(
  max_file_size: 10_000_000,  # 10MB limit
  allowed_extensions: %w[.txt .md .json .csv],
  create_directories: true
)
```

**Parameters:**
- `file_path` (required): Path where to write file
- `content` (required): Content to write
- `mode` (optional): Write mode ('w', 'a', 'w+', etc.)
- `encoding` (optional): File encoding (default: utf-8)

**Example Usage:**
```
USE_TOOL[filewriter](file_path=report.md, content=## Report\nThis is my analysis...)
```

**Security Features:**
- Content size validation
- Path traversal protection
- Extension restrictions
- Automatic directory creation

## Creating Custom Tools

### Basic Custom Tool

```ruby
class MyCustomTool < RCrewAI::Tools::Base
  def initialize(**options)
    super()
    @name = 'mycustomtool'
    @description = 'Description of what this tool does'
    @api_key = options[:api_key]
  end

  def execute(**params)
    validate_params!(params, required: [:input], optional: [:format])
    
    input = params[:input]
    format = params[:format] || 'json'
    
    begin
      # Your tool logic here
      result = process_input(input, format)
      format_result(result)
    rescue => e
      "Tool execution failed: #{e.message}"
    end
  end

  private

  def process_input(input, format)
    # Implement your tool logic
    "Processed: #{input} in #{format} format"
  end

  def format_result(result)
    result.to_s
  end
end
```

### Advanced Custom Tool Example

```ruby
class APIClientTool < RCrewAI::Tools::Base
  def initialize(**options)
    super()
    @name = 'apiclient'
    @description = 'Make HTTP requests to APIs'
    @base_url = options[:base_url]
    @api_key = options[:api_key]
    @timeout = options.fetch(:timeout, 30)
  end

  def execute(**params)
    validate_params!(
      params, 
      required: [:endpoint, :method], 
      optional: [:data, :headers]
    )
    
    endpoint = params[:endpoint]
    method = params[:method].upcase
    data = params[:data]
    headers = params[:headers] || {}

    # Add authentication
    headers['Authorization'] = "Bearer #{@api_key}" if @api_key
    headers['Content-Type'] = 'application/json'

    begin
      response = make_request(method, endpoint, data, headers)
      format_api_response(response)
    rescue => e
      "API request failed: #{e.message}"
    end
  end

  private

  def make_request(method, endpoint, data, headers)
    url = "#{@base_url}#{endpoint}"
    
    http_client = Faraday.new do |f|
      f.adapter Faraday.default_adapter
      f.options.timeout = @timeout
    end

    case method
    when 'GET'
      http_client.get(url, data, headers)
    when 'POST'
      http_client.post(url, data&.to_json, headers)
    when 'PUT'
      http_client.put(url, data&.to_json, headers)
    when 'DELETE'
      http_client.delete(url, data, headers)
    else
      raise ToolError, "Unsupported HTTP method: #{method}"
    end
  end

  def format_api_response(response)
    result = "Status: #{response.status}\n"
    result += "Headers: #{response.headers.to_h}\n"
    result += "Body: #{response.body}"
    result
  end
end
```

## Tool Integration Patterns

### Agent with Multiple Tools

```ruby
# Create specialized tools
search_tool = RCrewAI::Tools::WebSearch.new
file_reader = RCrewAI::Tools::FileReader.new
file_writer = RCrewAI::Tools::FileWriter.new
api_client = APIClientTool.new(base_url: 'https://api.example.com', api_key: ENV['API_KEY'])

# Agent with comprehensive toolkit
agent = RCrewAI::Agent.new(
  name: "multi_tool_agent",
  role: "Full-Stack AI Assistant",
  goal: "Handle any task requiring web research, file operations, or API calls",
  tools: [search_tool, file_reader, file_writer, api_client],
  verbose: true,
  max_iterations: 10
)
```

### Task-Specific Tools

```ruby
# Research task with web search
research_task = RCrewAI::Task.new(
  name: "market_research",
  description: "Research competitor pricing and features",
  agent: researcher_agent,
  tools: [RCrewAI::Tools::WebSearch.new(max_results: 15)]  # Task-specific tool
)

# Analysis task with file operations
analysis_task = RCrewAI::Task.new(
  name: "data_analysis",
  description: "Analyze data files and generate report",
  agent: analyst_agent,
  tools: [
    RCrewAI::Tools::FileReader.new(allowed_extensions: %w[.csv .json .xlsx]),
    RCrewAI::Tools::FileWriter.new
  ]
)
```

### Dynamic Tool Loading

```ruby
class ToolManager
  def self.create_tool_set(requirements)
    tools = []
    
    tools << RCrewAI::Tools::WebSearch.new if requirements.include?(:web_search)
    tools << RCrewAI::Tools::FileReader.new if requirements.include?(:file_read)
    tools << RCrewAI::Tools::FileWriter.new if requirements.include?(:file_write)
    
    if requirements.include?(:api_access)
      tools << APIClientTool.new(
        base_url: ENV['API_BASE_URL'],
        api_key: ENV['API_KEY']
      )
    end
    
    tools
  end
end

# Usage
requirements = [:web_search, :file_write, :api_access]
agent_tools = ToolManager.create_tool_set(requirements)

agent = RCrewAI::Agent.new(
  name: "dynamic_agent",
  role: "Adaptive Assistant",
  goal: "Handle tasks based on available tools",
  tools: agent_tools
)
```

## Tool Best Practices

### Security

1. **Validate all inputs**: Use `validate_params!` helper
2. **Limit resource usage**: Set file size, timeout limits
3. **Restrict file access**: Use allowed extensions and path validation
4. **Sanitize outputs**: Clean potentially dangerous content

```ruby
def execute(**params)
  validate_params!(params, required: [:input])
  
  # Sanitize input
  input = params[:input].to_s.strip
  raise ToolError, "Input too long" if input.length > 1000
  
  # Process safely...
end
```

### Error Handling

```ruby
def execute(**params)
  validate_params!(params, required: [:data])
  
  begin
    result = risky_operation(params[:data])
    return result
  rescue APITimeoutError => e
    "Operation timed out: #{e.message}"
  rescue APIRateLimitError => e
    "Rate limit exceeded, try again later"
  rescue => e
    logger.error "Unexpected error in #{@name}: #{e.message}"
    "Tool failed: #{e.message}"
  end
end
```

### Performance

1. **Use connection pooling** for HTTP clients
2. **Cache results** when appropriate
3. **Stream large files** instead of loading entirely
4. **Implement timeouts** for all external calls

### Testing Tools

```ruby
require 'rspec'

RSpec.describe MyCustomTool do
  let(:tool) { MyCustomTool.new(api_key: 'test-key') }

  it 'processes input correctly' do
    result = tool.execute(input: 'test data', format: 'json')
    expect(result).to include('Processed: test data')
  end

  it 'validates required parameters' do
    expect {
      tool.execute(format: 'json')  # Missing required 'input'
    }.to raise_error(RCrewAI::Tools::ToolError)
  end

  it 'handles errors gracefully' do
    allow(tool).to receive(:process_input).and_raise(StandardError.new('API down'))
    result = tool.execute(input: 'test')
    expect(result).to include('Tool execution failed')
  end
end
```

## Available Tool Registry

```ruby
# List all available tool classes
puts RCrewAI::Tools::Base.available_tools

# Create tool by name
search_tool = RCrewAI::Tools::Base.create_tool('websearch', max_results: 10)
```

## Tool Debugging

Enable verbose logging to see tool usage:

```ruby
agent = RCrewAI::Agent.new(
  name: "debug_agent",
  role: "Test Agent",
  goal: "Test tool usage",
  tools: [RCrewAI::Tools::WebSearch.new],
  verbose: true  # Shows tool calls and results
)
```

Tool usage will be logged as:
```
DEBUG Using tool: websearch with params: {:query=>"AI trends", :max_results=>5}
DEBUG Tool websearch result: Search Results:
1. Latest AI Trends 2024
   URL: https://example.com/ai-trends
   Recent developments in artificial intelligence...
```