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

      def initialize(scope:, embedder: nil, store: nil, limit: nil)
        super
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

      def extract_entities(text)
        text.to_s.scan(/\b([A-Z][a-zA-Z0-9]{1,})\b/).flatten.reject { |w| COMMON.include?(w) }.uniq
      end
    end
  end
end
