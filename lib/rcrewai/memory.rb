# frozen_string_literal: true

require 'json'

module RCrewAI
  # Cognitive memory facade. Preserves the original public API
  # (add_execution / add_tool_usage / relevant_executions / tool_usage_for /
  # clear_*! / stats) while delegating to semantic, optionally-persistent
  # memory types (short-term, long-term, entity, tool).
  #
  # Zero-config: `Memory.new` uses an in-memory store and, when no embedder is
  # available, falls back to lexical similarity — so existing code behaves as
  # before, just with better recall once an embedder is configured.
  class Memory
    def initialize(scope: 'default', embedder: nil, store: nil, short_term_limit: 100, entity_extractor: nil)
      @short_term = ShortTermMemory.new(scope: scope, embedder: embedder, store: store, limit: short_term_limit)
      @long_term  = LongTermMemory.new(scope: scope, embedder: embedder, store: store)
      @entity     = EntityMemory.new(scope: scope, embedder: embedder, store: store, extractor: entity_extractor)
      @tool       = ToolMemory.new(scope: scope, embedder: embedder, store: store)
    end

    # --- original API --------------------------------------------------------

    def add_execution(task, result, execution_time)
      success = !result.to_s.downcase.include?('failed')
      text = "Task: #{task.name}\nDescription: #{task.description}\nResult: #{truncate(result, 300)}"
      metadata = {
        'task' => task.name,
        'success' => success,
        'execution_time' => execution_time,
        'result' => result.to_s
      }

      @short_term.record(text, metadata)
      if success
        @long_term.record(text, metadata)
        @entity.observe("#{task.description} #{result}")
      end
      nil
    end

    def add_tool_usage(tool_name, params, result)
      @tool.record_call(tool_name, params, result)
      nil
    end

    # Returns a formatted string of the most relevant past executions, or nil.
    def relevant_executions(task, limit = 3)
      query = "#{task.name} #{task.description}"
      recalled = (@short_term.recall(query, limit: limit) + @long_term.recall(query, limit: limit))
      seen = {}
      unique = recalled.reject { |r| seen[r[:text]].tap { seen[r[:text]] = true } }
      return nil if unique.empty?

      unique.first(limit).map { |r| format_execution(r) }.join("\n---\n")
    end

    def tool_usage_for(tool_name, limit = 5)
      @tool.usage_for(tool_name, limit: limit).join("\n")
    end

    def clear_short_term!
      @short_term.clear!
    end

    def clear_all!
      @short_term.clear!
      @long_term.clear!
      @entity.clear!
      @tool.clear!
    end

    def stats
      {
        short_term_count: @short_term.count,
        long_term_total: @long_term.count,
        entity_count: @entity.entities.length,
        tool_usage_count: @tool.count
      }
    end

    # --- new surface (optional direct access) --------------------------------

    attr_reader :short_term, :long_term, :entity, :tool

    private

    def format_execution(record)
      meta = record[:metadata] || {}
      indicator = meta['success'] == false ? '✗' : '✓'
      "#{indicator} #{record[:text]}"
    end

    def truncate(text, limit)
      str = text.to_s
      str.length > limit ? "#{str[0, limit]}..." : str
    end
  end
end
