# frozen_string_literal: true

require_relative 'base_memory'

module RCrewAI
  class Memory
    # Durable insights promoted from successful executions. Dedupes
    # near-identical insights so the store doesn't fill with paraphrases.
    class LongTermMemory < BaseMemory
      DEDUPE_THRESHOLD = 0.92

      def record(text, metadata = {})
        return nil if duplicate?(text)

        add(text, metadata)
      end

      protected

      def type_suffix
        'long_term'
      end

      private

      def duplicate?(text)
        existing = @store.all(scope: @scope)
        return false if existing.empty?

        query_vector = embed(text)
        if query_vector && existing.any? { |r| r[:vector] }
          existing.any? { |r| r[:vector] && Similarity.cosine(query_vector, r[:vector]) >= DEDUPE_THRESHOLD }
        else
          existing.any? { |r| Similarity.lexical(text, r[:text]) >= DEDUPE_THRESHOLD }
        end
      end
    end
  end
end
