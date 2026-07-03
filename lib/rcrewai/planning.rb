# frozen_string_literal: true

require 'json'
require_relative 'output_schema'

module RCrewAI
  # Runs a single planning pass over a crew's tasks before execution. Asks an
  # LLM to draft a short, concrete plan for each task and folds that plan into
  # the task's description, so the executing agent starts with a game plan.
  #
  # Mirrors CrewAI's `planning=True`. Best-effort: if the planner errors or
  # returns unparseable output, execution proceeds with the original tasks.
  class Planning
    def initialize(crew, llm: nil, logger: nil)
      @crew = crew
      @llm = llm || LLMClient.for_provider
      @logger = logger
    end

    def plan!
      return if @crew.tasks.empty?

      plans = request_plans
      return if plans.nil? || plans.empty?

      @crew.tasks.each do |task|
        step = plans[task.name] || plans[task.name.to_s]
        task.enrich_description("Plan: #{step}") if step
      end
    rescue StandardError => e
      @logger&.warn("Planning pass failed, continuing without a plan: #{e.message}")
      nil
    end

    private

    def request_plans
      response = @llm.chat(messages: [
                             { role: 'system', content: system_prompt },
                             { role: 'user', content: user_prompt }
                           ])
      content = response.is_a?(Hash) ? response[:content].to_s : response.to_s
      parse_plans(content)
    end

    def parse_plans(content)
      OutputSchema.parse(content)
    rescue OutputSchemaError
      nil
    end

    def system_prompt
      'You are a planning assistant. Given a list of tasks, produce a short, ' \
        'concrete plan for each. Respond ONLY with a JSON object mapping each ' \
        'task name to a one-sentence plan string.'
    end

    def user_prompt
      lines = @crew.tasks.map do |t|
        "- #{t.name}: #{t.description} (expected: #{t.expected_output || 'n/a'})"
      end
      "Tasks:\n#{lines.join("\n")}\n\nReturn JSON: { \"<task name>\": \"<plan>\", ... }"
    end
  end
end
