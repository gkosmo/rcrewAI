# frozen_string_literal: true

require_relative 'base'
require_relative 'path_containment'
require 'pathname'
require 'fileutils'

module RCrewAI
  module Tools
    class FileWriter < Base
      tool_name        'file_writer'
      description      'Write content to a text file on disk'
      param :file_path, type: :string, required: true, description: 'Path to write to'
      param :content,   type: :string, required: true, description: 'Content to write'
      param :mode,      type: :enum,   default: 'w',   values: %w[w a],
                        description: "Write mode: 'w' to overwrite, 'a' to append"
      param :encoding,  type: :string, default: 'utf-8',
                        description: 'Text encoding'

      def initialize(**options)
        super()
        @max_file_size = options.fetch(:max_file_size, 10_000_000) # 10MB
        @allowed_extensions = options.fetch(:allowed_extensions, %w[.txt .md .json .yaml .yml .csv .log])
        @create_directories = options.fetch(:create_directories, true)
      end

      def execute(**params)
        validate_params!(params, required: %i[file_path content], optional: %i[mode encoding])

        file_path = params[:file_path]
        content = params[:content]
        mode = params[:mode] || 'w' # 'w' for write, 'a' for append
        encoding = params[:encoding] || 'utf-8'

        begin
          write_file(file_path, content, mode, encoding)
        rescue StandardError => e
          "File write failed: #{e.message}"
        end
      end

      private

      def write_file(file_path, content, mode, encoding)
        requested = Pathname.new(file_path)

        # Security checks. Everything after containment uses the resolved path.
        path = contained_path!(requested)
        reject_directory_path!(requested)
        # Both names, or a link called notes.txt could overwrite any file inside.
        validate_file_extension!(requested)
        validate_file_path!(path, requested)
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

      def contained_path!(path)
        real = PathContainment.resolve(path)
        raise ToolError, 'Access denied: file outside working directory' unless real

        Pathname.new(real)
      end

      # Resolving drops a trailing "/" or "/.", which would turn a path to a
      # directory into a path to a file.
      def reject_directory_path!(requested)
        raise ToolError, "Path is not a file: #{requested}" if requested.to_s.end_with?('/', '/.')
      end

      def validate_file_extension!(path)
        extension = path.extname.downcase
        return if @allowed_extensions.include?(extension) || @allowed_extensions.include?('*')

        raise ToolError, "File type not allowed: #{extension}"
      end

      def validate_file_path!(path, requested)
        validate_file_extension!(path)

        # If file exists, check if it's writable
        return unless path.exist?
        raise ToolError, "Path is not a file: #{requested}" unless path.file?
        raise ToolError, "File is not writable: #{requested}" unless path.writable?
      end

      def validate_content!(content)
        raise ToolError, 'Content cannot be nil' if content.nil?

        content_size = content.bytesize
        return unless content_size > @max_file_size

        raise ToolError, "Content too large: #{content_size} bytes (max: #{@max_file_size})"
      end

      def validate_mode!(mode)
        valid_modes = %w[w a w+ a+ wb ab]
        return if valid_modes.include?(mode)

        raise ToolError, "Invalid file mode: #{mode}. Valid modes: #{valid_modes.join(', ')}"
      end

      def create_parent_directories!(path)
        parent_dir = path.parent
        return if parent_dir.exist?

        FileUtils.mkdir_p(parent_dir)
      end

      def format_write_result(path, content, mode)
        action = mode.start_with?('a') ? 'appended to' : 'written to'
        size = content.bytesize

        result = "Content successfully #{action} #{path.basename}\n"
        result += "File size: #{size} bytes\n"
        result += "Full path: #{path.expand_path}\n"

        result += "File modified: #{path.mtime.strftime('%Y-%m-%d %H:%M:%S')}" if path.exist?

        result
      end
    end
  end
end
