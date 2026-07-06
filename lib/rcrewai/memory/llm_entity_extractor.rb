# frozen_string_literal: true

require_relative '../output_schema'

module RCrewAI
  class Memory
    # Extracts named entities from text with an LLM. Pass an instance as the
    # `extractor:` for EntityMemory. Responds to `call(text) -> [names]`.
    # Returns [] on any parse/LLM failure so EntityMemory falls back to the
    # heuristic extractor — extraction is best-effort and never fatal.
    class LlmEntityExtractor
      PROMPT = <<~PROMPT
        Extract the named entities (people, organizations, systems, products,
        places, and key concepts) from the text below. Respond ONLY with a JSON
        array of strings, e.g. ["Alice", "Payments", "Redis"]. No prose.

        Text:
      PROMPT

      def initialize(llm)
        @llm = llm
      end

      def call(text)
        response = @llm.chat(messages: [{ role: 'user', content: "#{PROMPT}#{text}" }])
        content = response.is_a?(Hash) ? response[:content] : response
        parsed = OutputSchema.parse(content.to_s)
        parsed.is_a?(Array) ? parsed.map(&:to_s) : []
      rescue StandardError
        []
      end
    end
  end
end
