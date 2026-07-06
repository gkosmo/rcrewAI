# frozen_string_literal: true

require 'digest'
require_relative '../similarity'
require_relative 'in_memory_store'

module RCrewAI
  class Memory
    # Shared behavior for the memory types: embed-on-write (when an embedder is
    # present) and semantic recall with a lexical fallback when it isn't.
    # Records are namespaced per (agent) scope + a type suffix so different
    # memory types don't collide in a shared store.
    class BaseMemory
      def initialize(scope:, embedder: nil, store: nil, limit: nil)
        @scope = "#{scope}:#{type_suffix}"
        @embedder = embedder
        @store = store || InMemoryStore.new
        @limit = limit
        @seq = 0
      end

      def record(text, metadata = {})
        add(text, metadata)
      end

      def recall(query, limit: 3)
        records = search_records(query, limit)
        records.map { |r| format(r) }
      end

      def count
        @store.all(scope: @scope).length
      end

      def clear!
        @store.delete(scope: @scope)
      end

      protected

      # Subclasses override to namespace their records.
      def type_suffix
        'base'
      end

      def format(record)
        { text: record[:text], metadata: record[:metadata] }
      end

      def add(text, metadata)
        vector = embed(text)
        id = next_id(text)
        @store.add(id: id, text: text, vector: vector, scope: @scope, metadata: stringify(metadata))
        evict_if_needed
        id
      end

      def search_records(query, limit)
        all = @store.all(scope: @scope)
        return [] if all.empty?

        query_vector = embed(query)
        if query_vector && all.any? { |r| r[:vector] }
          @store.search(query_vector, k: limit, scope: @scope)
        else
          lexical_search(query, all, limit)
        end
      end

      def lexical_search(query, records, limit)
        records
          .map { |r| [r, Similarity.lexical(query, r[:text])] }
          .sort_by { |(_r, score)| -score }
          .first(limit)
          .map(&:first)
      end

      def embed(text)
        return nil unless @embedder

        @embedder.embed([text]).first
      rescue StandardError
        nil # embedding is best-effort; fall back to lexical
      end

      def evict_if_needed
        return unless @limit

        records = @store.all(scope: @scope)
        return if records.length <= @limit

        # records carry a monotonic :seq in metadata; drop the oldest.
        oldest = records.min_by { |r| r[:metadata]['seq'].to_i }
        @store.delete_record(id: oldest[:id], scope: @scope) if @store.respond_to?(:delete_record)
      end

      def next_id(text)
        @seq += 1
        Digest::SHA256.hexdigest("#{@scope}:#{@seq}:#{text}")[0, 24]
      end

      def stringify(metadata)
        (metadata || {}).transform_keys(&:to_s).merge('seq' => @seq)
      end
    end
  end
end
