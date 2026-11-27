# frozen_string_literal: true

require_relative 'base'
require_relative 'path_containment'
require 'pathname'

module RCrewAI
  module Tools
    class FileReader < Base
      tool_name        'file_reader'
      description      'Read the contents of a text file from disk'
      param :file_path, type: :string,  required: true,
                        description: 'Absolute or relative path to the file'
      param :encoding,  type: :string,  default: 'utf-8',
                        description: 'Text encoding (e.g. utf-8, iso-8859-1)'
      param :lines,     type: :integer, required: false,
                        description: 'If set, read only the first N lines'

      def initialize(**options)
        super()
        @max_file_size = options.fetch(:max_file_size, 10_000_000) # 10MB
        @allowed_extensions = options.fetch(:allowed_extensions, %w[.txt .md .json .yaml .yml .csv .log])
      end

      def execute(**params)
        validate_params!(params, required: [:file_path], optional: %i[encoding lines])

        file_path = params[:file_path]
        encoding = params[:encoding] || 'utf-8'
        lines = params[:lines] # Optional: read only N lines

        begin
          read_file(file_path, encoding, lines)
        rescue StandardError => e
          "File read failed: #{e.message}"
        end
      end

      private

      def read_file(file_path, encoding, lines = nil)
        requested = Pathname.new(file_path)

        # Security checks. Containment comes first, so that nothing is revealed
        # about files outside, and everything after uses the resolved path.
        path = contained_path!(requested)
        # Types before anything about the file itself. Both names, or a link
        # called notes.txt could read any file inside.
        validate_file_extension!(requested)
        validate_file_extension!(path)
        validate_file_path!(path, requested)
        validate_file_size!(path)

        content = if lines
                    read_lines(path, encoding, lines)
                  else
                    read_full_file(path, encoding)
                  end

        format_file_content(path, requested.basename, content, lines)
      end

      def contained_path!(path)
        real = PathContainment.resolve(path)
        raise ToolError, 'Access denied: file outside working directory' unless real

        Pathname.new(real)
      end

      # Errors name the path that was asked for, not where it resolved to.
      def validate_file_path!(path, requested)
        raise ToolError, "File does not exist: #{requested}" unless path.exist?
        raise ToolError, "Path is not a file: #{requested}" unless path.file?
        raise ToolError, "File is not readable: #{requested}" unless path.readable?
      end

      def validate_file_size!(path)
        size = path.size
        return unless size > @max_file_size

        raise ToolError, "File too large: #{size} bytes (max: #{@max_file_size})"
      end

      def validate_file_extension!(path)
        extension = path.extname.downcase
        return if @allowed_extensions.include?(extension) || @allowed_extensions.include?('*')

        raise ToolError, "File type not allowed: #{extension}"
      end

      def read_lines(path, encoding, line_count)
        lines = []
        File.open(path, 'r', encoding: encoding) do |file|
          line_count.times do
            line = file.gets
            break unless line

            lines << line.chomp
          end
        end
        lines.join("\n")
      end

      def read_full_file(path, encoding)
        File.read(path, encoding: encoding)
      end

      def format_file_content(path, name, content, lines = nil)
        header = "File: #{name}"
        header += " (first #{lines} lines)" if lines
        header += "\nSize: #{path.size} bytes"
        header += "\nModified: #{path.mtime.strftime('%Y-%m-%d %H:%M:%S')}"
        header += "\n#{'=' * 50}\n"

        # Truncate very long content for display
        display_content = if content.length > 5000
                            "#{content[0..4997]}..."
                          else
                            content
                          end

        header + display_content
      end
    end
  end
end
