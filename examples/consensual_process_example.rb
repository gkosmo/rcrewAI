#!/usr/bin/env ruby
# frozen_string_literal: true

# Consensual process — agents propose competing answers and vote to pick one.
#
# For each task: up to `consensus_agents` agents each produce a candidate
# answer, every participant scores each candidate 0-10, and the highest-scored
# candidate wins (ties break toward the task's assigned agent).
#
# This example stubs the agents so it runs WITHOUT an API key. In real use each
# agent calls your configured LLM to propose and to score.
#
# Run:
#   ruby examples/consensual_process_example.rb

require_relative '../lib/rcrewai'

RCrewAI.configure(validate: false) do |c|
  c.llm_provider = :openai
  c.api_key = 'demo-key'
end

# A stand-in agent: proposes a fixed answer, and scores candidates by a simple
# rubric (here: answers mentioning "trade-offs" are judged higher). A real
# Agent proposes via execute_task and scores via its llm_client.
class PanelAgent
  attr_reader :name

  def initialize(name, answer)
    @name = name
    @answer = answer
  end

  def execute_task(_task)
    { content: @answer }
  end

  def llm_client
    self
  end

  def chat(messages:, **)
    candidate = messages.first[:content]
    score = candidate.include?('trade-offs') ? 9 : 5
    { content: score.to_s }
  end
end

junior = PanelAgent.new('junior', 'Use PostgreSQL.')
senior = PanelAgent.new('senior', 'Use PostgreSQL, but weigh the trade-offs vs. DynamoDB for scale.')

crew = RCrewAI::Crew.new('architecture_panel', process: :consensual, consensus_agents: 3)
crew.add_agent(junior)
crew.add_agent(senior)

task = RCrewAI::Task.new(name: 'db_choice', description: 'Recommend a database', agent: junior)
crew.add_task(task)

result = crew.execute

puts "process: #{result[:process]}"
puts "consensus winner: #{result[:results].first[:result].inspect}"
puts '(the answer weighing trade-offs scored higher and won)'
