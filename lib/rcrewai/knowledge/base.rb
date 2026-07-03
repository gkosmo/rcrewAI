# frozen_string_literal: true

require_relative 'chunker'
require_relative 'store'
require_relative 'sources'
require_relative 'embedder'

module RCrewAI
  module Knowledge
    # A knowledge base: loads sources, chunks their text, embeds the chunks, and
    # answers similarity queries. Attach one to an Agent (role-specific) or a
    # Crew (shared) via the +knowledge_sources:+ option.
    class Base
      attr_reader :sources

      def initialize(sources: [], embedder: nil, chunk_size: 1000, overlap: 100)
        @sources = Array(sources)
        @embedder = embedder || Embedder.new
        @chunker = Chunker.new(chunk_size: chunk_size, overlap: overlap)
        @store = Store.new
        @built = false
      end

      # Loads, chunks, and embeds all sources. Idempotent.
      def build!
        return self if @built

        chunks = @sources.flat_map { |source| @chunker.chunk(source.read) }
        unless chunks.empty?
          vectors = @embedder.embed(chunks)
          chunks.zip(vectors).each { |text, vector| @store.add(text, vector) }
        end

        @built = true
        self
      end

      # Returns up to k chunks most relevant to the query string.
      def search(query, k: 3)
        build! unless @built
        return [] if @store.empty?

        query_vector = @embedder.embed([query]).first
        @store.search(query_vector, k: k)
      end

      def empty?
        @sources.empty?
      end
    end
  end
end
