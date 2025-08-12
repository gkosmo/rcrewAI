# frozen_string_literal: true

module RCrewAI
  class Configuration
    attr_accessor :llm_provider, :api_key, :model, :temperature, :max_tokens, :timeout
    attr_accessor :openai_api_key, :anthropic_api_key, :google_api_key, :azure_api_key
    attr_accessor :openai_model, :anthropic_model, :google_model, :azure_model
    attr_accessor :base_url, :api_version, :deployment_name

    def initialize
      @llm_provider = :openai
      @model = 'gpt-4'
      @temperature = 0.1
      @max_tokens = 4000
      @timeout = 120
      
      # Default models for each provider
      @openai_model = 'gpt-4'
      @anthropic_model = 'claude-3-sonnet-20240229'
      @google_model = 'gemini-pro'
      @azure_model = 'gpt-4'
      
      # Load from environment variables
      load_from_env
    end

    def api_key
      case @llm_provider
      when :openai
        @openai_api_key || @api_key
      when :anthropic
        @anthropic_api_key || @api_key
      when :google
        @google_api_key || @api_key
      when :azure
        @azure_api_key || @api_key
      else
        @api_key
      end
    end

    def model
      case @llm_provider
      when :openai
        @openai_model || @model
      when :anthropic
        @anthropic_model || @model
      when :google
        @google_model || @model
      when :azure
        @azure_model || @model
      else
        @model
      end
    end

    def validate!
      raise ConfigurationError, "LLM provider must be set" if @llm_provider.nil?
      raise ConfigurationError, "API key must be set for #{@llm_provider}" if api_key.nil? || api_key.empty?
      raise ConfigurationError, "Model must be set for #{@llm_provider}" if model.nil? || model.empty?
    end

    def supported_providers
      %i[openai anthropic google azure ollama]
    end

    def provider_supported?(provider)
      supported_providers.include?(provider.to_sym)
    end

    private

    def load_from_env
      @openai_api_key = ENV['OPENAI_API_KEY']
      @anthropic_api_key = ENV['ANTHROPIC_API_KEY'] || ENV['CLAUDE_API_KEY']
      @google_api_key = ENV['GOOGLE_API_KEY'] || ENV['GEMINI_API_KEY']
      @azure_api_key = ENV['AZURE_OPENAI_API_KEY']
      
      @api_key = ENV['LLM_API_KEY'] if @api_key.nil?
      @base_url = ENV['LLM_BASE_URL'] if @base_url.nil?
      @api_version = ENV['AZURE_API_VERSION'] if @api_version.nil?
      @deployment_name = ENV['AZURE_DEPLOYMENT_NAME'] if @deployment_name.nil?
    end
  end

  class ConfigurationError < Error; end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure(validate: true)
    yield(configuration)
    configuration.validate! if validate
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end
end