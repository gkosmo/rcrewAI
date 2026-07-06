# frozen_string_literal: true

require_relative 'base_memory'

module RCrewAI
  class Memory
    # Facts about entities (people, systems, concepts) accumulated from work.
    # Entities are extracted heuristically (capitalized tokens / acronyms); an
    # LLM-backed extractor can be swapped in later.
    class EntityMemory < BaseMemory
      # Skip sentence-initial common words that happen to be capitalized.
      COMMON = %w[The A An I In On At To For Of With By And Or But It This That Who Where When].freeze

      def initialize(scope:, embedder: nil, store: nil, limit: nil, extractor: nil)
        super(scope: scope, embedder: embedder, store: store, limit: limit)
        @extractor = extractor
        @entities = []
      end

      # Records a full observation and indexes the entities it mentions.
      def observe(text)
        found = extract_entities(text)
        @entities.concat(found)
        add(text, { 'entities' => found })
      end

      def entities
        @entities.uniq
      end

      protected

      def type_suffix
        'entity'
      end

      def format(record)
        record[:text]
      end

      private

      # Uses the custom extractor when provided, falling back to the heuristic
      # if it's absent, returns nothing, or raises.
      def extract_entities(text)
        if @extractor
          begin
            result = Array(@extractor.call(text))
            return result unless result.empty?
          rescue StandardError
            # fall through to heuristic
          end
        end
        heuristic_entities(text)
      end

      def heuristic_entities(text)
        text.to_s.scan(/\b([A-Z][a-zA-Z0-9]{1,})\b/).flatten.reject { |w| COMMON.include?(w) }.uniq
      end
    end
  end
end
