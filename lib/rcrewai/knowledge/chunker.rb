# frozen_string_literal: true

module RCrewAI
  module Knowledge
    # Splits text into fixed-size, overlapping character windows. Overlap keeps
    # context from spilling across chunk boundaries during retrieval.
    class Chunker
      def initialize(chunk_size: 1000, overlap: 100)
        raise ArgumentError, 'overlap must be smaller than chunk_size' if overlap >= chunk_size

        @chunk_size = chunk_size
        @overlap = overlap
      end

      def chunk(text)
        text = text.to_s
        return [] if text.empty?
        return [text] if text.length <= @chunk_size

        chunks = []
        start = 0
        step = @chunk_size - @overlap
        while start < text.length
          chunks << text[start, @chunk_size]
          start += step
        end
        chunks
      end
    end
  end
end
