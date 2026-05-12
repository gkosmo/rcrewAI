#!/usr/bin/env ruby
# frozen_string_literal: true

# Streaming events from agent.execute_task.
#
# Multiple sinks can subscribe to the same stream: one prints tokens as
# they arrive; another tallies cost from Events::Usage. The sinks are
# fanned out independently — exceptions in one don't kill the others.
#
# Run:
#   OPENAI_API_KEY=... ruby examples/streaming_example.rb

require_relative '../lib/rcrewai'

RCrewAI.configure do |c|
  c.llm_provider = :openai
  c.openai_model = 'gpt-4o-mini'
end

agent = RCrewAI::Agent.new(
  name: 'storyteller',
  role: 'Short-story author',
  goal: 'Tell concise, vivid stories'
)
task = RCrewAI::Task.new(
  name: 'tell_story',
  description: 'Tell me a 3-sentence story about a robot and a cat.',
  agent: agent,
  expected_output: 'A 3-sentence story'
)

# Sink 1: print tokens as they arrive.
printer = lambda do |event|
  print event.text if event.is_a?(RCrewAI::Events::TextDelta)
  $stdout.flush
end

# Sink 2: tally cost and tokens.
total_cost   = 0.0
total_tokens = 0
cost_tracker = lambda do |event|
  next unless event.is_a?(RCrewAI::Events::Usage)

  total_cost   += event.cost_usd || 0
  total_tokens += event.total_tokens || 0
end

# Combine sinks (each event flows to both):
fan = RCrewAI::Events.fan_out([printer, cost_tracker])

agent.execute_task(task, stream: fan)

puts
puts "---"
puts "Total tokens: #{total_tokens}"
puts "Total cost:   $#{format('%.4f', total_cost)}"
