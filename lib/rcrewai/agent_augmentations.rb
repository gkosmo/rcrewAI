# frozen_string_literal: true

require_relative 'context_window'

module RCrewAI
  # Optional per-task augmentations mixed into Agent: a reasoning/planning pass
  # before answering, and context-window trimming of the message history.
  # Kept in a module so Agent's core stays focused.
  module AgentAugmentations
    def reasoning?
      @reasoning
    end

    def respect_context_window?
      @respect_context_window
    end

    # Trims a message list to fit the model's context window when the agent has
    # respect_context_window enabled; otherwise returns it unchanged. Called by
    # the runners before each LLM call.
    def fit_context(messages)
      return messages unless @respect_context_window

      limit = ContextWindow.window_for(llm_model_name)
      reserve = [RCrewAI.configuration.max_tokens.to_i, 0].max
      ContextWindow.fit(messages, limit: limit, reserve: reserve)
    end

    private

    # Asks the LLM to think through an approach before answering. Retries up to
    # @max_reasoning_attempts if the model returns empty output; returns nil if
    # every attempt is empty (execution then proceeds without a plan).
    def run_reasoning_pass(task)
      prompt = <<~PROMPT
        You are #{role}. Before answering, think step by step about how to best
        accomplish this task. Produce a short, concrete plan (do not answer yet).

        Task: #{task.description}
        Expected Output: #{task.expected_output || 'not specified'}
      PROMPT

      @max_reasoning_attempts.times do
        response = @llm_client.chat(messages: [{ role: 'user', content: prompt }])
        text = (response.is_a?(Hash) ? response[:content] : response).to_s.strip
        return text unless text.empty?
      end
      nil
    rescue StandardError => e
      @logger.warn("Reasoning pass failed: #{e.message}")
      nil
    end

    # Adds the reasoning trace to the user message so the answer pass can use it.
    def inject_reasoning(messages, reasoning)
      messages.map do |msg|
        next msg unless msg[:role] == 'user'

        { role: 'user', content: "#{msg[:content]}\n\nYour plan:\n#{reasoning}" }
      end
    end

    # Best-effort model name from the (possibly wrapped) client, for context
    # window sizing. Falls back to the global configured model.
    def llm_model_name
      if @llm_client.respond_to?(:config) && @llm_client.config.respond_to?(:model)
        @llm_client.config.model
      else
        RCrewAI.configuration.model
      end
    rescue StandardError
      RCrewAI.configuration.model
    end
  end
end
