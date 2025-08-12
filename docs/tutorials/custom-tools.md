---
layout: tutorial
title: Custom Tools Development
description: Learn how to build custom tools to extend agent capabilities for specialized tasks
---

# Custom Tools Development

This tutorial teaches you how to create custom tools that extend agent capabilities beyond the built-in tools. You'll learn tool architecture, implementation patterns, testing strategies, and best practices.

## Table of Contents
1. [Understanding Tool Architecture](#understanding-tool-architecture)
2. [Creating Basic Custom Tools](#creating-basic-custom-tools)
3. [Advanced Tool Features](#advanced-tool-features)
4. [API Integration Tools](#api-integration-tools)
5. [Database Tools](#database-tools)
6. [File Processing Tools](#file-processing-tools)
7. [Testing Custom Tools](#testing-custom-tools)
8. [Tool Security and Validation](#tool-security-and-validation)

## Understanding Tool Architecture

### Tool Base Class

All tools in RCrewAI inherit from the base Tool class:

```ruby
module RCrewAI
  module Tools
    class Base
      attr_reader :name, :description
      
      def initialize(**options)
        @name = self.class.name.split('::').last.downcase
        @description = "Base tool description"
        @options = options
        @logger = Logger.new($stdout)
      end
      
      def execute(**params)
        raise NotImplementedError, "Subclasses must implement execute method"
      end
      
      def validate_params!(params, required: [], optional: [])
        # Built-in parameter validation
        required.each do |param|
          unless params.key?(param)
            raise ToolError, "Missing required parameter: #{param}"
          end
        end
        
        # Check for unknown parameters
        all_params = required + optional
        params.keys.each do |key|
          unless all_params.include?(key)
            raise ToolError, "Unknown parameter: #{key}"
          end
        end
      end
    end
  end
end
```

### Tool Lifecycle

1. **Initialization**: Tool is created with configuration
2. **Validation**: Parameters are validated before execution
3. **Execution**: Tool performs its function
4. **Result Formatting**: Output is formatted for agent consumption
5. **Error Handling**: Exceptions are caught and handled

## Creating Basic Custom Tools

### Simple Calculator Tool

```ruby
class CalculatorTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'calculator'
    @description = 'Performs mathematical calculations'
    @precision = options[:precision] || 2
  end
  
  def execute(**params)
    validate_params!(params, required: [:operation, :operands])
    
    operation = params[:operation].to_s.downcase
    operands = params[:operands]
    
    # Validate operands
    unless operands.is_a?(Array) && operands.all? { |o| o.is_a?(Numeric) }
      raise ToolError, "Operands must be an array of numbers"
    end
    
    result = case operation
    when 'add', '+'
      operands.sum
    when 'subtract', '-'
      operands.reduce(&:-)
    when 'multiply', '*'
      operands.reduce(&:*)
    when 'divide', '/'
      divide_with_check(operands)
    when 'power', '^'
      operands[0] ** operands[1]
    when 'sqrt'
      Math.sqrt(operands[0])
    when 'average'
      operands.sum.to_f / operands.length
    else
      raise ToolError, "Unknown operation: #{operation}"
    end
    
    format_result(result)
  end
  
  private
  
  def divide_with_check(operands)
    if operands[1..-1].any? { |o| o == 0 }
      raise ToolError, "Division by zero"
    end
    operands.reduce(&:/)
  end
  
  def format_result(result)
    if result.is_a?(Float)
      "Result: #{result.round(@precision)}"
    else
      "Result: #{result}"
    end
  end
end

# Usage with an agent
calculator = CalculatorTool.new(precision: 4)

agent = RCrewAI::Agent.new(
  name: "math_agent",
  role: "Mathematics Specialist",
  goal: "Solve mathematical problems",
  tools: [calculator]
)

# Agent can now use: USE_TOOL[calculator](operation=multiply, operands=[5, 3, 2])
```

### Weather Information Tool

```ruby
require 'net/http'
require 'json'

class WeatherTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'weather'
    @description = 'Get current weather information for any location'
    @api_key = options[:api_key] || ENV['WEATHER_API_KEY']
    @base_url = 'https://api.openweathermap.org/data/2.5'
    @units = options[:units] || 'metric'  # metric, imperial, kelvin
  end
  
  def execute(**params)
    validate_params!(params, required: [:location], optional: [:forecast])
    
    location = params[:location]
    forecast = params[:forecast] || false
    
    begin
      if forecast
        get_forecast(location)
      else
        get_current_weather(location)
      end
    rescue => e
      "Weather service error: #{e.message}"
    end
  end
  
  private
  
  def get_current_weather(location)
    endpoint = "#{@base_url}/weather"
    params = {
      q: location,
      appid: @api_key,
      units: @units
    }
    
    response = make_api_request(endpoint, params)
    format_weather_response(response)
  end
  
  def get_forecast(location)
    endpoint = "#{@base_url}/forecast"
    params = {
      q: location,
      appid: @api_key,
      units: @units,
      cnt: 5  # 5 day forecast
    }
    
    response = make_api_request(endpoint, params)
    format_forecast_response(response)
  end
  
  def make_api_request(endpoint, params)
    uri = URI(endpoint)
    uri.query = URI.encode_www_form(params)
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    
    request = Net::HTTP::Get.new(uri)
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      raise "API error: #{response.code} - #{response.body}"
    end
  end
  
  def format_weather_response(data)
    temp = data['main']['temp']
    feels_like = data['main']['feels_like']
    description = data['weather'][0]['description']
    humidity = data['main']['humidity']
    wind_speed = data['wind']['speed']
    
    unit_label = @units == 'metric' ? '°C' : '°F'
    
    <<~WEATHER
      Weather in #{data['name']}, #{data['sys']['country']}:
      Temperature: #{temp}#{unit_label} (feels like #{feels_like}#{unit_label})
      Conditions: #{description}
      Humidity: #{humidity}%
      Wind Speed: #{wind_speed} #{@units == 'metric' ? 'm/s' : 'mph'}
    WEATHER
  end
  
  def format_forecast_response(data)
    forecasts = data['list'].map do |item|
      time = Time.at(item['dt']).strftime('%Y-%m-%d %H:%M')
      temp = item['main']['temp']
      desc = item['weather'][0]['description']
      "#{time}: #{temp}°, #{desc}"
    end
    
    "5-Day Forecast for #{data['city']['name']}:\n" + forecasts.join("\n")
  end
end
```

## Advanced Tool Features

### Tool with State Management

```ruby
class SessionMemoryTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'session_memory'
    @description = 'Store and retrieve information during agent session'
    @memory_store = {}
    @max_entries = options[:max_entries] || 100
    @ttl = options[:ttl] || 3600  # 1 hour default
  end
  
  def execute(**params)
    validate_params!(params, 
      required: [:action], 
      optional: [:key, :value, :pattern]
    )
    
    action = params[:action].to_sym
    
    case action
    when :store
      store_value(params[:key], params[:value])
    when :retrieve
      retrieve_value(params[:key])
    when :delete
      delete_value(params[:key])
    when :list
      list_keys(params[:pattern])
    when :clear
      clear_all
    else
      raise ToolError, "Unknown action: #{action}"
    end
  end
  
  private
  
  def store_value(key, value)
    raise ToolError, "Key and value required for store action" unless key && value
    
    # Enforce size limit
    if @memory_store.size >= @max_entries && !@memory_store.key?(key)
      evict_oldest
    end
    
    @memory_store[key] = {
      value: value,
      timestamp: Time.now,
      access_count: 0
    }
    
    "Stored: #{key} = #{value}"
  end
  
  def retrieve_value(key)
    raise ToolError, "Key required for retrieve action" unless key
    
    if entry = @memory_store[key]
      # Check TTL
      if Time.now - entry[:timestamp] > @ttl
        @memory_store.delete(key)
        return "Key expired: #{key}"
      end
      
      entry[:access_count] += 1
      entry[:last_accessed] = Time.now
      
      "Retrieved: #{key} = #{entry[:value]} (accessed #{entry[:access_count]} times)"
    else
      "Key not found: #{key}"
    end
  end
  
  def delete_value(key)
    if @memory_store.delete(key)
      "Deleted: #{key}"
    else
      "Key not found: #{key}"
    end
  end
  
  def list_keys(pattern = nil)
    keys = @memory_store.keys
    
    if pattern
      regex = Regexp.new(pattern)
      keys = keys.select { |k| k.match?(regex) }
    end
    
    "Keys (#{keys.length}): #{keys.join(', ')}"
  end
  
  def clear_all
    count = @memory_store.size
    @memory_store.clear
    "Cleared #{count} entries"
  end
  
  def evict_oldest
    oldest = @memory_store.min_by { |k, v| v[:last_accessed] || v[:timestamp] }
    @memory_store.delete(oldest[0]) if oldest
  end
end
```

### Async Tool with Callbacks

```ruby
class AsyncProcessingTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'async_processor'
    @description = 'Process tasks asynchronously with progress tracking'
    @callback = options[:callback]
    @thread_pool = []
    @max_threads = options[:max_threads] || 5
  end
  
  def execute(**params)
    validate_params!(params, 
      required: [:task_type, :data],
      optional: [:priority, :timeout]
    )
    
    task_id = SecureRandom.uuid
    priority = params[:priority] || :normal
    timeout = params[:timeout] || 60
    
    # Start async processing
    thread = Thread.new do
      begin
        process_async(task_id, params[:task_type], params[:data], timeout)
      rescue => e
        handle_async_error(task_id, e)
      end
    end
    
    # Manage thread pool
    @thread_pool << thread
    cleanup_threads
    
    "Task queued: #{task_id} (priority: #{priority})"
  end
  
  def get_status(task_id)
    # Check task status
    if result = check_result(task_id)
      "Task #{task_id}: #{result[:status]} - #{result[:message]}"
    else
      "Task #{task_id}: Unknown or not started"
    end
  end
  
  private
  
  def process_async(task_id, task_type, data, timeout)
    update_status(task_id, :processing, "Started at #{Time.now}")
    
    result = Timeout::timeout(timeout) do
      case task_type
      when 'analysis'
        perform_analysis(data)
      when 'transformation'
        perform_transformation(data)
      when 'validation'
        perform_validation(data)
      else
        raise "Unknown task type: #{task_type}"
      end
    end
    
    update_status(task_id, :completed, result)
    
    # Execute callback if provided
    @callback.call(task_id, result) if @callback
    
  rescue Timeout::Error
    update_status(task_id, :timeout, "Task exceeded #{timeout}s limit")
  end
  
  def cleanup_threads
    @thread_pool.reject!(&:alive?)
    
    # Limit thread pool size
    while @thread_pool.size > @max_threads
      oldest = @thread_pool.shift
      oldest.join(1) # Wait 1 second then continue
    end
  end
  
  def update_status(task_id, status, message)
    @status_store ||= {}
    @status_store[task_id] = {
      status: status,
      message: message,
      timestamp: Time.now
    }
  end
  
  def check_result(task_id)
    @status_store&.[](task_id)
  end
end
```

## API Integration Tools

### REST API Client Tool

```ruby
require 'faraday'
require 'json'

class RestApiTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'rest_api'
    @description = 'Make REST API calls with authentication and error handling'
    @base_url = options[:base_url]
    @api_key = options[:api_key]
    @auth_type = options[:auth_type] || :header  # :header, :query, :basic
    @timeout = options[:timeout] || 30
    
    setup_client
  end
  
  def execute(**params)
    validate_params!(params,
      required: [:method, :endpoint],
      optional: [:data, :headers, :query]
    )
    
    method = params[:method].to_s.downcase.to_sym
    endpoint = params[:endpoint]
    data = params[:data]
    headers = params[:headers] || {}
    query = params[:query] || {}
    
    # Add authentication
    headers, query = add_authentication(headers, query)
    
    # Make request
    response = make_request(method, endpoint, data, headers, query)
    
    # Format response
    format_api_response(response)
  rescue Faraday::Error => e
    handle_api_error(e)
  end
  
  private
  
  def setup_client
    @client = Faraday.new(url: @base_url) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
      f.options.timeout = @timeout
      
      # Add middleware for logging
      f.response :logger if @options[:debug]
      
      # Add retry logic
      f.request :retry, {
        max: 3,
        interval: 0.5,
        interval_randomness: 0.5,
        backoff_factor: 2
      }
    end
  end
  
  def add_authentication(headers, query)
    case @auth_type
    when :header
      headers['Authorization'] = "Bearer #{@api_key}" if @api_key
    when :query
      query['api_key'] = @api_key if @api_key
    when :basic
      headers['Authorization'] = "Basic #{Base64.encode64(@api_key)}" if @api_key
    end
    
    [headers, query]
  end
  
  def make_request(method, endpoint, data, headers, query)
    case method
    when :get
      @client.get(endpoint, query, headers)
    when :post
      @client.post(endpoint, data, headers) do |req|
        req.params = query
      end
    when :put
      @client.put(endpoint, data, headers) do |req|
        req.params = query
      end
    when :patch
      @client.patch(endpoint, data, headers) do |req|
        req.params = query
      end
    when :delete
      @client.delete(endpoint, query, headers)
    else
      raise ToolError, "Unsupported HTTP method: #{method}"
    end
  end
  
  def format_api_response(response)
    status = response.status
    body = response.body
    
    if status >= 200 && status < 300
      if body.is_a?(Hash) || body.is_a?(Array)
        JSON.pretty_generate(body)
      else
        body.to_s
      end
    else
      "API Error (#{status}): #{body}"
    end
  end
  
  def handle_api_error(error)
    case error
    when Faraday::TimeoutError
      "API request timed out after #{@timeout} seconds"
    when Faraday::ConnectionFailed
      "Failed to connect to API: #{error.message}"
    else
      "API error: #{error.class} - #{error.message}"
    end
  end
end

# Usage example
github_api = RestApiTool.new(
  base_url: 'https://api.github.com',
  api_key: ENV['GITHUB_TOKEN'],
  auth_type: :header
)

# Agent can use: USE_TOOL[rest_api](method=get, endpoint=/user/repos, query={per_page: 10})
```

### GraphQL Client Tool

```ruby
class GraphQLTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'graphql'
    @description = 'Execute GraphQL queries and mutations'
    @endpoint = options[:endpoint]
    @api_key = options[:api_key]
    @client = setup_graphql_client
  end
  
  def execute(**params)
    validate_params!(params,
      required: [:query],
      optional: [:variables, :operation_name]
    )
    
    query = params[:query]
    variables = params[:variables] || {}
    operation_name = params[:operation_name]
    
    response = @client.execute(
      query,
      variables: variables,
      operation_name: operation_name
    )
    
    format_graphql_response(response)
  rescue => e
    "GraphQL error: #{e.message}"
  end
  
  private
  
  def setup_graphql_client
    Faraday.new(url: @endpoint) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
      
      # Add authentication
      f.headers['Authorization'] = "Bearer #{@api_key}" if @api_key
    end
  end
  
  def format_graphql_response(response)
    if response['errors']
      errors = response['errors'].map { |e| e['message'] }.join(', ')
      "GraphQL errors: #{errors}"
    elsif response['data']
      JSON.pretty_generate(response['data'])
    else
      "Empty response"
    end
  end
end
```

## Database Tools

### SQL Database Tool

```ruby
require 'sequel'

class SqlDatabaseTool < RCrewAI::Tools::Base
  def initialize(**options)
    super
    @name = 'sql_database'
    @description = 'Execute SQL queries with safety checks'
    @connection_string = options[:connection_string]
    @read_only = options[:read_only] || true
    @max_rows = options[:max_rows] || 100
    @timeout = options[:timeout] || 30
    
    setup_connection
  end
  
  def execute(**params)
    validate_params!(params, required: [:query], optional: [:params])
    
    query = params[:query]
    query_params = params[:params] || []
    
    # Safety checks
    validate_query_safety(query) if @read_only
    
    # Execute query
    result = execute_query(query, query_params)
    
    # Format result
    format_query_result(result)
  rescue => e
    "Database error: #{e.message}"
  end
  
  private
  
  def setup_connection
    @db = Sequel.connect(@connection_string)
    @db.extension :pg_json if @connection_string.include?('postgres')
    
    # Set connection options
    @db.pool.connection_validation_timeout = -1
    @db.pool.max_connections = 5
  end
  
  def validate_query_safety(query)
    unsafe_keywords = %w[
      INSERT UPDATE DELETE DROP CREATE ALTER TRUNCATE
      EXEC EXECUTE GRANT REVOKE
    ]
    
    query_upper = query.upcase
    unsafe_keywords.each do |keyword|
      if query_upper.include?(keyword)
        raise ToolError, "Unsafe operation '#{keyword}' not allowed in read-only mode"
      end
    end
  end
  
  def execute_query(query, params)
    Timeout::timeout(@timeout) do
      dataset = @db[query, *params]
      
      # Limit results
      dataset = dataset.limit(@max_rows) if dataset.respond_to?(:limit)
      
      # Execute and fetch
      if query.upcase.start_with?('SELECT')
        dataset.all
      else
        rows_affected = dataset
        { rows_affected: rows_affected }
      end
    end
  end
  
  def format_query_result(result)
    if result.is_a?(Array)
      # Format as table
      return "No results" if result.empty?
      
      headers = result.first.keys
      rows = result.map { |r| r.values }
      
      format_table(headers, rows)
    elsif result.is_a?(Hash)
      "Query executed: #{result[:rows_affected]} rows affected"
    else
      result.to_s
    end
  end
  
  def format_table(headers, rows)
    # Calculate column widths
    widths = headers.map(&:to_s).map(&:length)
    rows.each do |row|
      row.each_with_index do |cell, i|
        widths[i] = [widths[i], cell.to_s.length].max
      end
    end
    
    # Build table
    separator = "+" + widths.map { |w| "-" * (w + 2) }.join("+") + "+"
    header_row = "|" + headers.each_with_index.map { |h, i| 
      " #{h.to_s.ljust(widths[i])} "
    }.join("|") + "|"
    
    table = [separator, header_row, separator]
    
    rows.each do |row|
      row_str = "|" + row.each_with_index.map { |cell, i|
        " #{cell.to_s.ljust(widths[i])} "
      }.join("|") + "|"
      table << row_str
    end
    
    table << separator
    table.join("\n")
  end
end
```

## File Processing Tools

### Document Processor Tool

```ruby
require 'pdf-reader'
require 'docx'
require 'csv'

class DocumentProcessorTool < RCrewAI::Tools::Base
  SUPPORTED_FORMATS = %w[.pdf .docx .txt .csv .json]
  
  def initialize(**options)
    super
    @name = 'document_processor'
    @description = 'Extract and process content from various document formats'
    @max_file_size = options[:max_file_size] || 10_000_000  # 10MB
  end
  
  def execute(**params)
    validate_params!(params, 
      required: [:file_path],
      optional: [:operation, :options]
    )
    
    file_path = params[:file_path]
    operation = params[:operation] || :extract_text
    options = params[:options] || {}
    
    # Validate file
    validate_file(file_path)
    
    # Process based on operation
    case operation.to_sym
    when :extract_text
      extract_text(file_path, options)
    when :extract_metadata
      extract_metadata(file_path)
    when :convert
      convert_document(file_path, options)
    when :analyze
      analyze_document(file_path, options)
    else
      raise ToolError, "Unknown operation: #{operation}"
    end
  end
  
  private
  
  def validate_file(file_path)
    unless File.exist?(file_path)
      raise ToolError, "File not found: #{file_path}"
    end
    
    if File.size(file_path) > @max_file_size
      raise ToolError, "File too large: #{File.size(file_path)} bytes"
    end
    
    ext = File.extname(file_path).downcase
    unless SUPPORTED_FORMATS.include?(ext)
      raise ToolError, "Unsupported format: #{ext}"
    end
  end
  
  def extract_text(file_path, options)
    ext = File.extname(file_path).downcase
    
    text = case ext
    when '.pdf'
      extract_pdf_text(file_path, options)
    when '.docx'
      extract_docx_text(file_path)
    when '.txt'
      File.read(file_path)
    when '.csv'
      extract_csv_text(file_path, options)
    when '.json'
      JSON.pretty_generate(JSON.parse(File.read(file_path)))
    end
    
    # Apply options
    if options[:max_length]
      text = text[0...options[:max_length]]
    end
    
    if options[:clean]
      text = clean_text(text)
    end
    
    text
  end
  
  def extract_pdf_text(file_path, options)
    reader = PDF::Reader.new(file_path)
    
    if options[:page]
      # Extract specific page
      page = reader.pages[options[:page] - 1]
      page&.text || ""
    else
      # Extract all pages
      reader.pages.map(&:text).join("\n\n")
    end
  end
  
  def extract_docx_text(file_path)
    doc = Docx::Document.open(file_path)
    doc.paragraphs.map(&:text).join("\n")
  end
  
  def extract_csv_text(file_path, options)
    csv_options = {
      headers: options[:headers] != false,
      encoding: options[:encoding] || 'UTF-8'
    }
    
    rows = CSV.read(file_path, csv_options)
    
    if options[:as_json]
      JSON.pretty_generate(rows.map(&:to_h))
    else
      CSV.generate do |csv|
        rows.each { |row| csv << row }
      end
    end
  end
  
  def extract_metadata(file_path)
    metadata = {
      filename: File.basename(file_path),
      size: File.size(file_path),
      modified: File.mtime(file_path),
      format: File.extname(file_path)
    }
    
    ext = File.extname(file_path).downcase
    
    case ext
    when '.pdf'
      reader = PDF::Reader.new(file_path)
      metadata[:pages] = reader.page_count
      metadata[:info] = reader.info
    when '.docx'
      doc = Docx::Document.open(file_path)
      metadata[:paragraphs] = doc.paragraphs.count
      metadata[:tables] = doc.tables.count
    end
    
    JSON.pretty_generate(metadata)
  end
  
  def analyze_document(file_path, options)
    text = extract_text(file_path, {})
    
    analysis = {
      character_count: text.length,
      word_count: text.split.length,
      line_count: text.lines.count,
      paragraph_count: text.split(/\n\n+/).length
    }
    
    if options[:keywords]
      keywords = options[:keywords]
      analysis[:keyword_frequency] = {}
      
      keywords.each do |keyword|
        count = text.scan(/#{Regexp.escape(keyword)}/i).length
        analysis[:keyword_frequency][keyword] = count
      end
    end
    
    JSON.pretty_generate(analysis)
  end
  
  def clean_text(text)
    # Remove extra whitespace
    text = text.gsub(/\s+/, ' ')
    
    # Remove special characters
    text = text.gsub(/[^\w\s\.\,\!\?\-]/, '')
    
    # Normalize line endings
    text = text.gsub(/\r\n/, "\n")
    
    text.strip
  end
end
```

## Testing Custom Tools

### RSpec Tests for Tools

```ruby
require 'rspec'

RSpec.describe CalculatorTool do
  let(:tool) { CalculatorTool.new(precision: 2) }
  
  describe '#execute' do
    context 'with addition' do
      it 'adds numbers correctly' do
        result = tool.execute(
          operation: 'add',
          operands: [5, 3, 2]
        )
        expect(result).to eq('Result: 10')
      end
    end
    
    context 'with division' do
      it 'divides numbers correctly' do
        result = tool.execute(
          operation: 'divide',
          operands: [10, 2]
        )
        expect(result).to eq('Result: 5')
      end
      
      it 'raises error for division by zero' do
        expect {
          tool.execute(
            operation: 'divide',
            operands: [10, 0]
          )
        }.to raise_error(RCrewAI::Tools::ToolError, /Division by zero/)
      end
    end
    
    context 'with invalid parameters' do
      it 'raises error for missing required parameters' do
        expect {
          tool.execute(operation: 'add')
        }.to raise_error(RCrewAI::Tools::ToolError, /Missing required parameter/)
      end
      
      it 'raises error for invalid operands' do
        expect {
          tool.execute(
            operation: 'add',
            operands: 'not an array'
          )
        }.to raise_error(RCrewAI::Tools::ToolError, /must be an array/)
      end
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe 'Tool Integration' do
  let(:agent) do
    RCrewAI::Agent.new(
      name: 'test_agent',
      role: 'Tool Tester',
      goal: 'Test tool integration',
      tools: [
        CalculatorTool.new,
        WeatherTool.new(api_key: 'test_key'),
        SessionMemoryTool.new
      ]
    )
  end
  
  it 'agent can use multiple tools in sequence' do
    task = RCrewAI::Task.new(
      name: 'complex_calculation',
      description: 'Calculate 5 * 3, store result, then add 10',
      agent: agent
    )
    
    # Mock the reasoning loop to use tools
    allow(agent).to receive(:reasoning_loop) do |task, context|
      # Step 1: Multiply
      result1 = agent.use_tool('calculator', 
        operation: 'multiply', 
        operands: [5, 3]
      )
      
      # Step 2: Store result
      agent.use_tool('session_memory',
        action: 'store',
        key: 'multiply_result',
        value: 15
      )
      
      # Step 3: Add
      result2 = agent.use_tool('calculator',
        operation: 'add',
        operands: [15, 10]
      )
      
      "Final result: 25"
    end
    
    result = task.execute
    expect(result).to include('25')
  end
end
```

## Tool Security and Validation

### Secure Tool Base Class

```ruby
class SecureTool < RCrewAI::Tools::Base
  def execute(**params)
    # Input sanitization
    sanitized_params = sanitize_inputs(params)
    
    # Rate limiting
    check_rate_limit
    
    # Execute with timeout
    Timeout::timeout(execution_timeout) do
      # Audit logging
      log_execution(sanitized_params)
      
      # Execute tool logic
      result = perform_execution(sanitized_params)
      
      # Output validation
      validate_output(result)
      
      result
    end
  rescue Timeout::Error
    handle_timeout
  rescue => e
    handle_error(e)
  end
  
  private
  
  def sanitize_inputs(params)
    params.transform_values do |value|
      case value
      when String
        # Remove potentially dangerous characters
        value.gsub(/[<>'\"&]/, '')
      when Array
        value.map { |v| sanitize_inputs(v) if v.is_a?(String) || v.is_a?(Hash) }
      when Hash
        sanitize_inputs(value)
      else
        value
      end
    end
  end
  
  def check_rate_limit
    @last_execution ||= {}
    key = "#{self.class.name}_#{Thread.current.object_id}"
    
    if @last_execution[key] && Time.now - @last_execution[key] < 1
      raise ToolError, "Rate limit exceeded - please wait"
    end
    
    @last_execution[key] = Time.now
  end
  
  def validate_output(result)
    # Check output size
    if result.to_s.length > 1_000_000
      raise ToolError, "Output too large"
    end
    
    # Check for sensitive data
    if contains_sensitive_data?(result)
      raise ToolError, "Output contains sensitive information"
    end
  end
  
  def contains_sensitive_data?(text)
    patterns = [
      /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
      /\b\d{16}\b/,              # Credit card
      /api[_-]?key/i,            # API keys
      /password/i,               # Passwords
      /secret/i                  # Secrets
    ]
    
    text_str = text.to_s
    patterns.any? { |pattern| text_str.match?(pattern) }
  end
  
  def log_execution(params)
    @logger.info "Tool execution: #{@name}"
    @logger.debug "Parameters: #{params.inspect}"
  end
  
  def execution_timeout
    30  # Default 30 seconds
  end
end
```

## Best Practices

### 1. **Tool Design Principles**
- Single responsibility - each tool does one thing well
- Clear, descriptive names and descriptions
- Comprehensive parameter validation
- Meaningful error messages
- Consistent output formatting

### 2. **Security Considerations**
- Always sanitize inputs
- Implement rate limiting
- Use timeouts to prevent hanging
- Validate output size and content
- Audit log all executions
- Never expose sensitive data

### 3. **Performance Optimization**
- Cache expensive operations
- Use connection pooling for databases/APIs
- Implement retry logic with backoff
- Stream large files instead of loading entirely
- Clean up resources after use

### 4. **Error Handling**
- Provide clear error messages
- Distinguish between recoverable and fatal errors
- Log errors with context
- Implement graceful degradation
- Return partial results when possible

### 5. **Testing Strategy**
- Unit test all tool methods
- Test parameter validation thoroughly
- Mock external dependencies
- Test error conditions
- Integration test with agents
- Performance test with large inputs

## Next Steps

Now that you can build custom tools:

1. Learn about [Working with Multiple Crews]({{ site.baseurl }}/tutorials/multiple-crews)
2. Explore [Production Deployment]({{ site.baseurl }}/tutorials/deployment) strategies
3. Review the [Tools API Documentation]({{ site.baseurl }}/api/tools)
4. Check out [Example Custom Tools]({{ site.baseurl }}/examples/) in production

Custom tools are essential for extending RCrewAI to handle specialized tasks and integrate with your existing systems.