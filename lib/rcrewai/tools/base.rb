# frozen_string_literal: true

require_relative '../tool_schema'

module RCrewAI
  module Tools
    class Base
      extend RCrewAI::ToolSchema

      def initialize
        # @name and @description are no longer set here.
        # Instance #name and #description delegate to the class-level DSL
        # (tool_name / description) via the fallback in the reader methods below.
      end

      def name
        @name || self.class.tool_name
      end

      def description
        @description || self.class.description
      end

      def json_schema
        self.class.json_schema
      end

      def execute_with_validation(args_hash)
        coerced = {}
        schema_params = self.class.params

        if schema_params.empty?
          coerced = args_hash.transform_keys(&:to_sym)
          return execute(**coerced)
        end

        schema_params.each do |p|
          key_str = p[:name].to_s
          key_sym = p[:name].to_sym
          if args_hash.key?(key_str)
            raw = args_hash[key_str]
          elsif args_hash.key?(key_sym)
            raw = args_hash[key_sym]
          else
            raise ToolError, "missing required param: #{p[:name]}" if p[:required]

            next
          end
          coerced[key_sym] = coerce(raw, p[:type], p[:name])
        end

        execute(**coerced)
      end

      def execute(**params)
        raise NotImplementedError, 'Subclasses must implement #execute method'
      end

      def validate_params!(params, required: [], optional: [])
        # Check required parameters
        missing = required - params.keys
        raise ToolError, "Missing required parameters: #{missing.join(', ')}" unless missing.empty?

        # Check for unexpected parameters
        allowed = required + optional
        unexpected = params.keys - allowed
        return if unexpected.empty?

        raise ToolError, "Unexpected parameters: #{unexpected.join(', ')}"
      end

      def self.available_tools
        [
          WebSearch,
          FileReader,
          FileWriter,
          SqlDatabase,
          EmailSender,
          CodeExecutor,
          PdfProcessor
        ]
      end

      def self.create_tool(tool_name, **options)
        tool_class = case tool_name.to_s.downcase
                     when 'websearch', 'web_search'
                       WebSearch
                     when 'filereader', 'file_reader'
                       FileReader
                     when 'filewriter', 'file_writer'
                       FileWriter
                     when 'sqldatabase', 'sql_database', 'database'
                       SqlDatabase
                     when 'emailsender', 'email_sender', 'email'
                       EmailSender
                     when 'codeexecutor', 'code_executor', 'code'
                       CodeExecutor
                     when 'pdfprocessor', 'pdf_processor', 'pdf'
                       PdfProcessor
                     else
                       raise ToolError, "Unknown tool: #{tool_name}"
                     end

        tool_class.new(**options)
      end

      def self.list_available_tools
        available_tools.each_with_object({}) do |klass, h|
          h[klass.tool_name] = klass.description
        end
      end

      private

      def coerce(value, type, name)
        case type
        when :integer
          return value if value.is_a?(Integer)

          Integer(value.to_s)
        when :number
          return value if value.is_a?(Numeric)

          Float(value.to_s)
        when :boolean
          return value if [true, false].include?(value)

          %w[true 1 yes].include?(value.to_s.downcase)
        when :string, :enum
          value.to_s
        when :array, :object
          value
        else
          value
        end
      rescue ArgumentError, TypeError
        raise ToolError, "#{name} must be #{type}, got #{value.inspect}"
      end
    end

    class ToolError < RCrewAI::Error; end
  end
end
