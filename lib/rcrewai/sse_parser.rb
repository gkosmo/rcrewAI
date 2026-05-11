# frozen_string_literal: true

module RCrewAI
  # Minimal Server-Sent Events line parser per
  # https://html.spec.whatwg.org/multipage/server-sent-events.html
  # Feed bytes via #feed(chunk); yields { event: String, data: String } per complete event.
  class SSEParser
    def initialize(&block)
      @on_event = block
      @buffer = +""
      @event = "message"
      @data_lines = []
    end

    def feed(chunk)
      @buffer << chunk
      while (idx = @buffer.index("\n"))
        line = @buffer.slice!(0, idx + 1).chomp
        if line.empty?
          dispatch
        elsif line.start_with?(":")
          # comment line, ignore
        elsif (colon = line.index(":"))
          field = line[0...colon]
          value = line[(colon + 1)..]
          value = value[1..] if value.start_with?(" ")
          handle_field(field, value)
        else
          handle_field(line, "")
        end
      end
    end

    private

    def handle_field(field, value)
      case field
      when "event" then @event = value
      when "data"  then @data_lines << value
      end
    end

    def dispatch
      return if @data_lines.empty?
      @on_event.call(event: @event, data: @data_lines.join("\n"))
      @event = "message"
      @data_lines = []
    end
  end
end
