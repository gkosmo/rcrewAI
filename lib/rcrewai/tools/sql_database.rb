# frozen_string_literal: true

require_relative 'base'
require 'uri'

module RCrewAI
  module Tools
    class SqlDatabase < Base
      def initialize(**options)
        super()
        @name = 'sqldatabase'
        @description = 'Execute SQL queries against databases (PostgreSQL, MySQL, SQLite)'
        @connection_string = options[:connection_string]
        @database_type = detect_database_type
        @max_results = options.fetch(:max_results, 100)
        @timeout = options.fetch(:timeout, 30)
        setup_database_adapter
      end

      def execute(**params)
        validate_params!(params, required: [:query], optional: [:limit])
        
        query = params[:query].strip
        limit = params[:limit] || @max_results
        
        begin
          validate_query_safety!(query)
          result = execute_query(query, limit)
          format_query_result(query, result)
        rescue => e
          "SQL execution failed: #{e.message}"
        end
      end

      private

      def detect_database_type
        return :sqlite unless @connection_string
        
        uri = URI.parse(@connection_string)
        case uri.scheme
        when 'postgres', 'postgresql'
          :postgresql
        when 'mysql', 'mysql2'
          :mysql
        when 'sqlite', 'sqlite3'
          :sqlite
        else
          :unknown
        end
      end

      def setup_database_adapter
        case @database_type
        when :postgresql
          require 'pg'
        when :mysql
          require 'mysql2'
        when :sqlite
          require 'sqlite3'
        else
          raise ToolError, "Unsupported database type: #{@database_type}"
        end
      rescue LoadError => e
        raise ToolError, "Database adapter not available: #{e.message}. Install the appropriate gem."
      end

      def validate_query_safety!(query)
        query_lower = query.downcase.strip
        
        # Block dangerous operations
        dangerous_keywords = %w[
          drop truncate delete update insert create alter
          grant revoke exec execute call load_file
        ]
        
        dangerous_keywords.each do |keyword|
          if query_lower.include?(keyword)
            raise ToolError, "Unsafe SQL operation detected: #{keyword.upcase}"
          end
        end
        
        # Only allow SELECT statements and safe functions
        unless query_lower.start_with?('select', 'show', 'describe', 'explain')
          raise ToolError, "Only SELECT, SHOW, DESCRIBE, and EXPLAIN queries are allowed"
        end
        
        # Check for suspicious patterns
        if query_lower.include?('--') || query_lower.include?('/*')
          raise ToolError, "SQL comments not allowed for security"
        end
      end

      def execute_query(query, limit)
        case @database_type
        when :postgresql
          execute_postgresql_query(query, limit)
        when :mysql
          execute_mysql_query(query, limit)
        when :sqlite
          execute_sqlite_query(query, limit)
        else
          raise ToolError, "Database execution not implemented for #{@database_type}"
        end
      end

      def execute_postgresql_query(query, limit)
        connection = PG.connect(@connection_string)
        
        # Add LIMIT if not present
        limited_query = add_limit_to_query(query, limit)
        
        result = connection.exec(limited_query)
        rows = result.to_a
        columns = result.fields
        
        { rows: rows, columns: columns, row_count: rows.length }
      ensure
        connection&.close
      end

      def execute_mysql_query(query, limit)
        connection = Mysql2::Client.new(@connection_string)
        
        # Add LIMIT if not present
        limited_query = add_limit_to_query(query, limit)
        
        result = connection.query(limited_query)
        rows = result.to_a
        columns = result.fields
        
        { rows: rows, columns: columns, row_count: rows.length }
      ensure
        connection&.close
      end

      def execute_sqlite_query(query, limit)
        db_path = @connection_string || ':memory:'
        db = SQLite3::Database.new(db_path)
        db.results_as_hash = true
        
        # Add LIMIT if not present
        limited_query = add_limit_to_query(query, limit)
        
        rows = db.execute(limited_query)
        columns = rows.first&.keys || []
        
        { rows: rows, columns: columns, row_count: rows.length }
      ensure
        db&.close
      end

      def add_limit_to_query(query, limit)
        query_lower = query.downcase
        
        # If query already has LIMIT, don't modify
        return query if query_lower.include?('limit')
        
        # Add LIMIT clause
        "#{query.chomp(';')} LIMIT #{limit}"
      end

      def format_query_result(query, result)
        output = []
        output << "SQL Query: #{query}"
        output << "Rows returned: #{result[:row_count]}"
        output << ""
        
        if result[:rows].empty?
          output << "No results found."
        else
          # Create simple table format
          output << format_table(result[:columns], result[:rows])
        end
        
        output.join("\n")
      end

      def format_table(columns, rows)
        return "No data" if rows.empty?
        
        # Calculate column widths
        col_widths = {}
        columns.each do |col|
          col_widths[col] = [col.length, 20].max  # Minimum width of 20
        end
        
        rows.first(10).each do |row|  # Only check first 10 rows for width
          row.each do |key, value|
            value_str = value.to_s
            col_widths[key] = [col_widths[key], value_str.length].min(50)  # Max width of 50
          end
        end
        
        # Build table
        table = []
        
        # Header
        header = columns.map { |col| col.ljust(col_widths[col]) }.join(" | ")
        table << header
        table << "-" * header.length
        
        # Rows (limit display to first 20 rows)
        display_rows = rows.first(20)
        display_rows.each do |row|
          row_str = columns.map do |col|
            value = row[col] || row[col.to_s] || ""
            value_str = value.to_s
            # Truncate long values
            value_str = value_str[0..47] + "..." if value_str.length > 50
            value_str.ljust(col_widths[col])
          end.join(" | ")
          table << row_str
        end
        
        # Add truncation notice if needed
        if rows.length > 20
          table << ""
          table << "(Showing first 20 rows of #{rows.length} total rows)"
        end
        
        table.join("\n")
      end
    end
  end
end