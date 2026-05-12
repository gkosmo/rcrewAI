#!/usr/bin/env ruby
# frozen_string_literal: true

# Connect to an MCP server over stdio and expose its tools to an agent.
#
# Prerequisites:
#   # The "filesystem" reference MCP server (Node):
#   npm install -g @modelcontextprotocol/server-filesystem
#   # or run it ad-hoc with npx (no global install):
#   #   command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
#
# Run:
#   OPENAI_API_KEY=... ruby examples/mcp_example.rb

require_relative '../lib/rcrewai'

RCrewAI.configure do |c|
  c.llm_provider = :openai
  c.openai_model = 'gpt-4o-mini'
end

RCrewAI::MCP::Client.with_connection(
  command: 'npx',
  args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp']
) do |client|
  puts "Connected to MCP server: #{client.server_name}"
  puts "Available tools:"
  client.tools.each { |t| puts "  - #{t.name}: #{t.description}" }
  puts

  agent = RCrewAI::Agent.new(
    name: 'fs_agent',
    role: 'Filesystem operator',
    goal: 'Read and summarize files using the filesystem tools',
    tools: client.tools
  )

  task = RCrewAI::Task.new(
    name: 'list_tmp',
    description: 'List the files in /tmp and tell me how many there are.',
    agent: agent,
    expected_output: 'A short summary'
  )

  result = agent.execute_task(task)
  puts "Answer: #{result[:content]}"
  puts "Tool calls: #{result[:tool_calls_history].length}"
end
