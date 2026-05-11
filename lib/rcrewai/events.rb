# frozen_string_literal: true

module RCrewAI
  module Events
    BaseAttrs = %i[type timestamp agent iteration].freeze

    Event           = Struct.new(*BaseAttrs, keyword_init: true)
    TextDelta       = Struct.new(*BaseAttrs, :text,                                  keyword_init: true)
    TextDone        = Struct.new(*BaseAttrs, :text,                                  keyword_init: true)
    ToolCallStart   = Struct.new(*BaseAttrs, :tool, :args, :call_id,                 keyword_init: true)
    ToolCallResult  = Struct.new(*BaseAttrs, :tool, :call_id, :result, :duration_ms, keyword_init: true)
    ToolCallError   = Struct.new(*BaseAttrs, :tool, :call_id, :error,                keyword_init: true)
    Thinking        = Struct.new(*BaseAttrs, :text,                                  keyword_init: true)
    Usage           = Struct.new(*BaseAttrs, :prompt_tokens, :completion_tokens, :total_tokens, :cost_usd, keyword_init: true)
    IterationStart  = Struct.new(*BaseAttrs, :iteration_index,                       keyword_init: true)
    IterationEnd    = Struct.new(*BaseAttrs, :finish_reason,                         keyword_init: true)
    Error           = Struct.new(*BaseAttrs, :error,                                 keyword_init: true)

    def self.fan_out(sinks)
      sinks = Array(sinks).compact
      lambda do |event|
        sinks.each do |s|
          begin
            s.call(event)
          rescue StandardError => e
            Kernel.warn "[rcrewai] event sink raised: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
