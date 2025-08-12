# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require 'vcr'
require 'simplecov'

# Start SimpleCov for code coverage
SimpleCov.start do
  add_filter '/spec/'
  add_group 'Core', 'lib/rcrewai/agent.rb'
  add_group 'Core', 'lib/rcrewai/crew.rb'
  add_group 'Core', 'lib/rcrewai/task.rb'
  add_group 'LLM Clients', 'lib/rcrewai/llm_clients'
  add_group 'Tools', 'lib/rcrewai/tools'
  add_group 'Human Input', 'lib/rcrewai/human_input.rb'
end

require_relative '../lib/rcrewai'

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

# Configure VCR for recording HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  
  # Filter sensitive data
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
  config.filter_sensitive_data('<GOOGLE_API_KEY>') { ENV['GOOGLE_API_KEY'] }
  config.filter_sensitive_data('<AZURE_API_KEY>') { ENV['AZURE_API_KEY'] }
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Enable flags
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = false
  config.profile_examples = 10
  
  # Random order
  config.order = :random
  Kernel.srand config.seed

  # Clean configuration before each test
  config.before(:each) do
    RCrewAI.reset_configuration!
  end

  # Helper methods
  config.include Module.new {
    def mock_llm_response(content: 'Mock response', provider: :openai)
      {
        content: content,
        role: 'assistant',
        finish_reason: 'stop',
        usage: { 'total_tokens' => 100 },
        provider: provider
      }
    end

    def configure_test_llm(provider: :openai, model: 'gpt-3.5-turbo')
      RCrewAI.configure do |config|
        config.llm_provider = provider
        config.model = model
        config.api_key = 'test-key'
        config.temperature = 0.1
      end
    end

    def mock_http_response(status: 200, body: {})
      double('Response', status: status, body: body)
    end

    def create_test_agent(name: 'test_agent', **options)
      configure_test_llm unless RCrewAI.configuration.api_key
      RCrewAI::Agent.new(
        name: name,
        role: 'Test Agent',
        goal: 'Test goal',
        backstory: 'Test backstory',
        **options
      )
    end

    def create_test_task(name: 'test_task', agent: nil, **options)
      agent ||= create_test_agent
      RCrewAI::Task.new(
        name: name,
        description: 'Test task description',
        agent: agent,
        **options
      )
    end

    def create_test_crew(name: 'test_crew', **options)
      RCrewAI::Crew.new(name, **options)
    end

    def with_captured_io
      original_stdout = $stdout
      original_stderr = $stderr
      $stdout = StringIO.new
      $stderr = StringIO.new
      yield
      { stdout: $stdout.string, stderr: $stderr.string }
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
  }
end

# Shared examples for LLM clients
RSpec.shared_examples 'an LLM client' do
  describe '#chat' do
    it 'accepts messages and returns formatted response' do
      expect(subject).to respond_to(:chat)
      
      # Create provider-specific mock response
      if subject.class.name.include?('OpenAI')
        mock_response = double('Response',
          status: 200,
          body: {
            'choices' => [{ 'message' => { 'content' => 'Test response', 'role' => 'assistant' } }],
            'usage' => { 'prompt_tokens' => 10, 'completion_tokens' => 20 }
          }
        )
      else
        mock_response = double('Response',
          status: 200,
          body: {
            'content' => [{ 'text' => 'Test response' }],
            'usage' => { 'input_tokens' => 10, 'output_tokens' => 20 }
          }
        )
      end
      
      allow(subject).to receive_message_chain(:http_client, :post).and_return(mock_response)
      
      result = subject.chat(messages: [{ role: 'user', content: 'test' }])
      expect(result).to have_key(:content)
    end
  end

  describe '#complete' do
    it 'accepts prompt and returns formatted response' do
      expect(subject).to respond_to(:complete)
      
      # Create provider-specific mock response
      if subject.class.name.include?('OpenAI')
        mock_response = double('Response',
          status: 200,
          body: {
            'choices' => [{ 'message' => { 'content' => 'Test response', 'role' => 'assistant' } }],
            'usage' => { 'prompt_tokens' => 10, 'completion_tokens' => 20 }
          }
        )
      else
        mock_response = double('Response',
          status: 200,
          body: {
            'content' => [{ 'text' => 'Test response' }],
            'usage' => { 'input_tokens' => 10, 'output_tokens' => 20 }
          }
        )
      end
      
      allow(subject).to receive_message_chain(:http_client, :post).and_return(mock_response)
      
      result = subject.complete(prompt: 'test')
      expect(result).to have_key(:content)
    end
  end
end

# Shared examples for tools
RSpec.shared_examples 'a tool' do
  it 'has required attributes' do
    expect(subject).to respond_to(:name)
    expect(subject).to respond_to(:description)
  end

  it 'can be executed' do
    expect(subject).to respond_to(:execute)
  end

  it 'validates parameters' do
    expect(subject).to respond_to(:validate_params)
  end
end

puts "RSpec configuration loaded successfully"