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
      'claude-opus-4-7' => 200_000,
      'claude-sonnet-4-6' => 200_000,
      'claude-haiku-4-5' => 200_000,
      'claude-3-5-sonnet-20241022' => 200_000,
      'claude-3-haiku-20240307' => 200_000,
      'gemini-1.5-pro' => 1_000_000,
      'gemini-1.5-flash' => 1_000_000
    }.freeze

    module_function

    def estimate_tokens(input)
      text = input.is_a?(Array) ? input.map { |m| m[:content].to_s }.join : input.to_s
      (text.length / CHARS_PER_TOKEN.to_f).ceil
    end

    def window_for(model)
      WINDOWS[model] || DEFAULT_WINDOW
    end

    # Returns a copy of +messages+ trimmed to fit within (limit - reserve)
    # tokens. System messages are always kept, as is the final message. The
    # oldest non-system, non-final messages are dropped first.
    def fit(messages, limit:, reserve: 0)
      budget = limit - reserve
      return messages if estimate_tokens(messages) <= budget

      system = messages.select { |m| m[:role] == 'system' }
      last = messages.last
      # Candidates for dropping: everything that isn't a system message or the
      # final message, oldest first.
      middle = messages.reject { |m| m[:role] == 'system' || m.equal?(last) }

      kept_middle = middle.dup
      until fits?(system, kept_middle, last, budget) || kept_middle.empty?
        kept_middle.shift # drop the oldest
      end

      rebuild(messages, system, kept_middle, last)
    end

    # -- helpers --------------------------------------------------------------

    def fits?(system, middle, last, budget)
      parts = system + middle
      parts << last unless system.include?(last) || middle.include?(last)
      estimate_tokens(parts) <= budget
    end

    def rebuild(original, system, middle, last)
      keep = (system + middle)
      keep << last unless keep.include?(last)
      # Preserve original ordering.
      original.select { |m| keep.include?(m) }
    end
  end
end
