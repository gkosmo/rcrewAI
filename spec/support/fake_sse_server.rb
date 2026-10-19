# frozen_string_literal: true

require 'socket'
require 'json'

# A tiny HTTP/1.1 keep-alive server that answers every POST with an Anthropic
# Messages SSE stream (chunked). Runs on a thread; counts TCP connections so
# specs can assert connection reuse, and notices clients that hang up early.
class FakeSSEServer
  attr_reader :port, :connections, :requests, :aborted

  def initialize(deltas:, delay: 0.01, usage: { 'input_tokens' => 50, 'cache_read_input_tokens' => 40,
                                                'cache_creation_input_tokens' => 0, 'output_tokens' => 1 })
    @deltas = deltas
    @delay = delay
    @usage = usage
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @connections = 0
    @requests = []
    @aborted = 0
    @thread = Thread.new { accept_loop }
  end

  def url = "http://127.0.0.1:#{@port}"

  def stop
    @thread.kill
    @server.close
  end

  private

  def accept_loop
    loop do
      client = @server.accept
      @connections += 1
      Thread.new(client) { |c| serve(c) }
    end
  rescue IOError
    nil
  end

  def serve(client)
    while (request_line = client.gets)
      headers = {}
      while (line = client.gets) && line != "\r\n"
        key, value = line.split(':', 2)
        headers[key.downcase] = value.strip
      end
      body = client.read(headers['content-length'].to_i)
      @requests << { line: request_line.strip, headers: headers, body: JSON.parse(body) }
      respond(client)
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    @aborted += 1
  ensure
    client.close unless client.closed?
  end

  def respond(client)
    client.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n" \
                 "Connection: keep-alive\r\n\r\n")
    event = lambda do |type, data|
      payload = "event: #{type}\ndata: #{JSON.generate(data)}\n\n"
      client.write("#{payload.bytesize.to_s(16)}\r\n#{payload}\r\n")
      client.flush
    end
    event.call('message_start', { type: 'message_start', message: { usage: @usage } })
    @deltas.each do |text|
      sleep @delay
      event.call('content_block_delta', { type: 'content_block_delta', index: 0,
                                          delta: { type: 'text_delta', text: text } })
    end
    event.call('message_delta', { type: 'message_delta', delta: { stop_reason: 'end_turn' },
                                  usage: { output_tokens: @deltas.size } })
    event.call('message_stop', { type: 'message_stop' })
    client.write("0\r\n\r\n")
  end
end
