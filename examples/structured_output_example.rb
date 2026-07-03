#!/usr/bin/env ruby
# frozen_string_literal: true

# Structured output, guardrails, and file output on a Task.
#
# After the agent produces its answer, a Task can:
#   - validate & coerce it against a JSON schema  (output_schema:)
#   - validate & transform it with a guardrail     (guardrail:)
#   - write it to disk, optionally as markdown      (output_file:, markdown:)
#
# Schema/guardrail failures re-run the agent with the error fed back.
#
# This example stubs the agent so it runs WITHOUT an API key. In real use the
# agent calls your configured LLM.
#
# Run:
#   ruby examples/structured_output_example.rb

require_relative '../lib/rcrewai'
require 'tmpdir'

# A stand-in agent: returns canned responses so we can demonstrate the
# post-processing pipeline deterministically. A real Agent behaves the same
# way from the Task's point of view (it returns { content: "..." }).
class ScriptedAgent
  def initialize(responses)
    @responses = responses
  end

  def tools = []

  def execute_task(_task)
    { content: @responses.shift }
  end
end

puts '== Structured output (with a repair retry) =='
# First response is invalid JSON; the task feeds the error back and retries,
# and the second response conforms to the schema.
agent = ScriptedAgent.new(['sorry, not sure', '{"title": "Q3 Report", "words": 1200}'])

task = RCrewAI::Task.new(
  name: 'extract',
  description: 'Extract the article title and word count as JSON',
  agent: agent,
  output_schema: {
    type: 'object',
    properties: { title: { type: 'string' }, words: { type: 'integer' } },
    required: ['title']
  }
)
task.execute
puts "structured_output: #{task.structured_output.inspect}"
puts "raw_result:        #{task.raw_result.inspect}"

puts "\n== Guardrail (transform + reject/retry) =="
# The guardrail requires the answer to mention a price; the first attempt does
# not, so the task re-runs, and the second attempt passes (and is stripped).
agent = ScriptedAgent.new(['no price yet', '  Final price: $49  '])

guardrail = lambda do |output|
  if output.include?('$')
    [true, output.strip] # accept + transform
  else
    [false, 'must include a price'] # reject with a reason (fed back to the agent)
  end
end

task = RCrewAI::Task.new(
  name: 'quote',
  description: 'Give the final price',
  agent: agent,
  guardrail: guardrail,
  guardrail_max_retries: 2
)
puts "result: #{task.execute.inspect}"

puts "\n== File output (markdown) =="
agent = ScriptedAgent.new(['All systems nominal.'])
path = File.join(Dir.tmpdir, 'rcrewai-report-demo.md')

task = RCrewAI::Task.new(
  name: 'report',
  description: 'Write a status report',
  agent: agent,
  output_file: path,
  markdown: true
)
task.execute
puts "wrote #{path}:"
puts File.read(path)
File.delete(path)
