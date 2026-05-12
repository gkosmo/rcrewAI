# frozen_string_literal: true

module RCrewAI
  module Events
    BASE_ATTRS = %i[type timestamp agent iteration].freeze

    Event           = Struct.new(*BASE_ATTRS, keyword_init: true)
    TextDelta       = Struct.new(*BASE_ATTRS, :text,                                  keyword_init: true)
    TextDone        = Struct.new(*BASE_ATTRS, :text,                                  keyword_init: true)
    ToolCallStart   = Struct.new(*BASE_ATTRS, :tool, :args, :call_id,                 keyword_init: true)
    ToolCallResult  = Struct.new(*BASE_ATTRS, :tool, :call_id, :result, :duration_ms, keyword_init: true)
    ToolCallError   = Struct.new(*BASE_ATTRS, :tool, :call_id, :error,                keyword_init: true)
    Thinking        = Struct.new(*BASE_ATTRS, :text,                                  keyword_init: true)
    Usage           = Struct.new(*BASE_ATTRS, :prompt_tokens, :completion_tokens, :total_tokens, :cost_usd, keyword_init: true)
    IterationStart  = Struct.new(*BASE_ATTRS, :iteration_index,                       keyword_init: true)
    IterationEnd    = Struct.new(*BASE_ATTRS, :finish_reason,                         keyword_init: true)
    Error           = Struct.new(*BASE_ATTRS, :error,                                 keyword_init: true)

    def self.fan_out(sinks)
      sinks = Array(sinks).compact
      lambda do |event|
        sinks.each do |s|
          s.call(event)
        rescue StandardError => e
          Kernel.warn "[rcrewai] event sink raised: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
