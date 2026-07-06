# frozen_string_literal: true

require_relative 'base_memory'

module RCrewAI
  class Memory
    # Tool-call history and outcomes. Replaces the old @tool_usage array;
    # persistable and searchable like the other memory types.
    class ToolMemory < BaseMemory
      def record_call(tool_name, params, result)
        success = !result.to_s.downcase.include?('error')
        text = "#{tool_name}(#{format_params(params)}) -> #{result}"
        add(text, { 'tool' => tool_name, 'success' => success, 'result' => result.to_s })
      end

      # Most-recent-first usage records for a given tool.
      def usage_for(tool_name, limit: 5)
        @store.all(scope: @scope)
              .select { |r| r[:metadata]['tool'] == tool_name }
              .sort_by { |r| -r[:metadata]['seq'].to_i }
              .first(limit)
              .map { |r| r[:text] }
      end

      protected

      def type_suffix
        'tool'
      end

      private

      def format_params(params)
        (params || {}).map { |k, v| "#{k}=#{v}" }.join(', ')
      end
    end
  end
end
