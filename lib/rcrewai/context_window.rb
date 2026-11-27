# frozen_string_literal: true

module RCrewAI
  # Keeps a conversation within a model's context window by dropping the oldest
  # non-system messages when it would overflow. Token counts use a cheap
  # chars/4 heuristic (no tokenizer dependency); the goal is to avoid hard
  # context-length errors, not exact accounting.
  module ContextWindow
    CHARS_PER_TOKEN = 4
    DEFAULT_WINDOW = 8_192

    # Approximate context window sizes (in tokens) by model.
    WINDOWS = {
      'gpt-4o' => 128_000,
      'gpt-4o-mini' => 128_000,
      'gpt-4-turbo' => 128_000,
      'gpt-4' => 8_192,
      'gpt-3.5-turbo' => 16_385,
      'claude-fable-5-1' => 1_000_000,
      'claude-fable-5' => 1_000_000,
      'claude-opus-5-5' => 1_000_000,
      'claude-opus-5' => 1_000_000,
      'claude-opus-4-8' => 1_000_000,
      'claude-opus-4-7' => 1_000_000,
      'claude-opus-4-6' => 1_000_000,
      'claude-sonnet-5-5' => 1_000_000,
      'claude-sonnet-5' => 1_000_000,
      'claude-sonnet-4-6' => 1_000_000,
      'claude-haiku-5-5' => 1_000_000,
      'claude-haiku-4-5' => 200_000,
      'claude-3-5-sonnet-20241022' => 200_000,
      'claude-3-haiku-20240307' => 200_000,
      'gemini-3.8-flash' => 1_000_000,
      'gemini-3.5-flash-lite' => 1_000_000,
      'gemini-1.5-pro' => 1_000_000,
      'gemini-1.5-flash' => 1_000_000
    }.freeze

    module_function

    def estimate_tokens(input)
      text = input.is_a?(Array) ? input.map { |m| message_text(m) }.join : input.to_s
      (text.length / CHARS_PER_TOKEN.to_f).ceil
    end

    def message_text(message)
      "#{message[:content]}#{message[:tool_calls]}"
    end

    def window_for(model)
      WINDOWS[model] || DEFAULT_WINDOW
    end

    # Returns a copy of +messages+ trimmed to fit within (limit - reserve)
    # tokens, dropping the oldest turns first. Always kept: system messages, the
    # latest turn and, once the model has replied, the first user message (the
    # task). An assistant's tool calls and their results are one turn, because
    # providers reject a history that has one without the other.
    def fit(messages, limit:, reserve: 0)
      budget = limit - reserve
      return messages if estimate_tokens(messages) <= budget

      turns = group_turns(messages)
      pinned = [task_turn(turns), turns.last].compact
      droppable = turns.reject { |t| t.first[:role] == 'system' || pinned.any? { |p| p.equal?(t) } }

      until droppable.empty? || estimate_tokens(turns.flatten(1)) <= budget
        oldest = droppable.shift
        turns.delete_if { |t| t.equal?(oldest) }
      end

      turns.flatten(1)
    end

    # -- helpers --------------------------------------------------------------

    def group_turns(messages)
      messages.each_with_object([]) do |message, turns|
        if turns.any? && tool_result?(message, turns.last.last)
          turns.last << message
        else
          turns << [message]
        end
      end
    end

    # The legacy runner has no tool role: a result is the user message that
    # follows a USE_TOOL[...] reply.
    def tool_result?(message, previous)
      return true if message[:role] == 'tool'

      message[:role] == 'user' && previous[:role] == 'assistant' && previous[:content].to_s.include?('USE_TOOL[')
    end

    def task_turn(turns)
      return nil unless turns.any? { |t| t.first[:role] == 'assistant' }

      turns.find { |t| t.first[:role] == 'user' }
    end
  end
end
