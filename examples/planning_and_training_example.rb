#!/usr/bin/env ruby
# frozen_string_literal: true

# Crew planning, plus the train/test workflows.
#
#   - planning: true            -> a planner pass drafts a per-task plan and
#                                  folds it into each task's description before
#                                  execution.
#   - crew.train(...)           -> runs the crew repeatedly, collecting feedback
#                                  after each run and persisting it as JSON.
#   - crew.test(...)            -> runs the crew repeatedly and scores each run.
#
# This example stubs the planner LLM and the process so it runs WITHOUT an API
# key, focusing on the wiring.
#
# Run:
#   ruby examples/planning_and_training_example.rb

require_relative '../lib/rcrewai'
require 'tmpdir'

RCrewAI.configure(validate: false) do |c|
  c.llm_provider = :openai
  c.api_key = 'demo-key'
end

# A fake planner client: returns a JSON map of task name -> plan.
class FakePlanner
  def chat(**)
    { content: '{"research": "list 3 sources", "summarize": "write 5 bullets"}' }
  end
end

agent = RCrewAI::Agent.new(name: 'analyst', role: 'Analyst', goal: 'Analyze')
research = RCrewAI::Task.new(name: 'research', description: 'Research the topic', agent: agent)
summarize = RCrewAI::Task.new(name: 'summarize', description: 'Summarize findings', agent: agent)

crew = RCrewAI::Crew.new('analysis', planning: true, planning_llm: FakePlanner.new)
crew.add_agent(agent)
crew.add_task(research)
crew.add_task(summarize)

# Stub the actual task execution so the demo needs no live LLM.
module RCrewAI
  module Process
    class Sequential
      def execute
        [{ status: :completed }]
      end
    end
  end
end

puts '== Planning pass =='
crew.execute
puts "research.description:\n  #{research.description.gsub("\n", "\n  ")}"
puts "summarize.description:\n  #{summarize.description.gsub("\n", "\n  ")}"

puts "\n== Training (feedback persisted to JSON) =="
file = File.join(Dir.tmpdir, 'rcrewai-training-demo.json')
summary = crew.train(
  n_iterations: 3,
  filename: file,
  feedback: ->(iteration, _result) { "run #{iteration}: looked good" }
)
puts "iterations: #{summary[:iterations]}, file: #{summary[:filename]}"
puts File.read(file)
File.delete(file)

puts "\n== Testing (per-run scores) =="
result = crew.test(n_iterations: 3, scorer: ->(_run) { 90.0 + rand(10) })
puts "scores: #{result[:scores].inspect}, average: #{result[:average_score]}"
