# frozen_string_literal: true

require_relative 'base'
require 'open3'
require 'tempfile'
require 'fileutils'

module RCrewAI
  module Tools
    class CodeExecutor < Base
      tool_name        "code_executor"
      description      "Execute code in a sandboxed subprocess"
      param :code,     type: :string,  required: true, description: "Source code to run"
      param :language, type: :enum,    required: true,
                       values: %w[ruby python javascript bash],
                       description: "Language: ruby, python, javascript, or bash"
      param :args,     type: :array,   required: false, items: { type: :string },
                       description: "Optional command-line arguments to pass to the interpreter"
      param :stdin,    type: :string,  required: false,
                       description: "Optional stdin payload"

      def initialize(**options)
        super()
        @timeout = options.fetch(:timeout, 30)
        @max_output_size = options.fetch(:max_output_size, 100_000) # 100KB
        @allowed_languages = options.fetch(:allowed_languages, %w[python ruby javascript bash])
        @working_directory = options[:working_directory] || Dir.mktmpdir('rcrewai_code_')
        @enable_file_operations = options.fetch(:enable_file_operations, false)
        setup_security_restrictions
      end

      def execute(**params)
        validate_params!(params, required: %i[code language], optional: %i[args stdin])

        language = params[:language].to_s.downcase
        code = params[:code]
        args = params[:args] || []
        stdin_input = params[:stdin]

        begin
          validate_execution_params!(language, code)
          result = execute_code(language, code, args, stdin_input)
          format_execution_result(language, code, result)
        rescue StandardError => e
          "Code execution failed: #{e.message}"
        end
      end

      private

      def setup_security_restrictions
        # Create secure working directory
        FileUtils.mkdir_p(@working_directory)
        File.chmod(0o755, @working_directory)

        # Set environment variables for security
        @secure_env = {
          'PATH' => '/usr/local/bin:/usr/bin:/bin',
          'HOME' => @working_directory,
          'TMPDIR' => @working_directory,
          'TEMP' => @working_directory,
          'TMP' => @working_directory
        }
      end

      def validate_execution_params!(language, code)
        unless @allowed_languages.include?(language)
          raise ToolError, "Language not allowed: #{language}. Allowed: #{@allowed_languages.join(', ')}"
        end

        raise ToolError, 'Code cannot be empty' if code.to_s.strip.empty?

        raise ToolError, "Code too long: #{code.length} characters (max: 50,000)" if code.length > 50_000 # 50KB max

        validate_code_safety!(language, code)
      end

      def validate_code_safety!(language, code)
        code_lower = code.downcase

        # Common dangerous patterns across languages
        dangerous_patterns = [
          # System operations
          'system(', 'exec(', 'eval(', 'subprocess', 'os.system',
          'shell_exec', 'passthru', '`', 'require "open3"',

          # File operations (if not explicitly enabled)
          'file.open', 'open(', 'with open', 'fopen', 'file_get_contents',
          'file_put_contents', 'unlink', 'delete', 'remove',

          # Network operations
          'socket', 'http', 'urllib', 'requests', 'net::',
          'tcpsocket', 'udpsocket', 'curl', 'wget',

          # Process operations
          'fork', 'spawn', 'thread', 'process',

          # Dangerous Python imports
          'import os', 'import sys', 'import subprocess', 'import socket',
          'from os', 'from sys', 'from subprocess',

          # Dangerous Ruby requires
          'require "fileutils"', 'require "open3"', 'require "net/',

          # Shell commands
          'rm -', 'sudo', 'chmod', 'chown', 'dd if=', 'mkfs',
          'iptables', 'systemctl', 'service '
        ]

        unless @enable_file_operations
          dangerous_patterns += [
            'file.', 'open(', 'with open', 'fopen', 'file_get_contents',
            'file_put_contents', 'fileutils', 'fs.', 'path.', 'dir.'
          ]
        end

        dangerous_patterns.each do |pattern|
          raise ToolError, "Potentially dangerous code detected: #{pattern}" if code_lower.include?(pattern)
        end

        # Language-specific checks
        case language
        when 'python'
          validate_python_safety!(code_lower)
        when 'ruby'
          validate_ruby_safety!(code_lower)
        when 'javascript', 'node', 'js'
          validate_javascript_safety!(code_lower)
        when 'bash', 'sh'
          validate_bash_safety!(code_lower)
        end
      end

      def validate_python_safety!(code)
        python_dangerous = [
          '__import__', 'getattr', 'setattr', 'delattr', 'hasattr',
          'globals(', 'locals(', 'vars(', 'dir(',
          'compile(', 'exec(', 'eval(',
          'input(', 'raw_input('
        ]

        python_dangerous.each do |pattern|
          raise ToolError, "Dangerous Python construct: #{pattern}" if code.include?(pattern)
        end
      end

      def validate_ruby_safety!(code)
        ruby_dangerous = [
          'instance_eval', 'class_eval', 'module_eval',
          'define_method', 'send(', 'method(',
          'const_get', 'const_set', 'remove_const',
          'gets', 'readline', 'readlines'
        ]

        ruby_dangerous.each do |pattern|
          raise ToolError, "Dangerous Ruby construct: #{pattern}" if code.include?(pattern)
        end
      end

      def validate_javascript_safety!(code)
        js_dangerous = [
          'eval(', 'function(', '=>', 'require(',
          'process.', 'global.', 'this.',
          'document.', 'window.', 'location.',
          'settimeout', 'setinterval'
        ]

        js_dangerous.each do |pattern|
          raise ToolError, "Dangerous JavaScript construct: #{pattern}" if code.include?(pattern)
        end
      end

      def validate_bash_safety!(code)
        bash_dangerous = [
          'rm ', 'sudo', 'su ', 'chmod', 'chown',
          '>', '>>', '|', '&', ';',
          '$(', '`', 'eval ', 'exec ',
          '/etc/', '/proc/', '/sys/', '/dev/'
        ]

        bash_dangerous.each do |pattern|
          raise ToolError, "Dangerous bash construct: #{pattern}" if code.include?(pattern)
        end
      end

      def execute_code(language, code, args, stdin_input)
        case language
        when 'python', 'python3'
          execute_python(code, args, stdin_input)
        when 'ruby'
          execute_ruby(code, args, stdin_input)
        when 'javascript', 'node', 'js'
          execute_javascript(code, args, stdin_input)
        when 'bash', 'sh'
          execute_bash(code, args, stdin_input)
        else
          raise ToolError, "Execution not implemented for language: #{language}"
        end
      end

      def execute_python(code, args, stdin_input)
        with_temp_file(code, '.py') do |file_path|
          command = ['python3', file_path] + args.map(&:to_s)
          execute_command(command, stdin_input)
        end
      end

      def execute_ruby(code, args, stdin_input)
        with_temp_file(code, '.rb') do |file_path|
          command = ['ruby', file_path] + args.map(&:to_s)
          execute_command(command, stdin_input)
        end
      end

      def execute_javascript(code, args, stdin_input)
        with_temp_file(code, '.js') do |file_path|
          command = ['node', file_path] + args.map(&:to_s)
          execute_command(command, stdin_input)
        end
      end

      def execute_bash(code, args, stdin_input)
        with_temp_file(code, '.sh') do |file_path|
          File.chmod(0o755, file_path)
          command = ['bash', file_path] + args.map(&:to_s)
          execute_command(command, stdin_input)
        end
      end

      def with_temp_file(content, extension)
        temp_file = Tempfile.new(['rcrewai_code', extension], @working_directory)
        begin
          temp_file.write(content)
          temp_file.flush
          temp_file.close
          yield temp_file.path
        ensure
          temp_file&.unlink
        end
      end

      def execute_command(command, stdin_input)
        stdout_str = ''
        stderr_str = ''
        exit_status = nil

        # Execute with timeout and security restrictions
        Open3.popen3(@secure_env, *command, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
          # Write stdin if provided
          if stdin_input
            stdin.write(stdin_input)
            stdin.close
          end

          # Set up timeout
          timeout_thread = Thread.new do
            sleep @timeout
            begin
              Process.kill('KILL', wait_thread.pid)
            rescue StandardError
              nil
            end
          end

          begin
            # Read output
            stdout_str = read_with_limit(stdout, @max_output_size)
            stderr_str = read_with_limit(stderr, @max_output_size)

            exit_status = wait_thread.value.exitstatus
          rescue StandardError => e
            exit_status = -1
            stderr_str += "\nExecution error: #{e.message}"
          ensure
            timeout_thread.kill
          end
        end

        {
          stdout: stdout_str,
          stderr: stderr_str,
          exit_status: exit_status,
          success: exit_status.zero?
        }
      end

      def read_with_limit(io, limit)
        output = ''
        while output.bytesize < limit && !io.eof?
          chunk = io.read(1024)
          break unless chunk

          if output.bytesize + chunk.bytesize > limit
            remaining = limit - output.bytesize
            output += chunk[0, remaining]
            output += "\n[OUTPUT TRUNCATED - LIMIT EXCEEDED]"
            break
          else
            output += chunk
          end
        end
        output
      end

      def format_execution_result(language, _code, result)
        output = []
        output << "Code Execution Result (#{language.upcase})"
        output << '=' * 40
        output << "Exit Status: #{result[:exit_status]} (#{result[:success] ? 'SUCCESS' : 'FAILURE'})"
        output << ''

        if result[:stdout] && !result[:stdout].empty?
          output << 'STDOUT:'
          output << result[:stdout]
          output << ''
        end

        if result[:stderr] && !result[:stderr].empty?
          output << 'STDERR:'
          output << result[:stderr]
          output << ''
        end

        output << 'No output produced.' if result[:stdout].empty? && result[:stderr].empty?

        output.join("\n")
      end
    end
  end
end
