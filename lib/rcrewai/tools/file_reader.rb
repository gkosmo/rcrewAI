# frozen_string_literal: true

require_relative 'base'
require 'pathname'

module RCrewAI
  module Tools
    class FileReader < Base
      def initialize(**options)
        super()
        @name = 'filereader'
        @description = 'Read contents from files'
        @max_file_size = options.fetch(:max_file_size, 10_000_000) # 10MB
        @allowed_extensions = options.fetch(:allowed_extensions, %w[.txt .md .json .yaml .yml .csv .log])
      end

      def execute(**params)
        validate_params!(params, required: [:file_path], optional: [:encoding, :lines])
        
        file_path = params[:file_path]
        encoding = params[:encoding] || 'utf-8'
        lines = params[:lines] # Optional: read only N lines
        
        begin
          read_file(file_path, encoding, lines)
        rescue => e
          "File read failed: #{e.message}"
        end
      end

      private

      def read_file(file_path, encoding, lines = nil)
        path = Pathname.new(file_path)
        
        # Security checks
        validate_file_path!(path)
        validate_file_size!(path)
        validate_file_extension!(path)
        
        content = if lines
                   read_lines(path, encoding, lines)
                 else
                   read_full_file(path, encoding)
                 end

        format_file_content(path, content, lines)
      end

      def validate_file_path!(path)
        raise ToolError, "File does not exist: #{path}" unless path.exist?
        raise ToolError, "Path is not a file: #{path}" unless path.file?
        raise ToolError, "File is not readable: #{path}" unless path.readable?
        
        # Prevent directory traversal
        resolved_path = path.realpath.to_s
        working_dir = Dir.pwd
        unless resolved_path.start_with?(working_dir)
          raise ToolError, "Access denied: file outside working directory"
        end
      end

      def validate_file_size!(path)
        size = path.size
        if size > @max_file_size
          raise ToolError, "File too large: #{size} bytes (max: #{@max_file_size})"
        end
      end

      def validate_file_extension!(path)
        extension = path.extname.downcase
        unless @allowed_extensions.include?(extension) || @allowed_extensions.include?('*')
          raise ToolError, "File type not allowed: #{extension}"
        end
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

      def format_file_content(path, content, lines = nil)
        header = "File: #{path.basename}"
        header += " (first #{lines} lines)" if lines
        header += "\nSize: #{path.size} bytes"
        header += "\nModified: #{path.mtime.strftime('%Y-%m-%d %H:%M:%S')}"
        header += "\n" + "="*50 + "\n"
        
        # Truncate very long content for display
        display_content = if content.length > 5000
                           content[0..4997] + "..."
                         else
                           content
                         end
        
        header + display_content
      end
    end
  end
end