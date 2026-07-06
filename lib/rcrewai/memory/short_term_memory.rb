# frozen_string_literal: true

require_relative 'base_memory'

module RCrewAI
  class Memory
    # Recent executions with semantic recall. Capped and volatile-by-default.
    class ShortTermMemory < BaseMemory
      def initialize(scope:, embedder: nil, store: nil, limit: 100)
        super
      end

      protected

      def type_suffix
        'short_term'
      end
    end
  end
end
