# frozen_string_literal: true

require_relative 'tool_approval'

module RCrewAI
  class Configuration
    # Used when neither +<provider>_model+ nor +model+ has been set.
    DEFAULT_MODELS = {
      openai: 'gpt-4o',
      anthropic: 'claude-opus-5-5',
      google: 'gemini-3.8-flash',
      azure: 'gpt-4o'
    }.freeze

    # Sent by providers that take a temperature when none has been set. The
    # Anthropic client sends only #explicit_temperature, because current Claude
    # models reject the field.
    DEFAULT_TEMPERATURE = 0.1

    # Providers that authenticate some other way, or not at all.
    KEYLESS_PROVIDERS = %i[ollama].freeze

    attr_accessor :llm_provider, :api_key, :model, :max_tokens, :timeout,
                  :openai_api_key, :anthropic_api_key, :google_api_key, :azure_api_key,
                  :base_url, :api_version, :deployment_name,
                  :aws_region, :snowflake_account,
                  :pricing, :ollama_native_tools, :log_level,
                  :approval_handler, :approval_timeout
    attr_writer :openai_model, :anthropic_model, :google_model, :azure_model

    DEFAULT_MODELS.each do |provider, default|
      define_method("#{provider}_model") { instance_variable_get("@#{provider}_model") || default }
    end

    def initialize
      @llm_provider = :openai
      @max_tokens = 4000
      @timeout = 120

      @aws_region = nil
      @snowflake_account = nil

      @pricing = nil
      @ollama_native_tools = nil
      @log_level = :info
      @approval_handler = nil
      @approval_timeout = ToolApproval::DEFAULT_TIMEOUT

      # Load from environment variables
      load_from_env
    end

    def temperature
      @temperature_set ? @temperature : DEFAULT_TEMPERATURE
    end

    def temperature=(value)
      @temperature = value
      @temperature_set = true
    end

    # The temperature the user chose, or nil if they never set one.
    def explicit_temperature
      @temperature if @temperature_set
    end

    def api_key
      case @llm_provider
      when :openai, :openai_responses
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

    # Resolution order: an explicit +<provider>_model+, then +model+, then the
    # provider's default. Providers without a default must be given a model.
    def model
      family = model_family(@llm_provider)
      explicit = instance_variable_get("@#{family}_model") if DEFAULT_MODELS.key?(family)
      explicit || @model || DEFAULT_MODELS[family]
    end

    # Returns a copy of this configuration with the given per-agent overrides
    # applied. The original configuration is left untouched, so agents can each
    # target a different provider/model without mutating global state.
    #
    #   config.with_overrides(provider: :anthropic, model: 'claude-opus-5-5')
    #
    # Pass temperature: nil to clear a global temperature for this copy.
    def with_overrides(provider: nil, model: nil, api_key: nil, temperature: :inherit)
      copy = dup
      copy.llm_provider = provider.to_sym if provider
      target = copy.llm_provider

      # A global +model+ names a model on the global provider; it must not
      # follow an agent that switches to a different one.
      copy.model = nil if target != llm_provider

      family = model_family(target)
      copy.public_send("#{family}_model=", model) if model && copy.respond_to?("#{family}_model=")
      copy.model = model if model

      copy.public_send("#{target}_api_key=", api_key) if api_key && copy.respond_to?("#{target}_api_key=")
      copy.api_key = api_key if api_key

      copy.temperature = temperature unless temperature == :inherit
      copy
    end

    def validate!
      raise ConfigurationError, 'LLM provider must be set' if @llm_provider.nil?
      raise ConfigurationError, "API key must be set for #{@llm_provider}" if api_key_missing?
      raise ConfigurationError, "Model must be set for #{@llm_provider}" if model.nil? || model.empty?
    end

    def supported_providers
      LLMClient::PROVIDERS.keys
    end

    def provider_supported?(provider)
      supported_providers.include?(provider.to_sym)
    end

    private

    # The Responses API is OpenAI under another request shape: same models, same key.
    def model_family(provider)
      provider == :openai_responses ? :openai : provider
    end

    def api_key_missing?
      !KEYLESS_PROVIDERS.include?(@llm_provider.to_sym) && (api_key.nil? || api_key.empty?)
    end

    def load_from_env
      @openai_api_key = ENV['OPENAI_API_KEY']
      @anthropic_api_key = ENV['ANTHROPIC_API_KEY'] || ENV['CLAUDE_API_KEY']
      @google_api_key = ENV['GOOGLE_API_KEY'] || ENV['GEMINI_API_KEY']
      @azure_api_key = ENV['AZURE_OPENAI_API_KEY']

      @aws_region ||= ENV.fetch('AWS_REGION', nil) || ENV.fetch('AWS_DEFAULT_REGION', nil)
      @snowflake_account ||= ENV.fetch('SNOWFLAKE_ACCOUNT', nil)

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
