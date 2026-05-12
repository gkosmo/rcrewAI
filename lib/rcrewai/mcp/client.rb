# frozen_string_literal: true

require 'json'
require_relative 'transport/stdio'
require_relative 'transport/http'
require_relative 'tool_adapter'

module RCrewAI
  module MCP
    class Error < RCrewAI::Error; end

    # Minimal MCP (Model Context Protocol) JSON-RPC client. Connects to a
    # server via stdio or streamable HTTP, performs the initialize/initialized
    # handshake, lists tools, and exposes them as RCrewAI::Tools::Base instances.
    class Client
      PROTOCOL_VERSION = '2024-11-05'

      attr_reader :server_name, :tools

      def self.connect(**opts)
        new(**opts).tap(&:open)
      end

      def self.with_connection(**opts)
        c = connect(**opts)
        begin
          yield c
        ensure
          c&.close
        end
      end

      def initialize(command: nil, args: [], env: {}, url: nil, headers: {})
        @transport = if url
                       Transport::Http.new(url: url, headers: headers)
                     else
                       Transport::Stdio.new(command: command, args: args, env: env)
                     end
        @request_id = 0
        @tools = []
        @server_name = nil
      end

      def open
        @transport.open
        handshake
        load_tools
      end

      def close
        @transport.close
      end

      def call_tool(name, args)
        result = request('tools/call',
                         name: strip_prefix(name),
                         arguments: args)
        text = result.dig('content', 0, 'text')
        text || result['content']
      end

      private

      def handshake
        info = request('initialize',
                       protocolVersion: PROTOCOL_VERSION,
                       capabilities: { tools: {} },
                       clientInfo: { name: 'rcrewai', version: RCrewAI::VERSION })
        @server_name = info.dig('serverInfo', 'name') || 'mcp'
        notify('notifications/initialized', {})
      end

      def load_tools
        result = request('tools/list', {})
        @tools = Array(result['tools']).map { |t| ToolAdapter.new(self, t, @server_name) }
      end

      def request(method, params)
        @request_id += 1
        msg = { jsonrpc: '2.0', id: @request_id, method: method, params: params }
        @transport.send_line(msg.to_json)
        line = @transport.recv_line
        raise Error, 'connection closed before response' if line.nil?

        reply = JSON.parse(line)
        raise Error, reply['error']['message'] if reply['error']

        reply['result']
      end

      def notify(method, params)
        msg = { jsonrpc: '2.0', method: method, params: params }
        @transport.send_line(msg.to_json)
      end

      def strip_prefix(prefixed_name)
        prefixed_name.sub(/^#{Regexp.escape(@server_name)}__/, '')
      end
    end
  end
end
