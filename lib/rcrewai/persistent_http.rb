# frozen_string_literal: true

require 'net/http'
require 'uri'

module RCrewAI
  # One keep-alive HTTP connection per client for streaming POSTs, so
  # back-to-back calls skip TCP/TLS setup. Requests on a connection are
  # serialised. A stream that does not finish cleanly (cancel, task stop,
  # error) discards the connection; the next call reconnects. Under Ruby's
  # fiber scheduler Net::HTTP yields on IO, so this is reactor-friendly.
  class PersistentHTTP
    RETRYABLE = [EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED].freeze

    def initialize(base_url, timeout:)
      @uri = URI(base_url)
      @timeout = timeout
      @lock = Mutex.new
      @http = nil
    end

    # Yields body chunks as they arrive. Returns the Net::HTTPResponse.
    # Non-2xx responses are returned with their body read (not yielded).
    def post_stream(path, headers:, body:, cancel: nil, &on_chunk)
      @lock.synchronize do
        attempts = 0
        begin
          perform(path, headers, body, cancel, &on_chunk)
        rescue *RETRYABLE
          # A kept-alive connection the server already closed fails before any
          # bytes arrive; retry once on a fresh connection.
          raise if @received || (attempts += 1) > 1

          retry
        end
      end
    end

    def close
      @http&.finish if @http&.started?
    rescue IOError
      nil
    ensure
      @http = nil
    end

    private

    def perform(path, headers, body, cancel, &on_chunk)
      @received = false
      completed = false
      request = Net::HTTP::Post.new(path, headers)
      request.body = body
      response = nil
      connection.request(request) do |res|
        response = res
        unless res.is_a?(Net::HTTPSuccess)
          res.read_body
          next
        end

        res.read_body do |chunk|
          @received = true
          raise StreamCancelled, 'stream cancelled' if cancel&.cancelled?

          on_chunk.call(chunk)
          raise StreamCancelled, 'stream cancelled' if cancel&.cancelled?
        end
      end
      completed = true
      response
    ensure
      close unless completed
    end

    def connection
      return @http if @http&.started?

      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == 'https'
      @http.open_timeout = 10
      @http.read_timeout = @timeout
      @http.keep_alive_timeout = 30
      @http.start
    end
  end
end
