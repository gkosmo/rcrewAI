# frozen_string_literal: true

module RCrewAI
  module Tools
    class Base
      attr_reader :name, :description

      def initialize
        @name = self.class.name.split('::').last.downcase
        @description = "Base tool class"
      end

      def execute(**params)
        raise NotImplementedError, "Subclasses must implement #execute method"
      end

      def validate_params!(params, required: [], optional: [])
        # Check required parameters
        missing = required - params.keys
        unless missing.empty?
          raise ToolError, "Missing required parameters: #{missing.join(', ')}"
        end

        # Check for unexpected parameters
        allowed = required + optional
        unexpected = params.keys - allowed
        unless unexpected.empty?
          raise ToolError, "Unexpected parameters: #{unexpected.join(', ')}"
        end
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
        {
          'websearch' => 'Search the web using DuckDuckGo',
          'filereader' => 'Read contents from text files',
          'filewriter' => 'Write content to text files',
          'sqldatabase' => 'Execute SQL queries against databases',
          'emailsender' => 'Send emails via SMTP',
          'codeexecutor' => 'Execute code in various programming languages',
          'pdfprocessor' => 'Read and extract text from PDF files'
        }
      end
    end

    class ToolError < RCrewAI::Error; end
  end
end