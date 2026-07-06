# frozen_string_literal: true

require_relative '../similarity'

module RCrewAI
  class Memory
    # Default, volatile vector store: records live in a Hash keyed by scope.
    # Records: { id:, text:, vector:, metadata: }. Cosine search in Ruby.
    class InMemoryStore
      def initialize
        @scopes = Hash.new { |h, k| h[k] = {} }
      end

      def add(id:, text:, vector:, scope:, metadata: {})
        @scopes[scope][id] = { id: id, text: text, vector: vector, metadata: metadata || {} }
      end

      def all(scope:)
        @scopes[scope].values
      end

      def search(vector, k:, scope:)
        @scopes[scope].values
                      .reject { |r| r[:vector].nil? }
                      .map { |r| [r, Similarity.cosine(vector, r[:vector])] }
                      .sort_by { |(_r, score)| -score }
                      .first(k)
                      .map(&:first)
      end

      def delete(scope:)
        @scopes.delete(scope)
      end

      def delete_record(id:, scope:)
        @scopes[scope].delete(id)
      end
    end
  end
end
