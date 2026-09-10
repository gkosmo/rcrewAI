# frozen_string_literal: true

require 'thor'

module RCrewAI
  module Checkpoint
    # Inspects checkpoints written by a crew run.
    class CLI < Thor
      DEFAULT_DIR = '.rcrewai/checkpoints'

      class_option :dir, type: :string, default: DEFAULT_DIR,
                         desc: 'Directory holding checkpoint files'

      desc 'list', 'List saved checkpoint runs'
      def list
        ids = store.list
        if ids.empty?
          puts 'No checkpoints found.'
          return
        end

        puts "Checkpoints in #{options[:dir]}:"
        ids.sort.each do |id|
          record = store.load(id)
          next unless record

          puts "  #{id}  #{summarize(record)}"
        end
      end

      desc 'info RUN_ID', 'Show a checkpoint in detail'
      def info(run_id)
        record = store.load(run_id)
        unless record
          puts "No checkpoint for run id #{run_id}."
          return
        end

        puts "run:     #{record['run_id']}"
        puts "crew:    #{record['crew']}"
        puts "updated: #{record['updated_at']}"
        print_lineage(run_id, record)
        print_tasks(record)
      end

      desc 'delete RUN_ID', 'Delete a checkpoint'
      def delete(run_id)
        unless store.load(run_id)
          puts "No checkpoint for run id #{run_id}."
          return
        end

        store.delete(run_id)
        puts "Deleted checkpoint #{run_id}."
      end

      # Thor exits non-zero on an unhandled error rather than swallowing it.
      def self.exit_on_failure?
        true
      end

      private

      def store
        @store ||= FileStore.new(options[:dir])
      end

      def summarize(record)
        tasks = record['tasks'] || {}
        done = tasks.count { |_n, t| t['status'] == 'completed' }
        "#{record['crew']}  #{done}/#{tasks.size} tasks"
      end

      def print_lineage(run_id, record)
        return unless record['parent_run_id']

        chain = Checkpoint.lineage(store, run_id)
        puts "lineage: #{chain.join(' -> ')}"
      end

      def print_tasks(record)
        tasks = record['tasks'] || {}
        return puts 'tasks:   (none)' if tasks.empty?

        puts 'tasks:'
        tasks.each do |name, entry|
          secs = entry['execution_time']
          timing = secs ? format(' (%.2fs)', secs) : ''
          puts "  #{status_mark(entry['status'])} #{name}  #{entry['status']}#{timing}"
        end
      end

      def status_mark(status)
        status == 'completed' ? '+' : '!'
      end
    end
  end
end
