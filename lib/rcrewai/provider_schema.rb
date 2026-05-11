# frozen_string_literal: true

module RCrewAI
  module ProviderSchema
    module_function

    def for(provider, canonical)
      case provider.to_sym
      when :openai, :azure, :ollama
        { type: "function", function: canonical }
      when :anthropic
        {
          name: canonical[:name],
          description: canonical[:description],
          input_schema: canonical[:parameters]
        }
      when :google
        {
          function_declarations: [{
            name: canonical[:name],
            description: canonical[:description],
            parameters: canonical[:parameters]
          }]
        }
      else
        raise ArgumentError, "unknown provider #{provider.inspect}"
      end
    end

    def for_many(provider, canonicals)
      if provider.to_sym == :google
        { function_declarations: canonicals.map { |c| self.for(:google, c)[:function_declarations].first } }
      else
        canonicals.map { |c| self.for(provider, c) }
      end
    end
  end
end
