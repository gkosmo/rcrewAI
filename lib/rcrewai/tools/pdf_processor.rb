# frozen_string_literal: true

require_relative 'base'
require 'pdf-reader'
require 'pathname'

module RCrewAI
  module Tools
    class PdfProcessor < Base
      def initialize(**options)
        super()
        @name = 'pdfprocessor'
        @description = 'Read and extract text from PDF files'
        @max_file_size = options.fetch(:max_file_size, 50_000_000)  # 50MB
        @max_pages = options.fetch(:max_pages, 100)
        @extract_metadata = options.fetch(:extract_metadata, true)
        @working_directory = options[:working_directory] || Dir.pwd
      end

      def execute(**params)
        validate_params!(
          params, 
          required: [:file_path], 
          optional: [:pages, :extract_text, :extract_metadata, :output_format]
        )
        
        file_path = params[:file_path]
        pages = params[:pages]  # Can be array [1,2,3] or range "1-5" or "all"
        extract_text = params.fetch(:extract_text, true)
        extract_metadata = params.fetch(:extract_metadata, @extract_metadata)
        output_format = params.fetch(:output_format, 'text')  # 'text', 'json', 'markdown'
        
        begin
          validate_pdf_file!(file_path)
          result = process_pdf(file_path, pages, extract_text, extract_metadata)
          format_pdf_result(result, output_format)
        rescue => e
          "PDF processing failed: #{e.message}"
        end
      end

      private

      def validate_pdf_file!(file_path)
        path = Pathname.new(file_path)
        
        # Security and existence checks
        unless path.exist?
          raise ToolError, "PDF file does not exist: #{file_path}"
        end
        
        unless path.file?
          raise ToolError, "Path is not a file: #{file_path}"
        end
        
        unless path.readable?
          raise ToolError, "PDF file is not readable: #{file_path}"
        end
        
        # Check file extension
        unless path.extname.downcase == '.pdf'
          raise ToolError, "File is not a PDF: #{file_path}"
        end
        
        # Check file size
        file_size = path.size
        if file_size > @max_file_size
          raise ToolError, "PDF file too large: #{file_size} bytes (max: #{@max_file_size})"
        end
        
        if file_size == 0
          raise ToolError, "PDF file is empty: #{file_path}"
        end
        
        # Prevent directory traversal
        resolved_path = path.realpath.to_s
        unless resolved_path.start_with?(@working_directory)
          raise ToolError, "Access denied: file outside working directory"
        end
      end

      def process_pdf(file_path, pages_param, extract_text, extract_metadata)
        reader = PDF::Reader.new(file_path)
        
        result = {
          file_path: file_path,
          total_pages: reader.page_count,
          processed_pages: 0,
          text_content: [],
          metadata: {},
          processing_errors: []
        }
        
        # Check page count limit
        if reader.page_count > @max_pages
          raise ToolError, "PDF has too many pages: #{reader.page_count} (max: #{@max_pages})"
        end
        
        # Extract metadata if requested
        if extract_metadata
          result[:metadata] = extract_pdf_metadata(reader)
        end
        
        # Determine which pages to process
        pages_to_process = determine_pages_to_process(pages_param, reader.page_count)
        
        # Extract text if requested
        if extract_text
          result[:text_content] = extract_text_from_pages(reader, pages_to_process, result)
        end
        
        result[:processed_pages] = pages_to_process.length
        result
      end

      def extract_pdf_metadata(reader)
        metadata = {}
        
        begin
          info = reader.info
          metadata[:title] = info[:Title] if info[:Title]
          metadata[:author] = info[:Author] if info[:Author]
          metadata[:subject] = info[:Subject] if info[:Subject]
          metadata[:keywords] = info[:Keywords] if info[:Keywords]
          metadata[:creator] = info[:Creator] if info[:Creator]
          metadata[:producer] = info[:Producer] if info[:Producer]
          metadata[:creation_date] = info[:CreationDate] if info[:CreationDate]
          metadata[:modification_date] = info[:ModDate] if info[:ModDate]
        rescue => e
          metadata[:extraction_error] = "Failed to extract metadata: #{e.message}"
        end
        
        # Add PDF version and security info
        begin
          metadata[:pdf_version] = reader.pdf_version
          metadata[:encrypted] = reader.encrypted?
        rescue => e
          # Ignore errors for version/security info
        end
        
        metadata
      end

      def determine_pages_to_process(pages_param, total_pages)
        return (1..total_pages).to_a if pages_param.nil? || pages_param == 'all'
        
        case pages_param
        when Array
          # Array of page numbers: [1, 3, 5]
          pages_param.select { |p| p.is_a?(Integer) && p >= 1 && p <= total_pages }
        when String
          # Range string: "1-5" or "2,4,6-8"
          parse_page_range_string(pages_param, total_pages)
        when Integer
          # Single page number
          pages_param >= 1 && pages_param <= total_pages ? [pages_param] : []
        when Range
          # Ruby range: 1..5
          pages_param.select { |p| p >= 1 && p <= total_pages }
        else
          raise ToolError, "Invalid pages parameter: #{pages_param}"
        end
      end

      def parse_page_range_string(range_string, total_pages)
        pages = []
        
        range_string.split(',').each do |part|
          part = part.strip
          
          if part.include?('-')
            # Range like "1-5"
            start_page, end_page = part.split('-').map(&:strip).map(&:to_i)
            if start_page > 0 && end_page > 0 && start_page <= end_page
              (start_page..end_page).each do |p|
                pages << p if p <= total_pages
              end
            end
          else
            # Single page number
            page_num = part.to_i
            pages << page_num if page_num > 0 && page_num <= total_pages
          end
        end
        
        pages.uniq.sort
      end

      def extract_text_from_pages(reader, pages_to_process, result)
        text_content = []
        
        pages_to_process.each do |page_num|
          begin
            page = reader.page(page_num)
            page_text = page.text.strip
            
            text_content << {
              page_number: page_num,
              text: page_text,
              character_count: page_text.length,
              word_count: page_text.split(/\s+/).length
            }
            
          rescue => e
            error_msg = "Failed to extract text from page #{page_num}: #{e.message}"
            result[:processing_errors] << error_msg
            
            text_content << {
              page_number: page_num,
              text: "",
              character_count: 0,
              word_count: 0,
              error: error_msg
            }
          end
        end
        
        text_content
      end

      def format_pdf_result(result, output_format)
        case output_format.downcase
        when 'json'
          format_as_json(result)
        when 'markdown'
          format_as_markdown(result)
        else
          format_as_text(result)
        end
      end

      def format_as_text(result)
        output = []
        output << "PDF Processing Results"
        output << "=" * 30
        output << "File: #{File.basename(result[:file_path])}"
        output << "Total Pages: #{result[:total_pages]}"
        output << "Processed Pages: #{result[:processed_pages]}"
        
        if result[:metadata].any?
          output << ""
          output << "Metadata:"
          result[:metadata].each do |key, value|
            output << "  #{key.to_s.capitalize}: #{value}"
          end
        end
        
        if result[:processing_errors].any?
          output << ""
          output << "Processing Errors:"
          result[:processing_errors].each do |error|
            output << "  - #{error}"
          end
        end
        
        if result[:text_content].any?
          output << ""
          output << "Extracted Text:"
          output << "-" * 20
          
          result[:text_content].each do |page_content|
            if page_content[:error]
              output << ""
              output << "Page #{page_content[:page_number]} (ERROR): #{page_content[:error]}"
            elsif page_content[:text].empty?
              output << ""
              output << "Page #{page_content[:page_number]}: [No text content]"
            else
              output << ""
              output << "Page #{page_content[:page_number]} (#{page_content[:word_count]} words):"
              
              # Truncate very long pages for readability
              text = page_content[:text]
              if text.length > 2000
                text = text[0..1997] + "..."
              end
              
              output << text
            end
          end
        end
        
        output.join("\n")
      end

      def format_as_markdown(result)
        output = []
        output << "# PDF Processing Results"
        output << ""
        output << "**File:** `#{File.basename(result[:file_path])}`"
        output << "**Total Pages:** #{result[:total_pages]}"
        output << "**Processed Pages:** #{result[:processed_pages]}"
        
        if result[:metadata].any?
          output << ""
          output << "## Metadata"
          result[:metadata].each do |key, value|
            output << "- **#{key.to_s.capitalize}:** #{value}"
          end
        end
        
        if result[:text_content].any?
          output << ""
          output << "## Extracted Text"
          
          result[:text_content].each do |page_content|
            output << ""
            output << "### Page #{page_content[:page_number]}"
            
            if page_content[:error]
              output << ""
              output << "> ⚠️ **Error:** #{page_content[:error]}"
            elsif page_content[:text].empty?
              output << ""
              output << "> ℹ️ No text content found on this page"
            else
              output << ""
              output << "**Word Count:** #{page_content[:word_count]}"
              output << ""
              output << page_content[:text]
            end
          end
        end
        
        if result[:processing_errors].any?
          output << ""
          output << "## Processing Errors"
          result[:processing_errors].each do |error|
            output << "- #{error}"
          end
        end
        
        output.join("\n")
      end

      def format_as_json(result)
        require 'json'
        JSON.pretty_generate(result)
      end
    end
  end
end