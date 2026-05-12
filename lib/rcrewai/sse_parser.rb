# frozen_string_literal: true

module RCrewAI
  # Minimal Server-Sent Events line parser.
  # Supports LF and CRLF line terminators (sufficient for OpenAI, Anthropic,
  # Google, and well-behaved MCP HTTP servers). Lone-CR terminators are NOT
  # handled — see https://html.spec.whatwg.org/multipage/server-sent-events.html
  # if that becomes a requirement.
  # Feed bytes via #feed(chunk); yields { event: String, data: String } per complete event.
  class SSEParser
    def initialize(&block)
      @on_event = block
      @buffer = String.new(encoding: Encoding::UTF_8)
      @event = 'message'
      @data_lines = []
    end

    def feed(chunk)
      chunk = chunk.dup.force_encoding(Encoding::UTF_8) unless chunk.encoding == Encoding::UTF_8
      @buffer << chunk
      while (idx = @buffer.index("\n"))
        line = @buffer.slice!(0, idx + 1).chomp
        if line.empty?
          dispatch
        elsif line.start_with?(':')
          # comment line, ignore
        elsif (colon = line.index(':'))
          field = line[0...colon]
          value = line[(colon + 1)..]
          value = value[1..] if value.start_with?(' ')
          handle_field(field, value)
        else
          handle_field(line, '')
        end
      end
    end

    private

    def handle_field(field, value)
      case field
      when 'event' then @event = value
      when 'data'  then @data_lines << value
      end
    end

    def dispatch
      return if @data_lines.empty?

      @on_event.call(event: @event, data: @data_lines.join("\n"))
      @event = 'message'
      @data_lines = []
    end
  end
end
