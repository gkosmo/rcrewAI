# frozen_string_literal: true

require_relative '../similarity'

module RCrewAI
  module Knowledge
    # In-memory vector store with cosine-similarity search. The default backing
    # store for Knowledge — no external service required. The interface
    # (#add, #search) is intentionally small so a Chroma/Qdrant-backed store can
    # be swapped in later.
    class Store
      Entry = Struct.new(:text, :vector)

      def initialize
        @entries = []
      end

      def add(text, vector)
        @entries << Entry.new(text, vector)
      end

      # Returns the texts of the top-k entries most similar to +query_vector+.
      def search(query_vector, k: 3)
        return [] if @entries.empty?

        @entries
          .map { |e| [e.text, cosine_similarity(query_vector, e.vector)] }
          .sort_by { |(_text, score)| -score }
          .first(k)
          .map(&:first)
      end

      def size
        @entries.length
      end

      def empty?
        @entries.empty?
      end

      private

      def cosine_similarity(vec_a, vec_b)
        Similarity.cosine(vec_a, vec_b)
      end
    end
  end
end
