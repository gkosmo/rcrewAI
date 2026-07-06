# frozen_string_literal: true

require 'json'
require_relative '../similarity'

module RCrewAI
  class Memory
    # Persistent vector store backed by SQLite. Vectors are packed as
    # little-endian floats; metadata is JSON. Cosine is computed in Ruby over
    # rows filtered by scope — adequate for the thousands-of-memories scale an
    # agent produces; an ANN index is a later optimization.
    #
    # The sqlite3 gem is required lazily so the rest of the library (and the
    # in-memory store) works even if it isn't installed.
    class SqliteStore
      DEFAULT_PATH = File.join(Dir.home, '.rcrewai', 'memory.db')

      def initialize(path: DEFAULT_PATH)
        require 'sqlite3'
        ensure_parent_dir(path) unless path == ':memory:'
        @db = SQLite3::Database.new(path)
        @db.results_as_hash = true
        create_schema
      end

      def add(id:, text:, vector:, scope:, metadata: {})
        @db.execute(
          'INSERT INTO memories (id, scope, text, vector, metadata) VALUES (?, ?, ?, ?, ?) ' \
          'ON CONFLICT(id) DO UPDATE SET scope=excluded.scope, text=excluded.text, ' \
          'vector=excluded.vector, metadata=excluded.metadata',
          [id, scope, text, pack_vector(vector), JSON.generate(metadata || {})]
        )
      end

      def all(scope:)
        @db.execute('SELECT * FROM memories WHERE scope = ?', [scope]).map { |row| to_record(row) }
      end

      def search(vector, k:, scope:)
        all(scope: scope)
          .reject { |r| r[:vector].nil? }
          .map { |r| [r, Similarity.cosine(vector, r[:vector])] }
          .sort_by { |(_r, score)| -score }
          .first(k)
          .map(&:first)
      end

      def delete(scope:)
        @db.execute('DELETE FROM memories WHERE scope = ?', [scope])
      end

      def delete_record(id:, scope:)
        @db.execute('DELETE FROM memories WHERE id = ? AND scope = ?', [id, scope])
      end

      private

      def create_schema
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            scope TEXT NOT NULL,
            text TEXT,
            vector BLOB,
            metadata TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        SQL
        @db.execute('CREATE INDEX IF NOT EXISTS idx_memories_scope ON memories (scope)')
      end

      def ensure_parent_dir(path)
        require 'fileutils'
        FileUtils.mkdir_p(File.dirname(path))
      end

      def pack_vector(vector)
        return nil if vector.nil?

        vector.map(&:to_f).pack('e*')
      end

      def unpack_vector(blob)
        return nil if blob.nil?

        blob.unpack('e*')
      end

      def to_record(row)
        {
          id: row['id'],
          text: row['text'],
          vector: unpack_vector(row['vector']),
          metadata: JSON.parse(row['metadata'] || '{}')
        }
      end
    end
  end
end
