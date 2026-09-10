# frozen_string_literal: true

require_relative 'openai'

module RCrewAI
  module LLMClients
    # Snowflake Cortex inference. The request/response bodies follow the
    # OpenAI Chat Completions shape, so only the endpoint and the auth headers
    # differ -- Cortex wants the token type declared alongside the bearer
    # token.
    class SnowflakeCortex < OpenAI
      def initialize(config = RCrewAI.configuration, **hooks)
        super
        @account = config.snowflake_account
        @base_url = "https://#{@account}.snowflakecomputing.com"
      end

      def provider_name
        :snowflake
      end

      private

      def chat_url
        "#{@base_url}/api/v2/cortex/inference:complete"
      end

      def auth_header
        {
          'Authorization' => "Bearer #{config.api_key}",
          'X-Snowflake-Authorization-Token-Type' => 'KEYPAIR_JWT'
        }
      end

      def validate_config!
        raise ConfigurationError, 'Snowflake token is required' unless config.api_key
        raise ConfigurationError, 'A Snowflake account identifier is required' unless config.snowflake_account
        raise ConfigurationError, 'Model is required' unless config.model
      end
    end
  end
end
