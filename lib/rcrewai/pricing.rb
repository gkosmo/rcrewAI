# frozen_string_literal: true

module RCrewAI
  module Pricing
    # Prices in USD per 1M tokens. List prices as of 2026-05; users can override.
    DEFAULT_PRICES = {
      # OpenAI
      "gpt-4o"            => { input: 2.50, output: 10.00 },
      "gpt-4o-mini"       => { input: 0.15, output: 0.60 },
      "gpt-4-turbo"       => { input: 10.00, output: 30.00 },
      "gpt-4"             => { input: 30.00, output: 60.00 },
      "gpt-3.5-turbo"     => { input: 0.50, output: 1.50 },
      # Anthropic
      "claude-opus-4-7"   => { input: 15.00, output: 75.00 },
      "claude-sonnet-4-6" => { input: 3.00,  output: 15.00 },
      "claude-haiku-4-5"  => { input: 0.80,  output: 4.00 },
      "claude-3-5-sonnet-20241022" => { input: 3.00, output: 15.00 },
      "claude-3-haiku-20240307"    => { input: 0.25, output: 1.25 },
      # Google
      "gemini-1.5-pro"    => { input: 1.25, output: 5.00 },
      "gemini-1.5-flash"  => { input: 0.075, output: 0.30 }
    }.freeze

    module_function

    def cost_for(model, prompt_tokens:, completion_tokens:)
      table = RCrewAI.configuration.pricing || {}
      entry = table[model] || DEFAULT_PRICES[model]
      return nil unless entry
      ((prompt_tokens * entry[:input]) + (completion_tokens * entry[:output])) / 1_000_000.0
    end
  end
end
