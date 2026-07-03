# frozen_string_literal: true

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

      def cosine_similarity(a, b)
        dot = 0.0
        norm_a = 0.0
        norm_b = 0.0
        a.each_index do |i|
          ai = a[i].to_f
          bi = (b[i] || 0).to_f
          dot += ai * bi
          norm_a += ai * ai
          norm_b += bi * bi
        end
        return 0.0 if norm_a.zero? || norm_b.zero?

        dot / (Math.sqrt(norm_a) * Math.sqrt(norm_b))
      end
    end
  end
end
