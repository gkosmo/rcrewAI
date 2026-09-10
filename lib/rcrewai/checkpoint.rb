# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require 'time'

module RCrewAI
  # Durable execution state for a crew run.
  #
  # A checkpoint records, per task, whether it completed and what it produced.
  # Resuming a run replays those results instead of re-executing the tasks --
  # the expensive part of a crew run is the LLM calls, so skipping a completed
  # task is the whole point.
  #
  # Granularity is task-level: a checkpoint is written after each task settles,
  # so a crash loses at most the task in flight. Stores are pluggable; anything
  # responding to #save(id, record), #load(id), #list and #delete works.
  module Checkpoint
    class CheckpointError < RCrewAI::Error; end

    # Volatile; for tests and single-process runs.
    class MemoryStore
      def initialize
        @data = {}
      end

      def save(id, record)
        @data[id] = deep_dup(record)
      end

      def load(id)
        record = @data[id]
        record && deep_dup(record)
      end

      def list
        @data.keys
      end

      def delete(id)
        @data.delete(id)
        nil
      end

      private

      # Records are plain JSON-shaped data, so a round-trip is a sufficient
      # deep copy and keeps a caller's later mutation from reaching the store.
      def deep_dup(record)
        JSON.parse(JSON.generate(record))
      end
    end

    # One JSON file per run under a directory.
    class FileStore
      def initialize(dir)
        @dir = dir
        FileUtils.mkdir_p(@dir)
      end

      def save(id, record)
        File.write(path_for(id), JSON.pretty_generate(record))
      end

      def load(id)
        path = path_for(id)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path))
      end

      def list
        Dir.glob(File.join(@dir, '*.json')).map { |p| File.basename(p, '.json') }
      end

      def delete(id)
        path = path_for(id)
        File.delete(path) if File.exist?(path)
        nil
      end

      private

      # Run ids reach here from callers and from stored records, so a path
      # separator or traversal segment must not be able to steer the write
      # outside the checkpoint directory.
      def path_for(id)
        s = id.to_s
        raise CheckpointError, "invalid run id: #{id.inspect}" if s.empty? ||
                                                                  s.include?('/') ||
                                                                  s.include?('\\') ||
                                                                  s == '.' || s == '..'

        File.join(@dir, "#{s}.json")
      end
    end

    module_function

    def new_run_id
      SecureRandom.uuid
    end

    # Builds the record persisted for a run.
    def record_for(run_id:, crew_name:, tasks:, parent_run_id: nil)
      {
        'run_id' => run_id,
        'parent_run_id' => parent_run_id,
        'crew' => crew_name,
        'updated_at' => Time.now.utc.iso8601,
        'tasks' => tasks
      }
    end

    # Serializes one task's settled state.
    def task_entry(task, status)
      {
        'status' => status.to_s,
        'result' => task.result,
        'execution_time' => task.execution_time
      }
    end

    # Walks parent_run_id links from +run_id+ back to the root, returning the
    # chain oldest-first. Stops on a missing record rather than raising, so a
    # pruned ancestor truncates the chain instead of breaking it.
    def lineage(store, run_id)
      chain = []
      seen = {}
      current = run_id

      while current && !seen[current]
        seen[current] = true
        record = store.load(current)
        break unless record

        chain.unshift(current)
        current = record['parent_run_id']
      end

      chain
    end
  end
end
