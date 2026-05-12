#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal stdio MCP server: implements initialize, tools/list, tools/call
# (for one tool: echo).
require 'json'

$stdout.sync = true

loop do
  line = $stdin.gets
  break if line.nil?

  req = JSON.parse(line)
  id = req['id']

  case req['method']
  when 'initialize'
    puts({ jsonrpc: '2.0', id: id, result: {
      protocolVersion: '2024-11-05',
      capabilities: { tools: {} },
      serverInfo: { name: 'echo-server', version: '0.1' }
    } }.to_json)
  when 'tools/list'
    puts({ jsonrpc: '2.0', id: id, result: {
      tools: [{
        name: 'echo',
        description: 'Echoes its input',
        inputSchema: { type: 'object',
                       properties: { message: { type: 'string' } },
                       required: ['message'] }
      }]
    } }.to_json)
  when 'tools/call'
    msg = req.dig('params', 'arguments', 'message')
    puts({ jsonrpc: '2.0', id: id, result: {
      content: [{ type: 'text', text: "echo: #{msg}" }]
    } }.to_json)
  when 'notifications/initialized'
    # no response for notifications
  else
    puts({ jsonrpc: '2.0', id: id,
           error: { code: -32_601, message: 'method not found' } }.to_json)
  end
end
