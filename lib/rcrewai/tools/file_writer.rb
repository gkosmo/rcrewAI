# frozen_string_literal: true

require_relative 'base'
require 'pathname'
require 'fileutils'

module RCrewAI
  module Tools
    class FileWriter < Base
      def initialize(**options)
        super()
        @name = 'filewriter'
        @description = 'Write content to files'
        @max_file_size = options.fetch(:max_file_size, 10_000_000) # 10MB
        @allowed_extensions = options.fetch(:allowed_extensions, %w[.txt .md .json .yaml .yml .csv .log])
        @create_directories = options.fetch(:create_directories, true)
      end

      def execute(**params)
        validate_params!(params, required: [:file_path, :content], optional: [:mode, :encoding])
        
        file_path = params[:file_path]
        content = params[:content]
        mode = params[:mode] || 'w'  # 'w' for write, 'a' for append
        encoding = params[:encoding] || 'utf-8'
        
        begin
          write_file(file_path, content, mode, encoding)
        rescue => e
          "File write failed: #{e.message}"
        end
      end

      private

      def write_file(file_path, content, mode, encoding)
        path = Pathname.new(file_path)
        
        # Security checks
        validate_file_path!(path)
        validate_content!(content)
        validate_mode!(mode)
        
        # Create directory if needed
        create_parent_directories!(path) if @create_directories
        
        # Write the file
        File.open(path, mode, encoding: encoding) do |file|
          file.write(content)
        end
        
        format_write_result(path, content, mode)
      end

      def validate_file_path!(path)
        # Prevent directory traversal
        resolved_path = path.expand_path.to_s
        working_dir = Dir.pwd
        unless resolved_path.start_with?(working_dir)
          raise ToolError, "Access denied: file outside working directory"
        end
        
        # Check file extension
        extension = path.extname.downcase
        unless @allowed_extensions.include?(extension) || @allowed_extensions.include?('*')
          raise ToolError, "File type not allowed: #{extension}"
        end
        
        # If file exists, check if it's writable
        if path.exist?
          raise ToolError, "Path is not a file: #{path}" unless path.file?
          raise ToolError, "File is not writable: #{path}" unless path.writable?
        end
      end

      def validate_content!(content)
        raise ToolError, "Content cannot be nil" if content.nil?
        
        content_size = content.bytesize
        if content_size > @max_file_size
          raise ToolError, "Content too large: #{content_size} bytes (max: #{@max_file_size})"
        end
      end

      def validate_mode!(mode)
        valid_modes = %w[w a w+ a+ wb ab]
        unless valid_modes.include?(mode)
          raise ToolError, "Invalid file mode: #{mode}. Valid modes: #{valid_modes.join(', ')}"
        end
      end

      def create_parent_directories!(path)
        parent_dir = path.parent
        unless parent_dir.exist?
          FileUtils.mkdir_p(parent_dir)
        end
      end

      def format_write_result(path, content, mode)
        action = mode.start_with?('a') ? 'appended to' : 'written to'
        size = content.bytesize
        
        result = "Content successfully #{action} #{path.basename}\n"
        result += "File size: #{size} bytes\n"
        result += "Full path: #{path.expand_path}\n"
        
        if path.exist?
          result += "File modified: #{path.mtime.strftime('%Y-%m-%d %H:%M:%S')}"
        end
        
        result
      end
    end
  end
end