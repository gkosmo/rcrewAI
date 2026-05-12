# frozen_string_literal: true

require 'json'
require 'open3'

module RCrewAI
  module MCP
    module Transport
      class Stdio
        def initialize(command:, args: [], env: {})
          @command = command
          @args = args
          @env = env
          @stdin = nil
          @stdout = nil
          @stderr_thread = nil
          @wait_thr = nil
        end

        def open
          @stdin, @stdout, stderr, @wait_thr = Open3.popen3(@env, @command, *@args)
          @stderr_thread = Thread.new do
            stderr.each_line { |l| Kernel.warn "[mcp-stderr] #{l}" }
          rescue IOError
            # stream closed
          end
        end

        def send_line(json)
          @stdin.write("#{json}\n")
          @stdin.flush
        end

        def recv_line
          @stdout.gets
        end

        def close
          return unless @wait_thr&.alive?

          begin
            ::Process.kill('TERM', @wait_thr.pid)
          rescue Errno::ESRCH, Errno::EPERM
            # already dead
          end
          @stdin&.close
          @stdout&.close
          @stderr_thread&.kill
        rescue IOError
          # streams already closed
        end
      end
    end
  end
end
