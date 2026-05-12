#!/usr/bin/env ruby
# frozen_string_literal: true

# Native function calling end-to-end.
#
# A tool declares a JSON schema via the DSL on Tools::Base. The OpenAI
# client sends that schema as `tools:` in the request payload, the model
# replies with a `tool_calls` block, and ToolRunner dispatches the call,
# threads the result back into the conversation, and continues until the
# model is done.
#
# Run:
#   OPENAI_API_KEY=... ruby examples/native_tools_example.rb

require_relative '../lib/rcrewai'

# 1. Configure the LLM.
RCrewAI.configure do |c|
  c.llm_provider = :openai
  c.openai_model = 'gpt-4o-mini'
end

# 2. Declare a tool with the DSL.
class WeatherTool < RCrewAI::Tools::Base
  tool_name   'get_weather'
  description 'Get the current weather for a city'
  param :city,  type: :string, required: true, description: 'City name'
  param :units, type: :enum, values: %w[metric imperial], default: 'metric'

  def execute(city:, units: 'metric')
    # In a real tool this would call a weather API. We fake it for demo.
    {
      city: city,
      temperature: units == 'metric' ? 22 : 72,
      conditions: 'sunny'
    }
  end
end

# 3. Build an agent that has the tool.
agent = RCrewAI::Agent.new(
  name: 'meteorologist',
  role: 'Helpful weather assistant',
  goal: 'Answer weather questions accurately',
  tools: [WeatherTool.new]
)

# 4. Define and execute a task.
task = RCrewAI::Task.new(
  name: 'weather_check',
  description: "What's the weather in Tokyo?",
  agent: agent,
  expected_output: 'A short sentence about the weather'
)

result = agent.execute_task(task)

puts "Answer:    #{result[:content]}"
puts 'Tool calls:'
result[:tool_calls_history].each do |tc|
  puts "  - #{tc[:tool]}(#{tc[:args]}) -> #{tc[:result]}"
end
puts "Tokens:    #{result.dig(:usage, :total_tokens)}"
puts "Finish:    #{result[:finish_reason]}"
