# frozen_string_literal: true

require 'faraday'
require 'thread'
require_relative '../../sse_parser'

module RCrewAI
  module MCP
    module Transport
      # Streamable HTTP transport for MCP: server pushes JSON-RPC responses
      # via a long-lived SSE stream (GET); client sends requests via POST.
      class Http
        def initialize(url:, headers: {})
          @url = url
          @headers = headers
          @queue = Queue.new
          @sse_thread = nil
        end

        def open
          @http = Faraday.new(url: @url) { |f| f.adapter Faraday.default_adapter }
          @sse_thread = Thread.new { start_sse_stream }
        end

        def send_line(json)
          @http.post('') do |req|
            req.headers.merge!(@headers).merge!('Content-Type' => 'application/json')
            req.body = json
          end
        end

        def recv_line
          @queue.pop
        end

        def close
          @sse_thread&.kill
        end

        private

        def start_sse_stream
          parser = SSEParser.new do |evt|
            @queue << "#{evt[:data]}\n" if evt[:event] == 'message' || evt[:event].nil?
          end
          @http.get('') do |req|
            req.headers.merge!(@headers).merge!('Accept' => 'text/event-stream')
            req.options.on_data = proc { |chunk, _| parser.feed(chunk) }
          end
        end
      end
    end
  end
end
