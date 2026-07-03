# frozen_string_literal: true

require 'json'
require 'fileutils'

module RCrewAI
  class Flow
    # Persists flow state keyed by state id, so a flow can be resumed across
    # restarts. Two built-ins: in-memory (tests / single process) and file-based
    # (JSON on disk). Any object with #save(id, hash) and #load(id) works.
    class MemoryStateStore
      def initialize
        @data = {}
      end

      def save(id, hash)
        @data[id] = hash.dup
      end

      def load(id)
        @data[id]
      end
    end

    # Stores each state as a JSON file named <id>.json under a directory.
    class FileStateStore
      def initialize(dir)
        @dir = dir
        FileUtils.mkdir_p(@dir)
      end

      def save(id, hash)
        File.write(path_for(id), JSON.pretty_generate(hash))
      end

      def load(id)
        path = path_for(id)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path))
      end

      private

      def path_for(id)
        File.join(@dir, "#{id}.json")
      end
    end
  end
end
