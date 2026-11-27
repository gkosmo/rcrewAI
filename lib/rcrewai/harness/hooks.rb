# frozen_string_literal: true

module RCrewAI
  class Harness
    # What a hook is given. +args+ is the frozen, string-keyed copy the rules
    # saw; +agent+ is the agent's name. +result+ and +error+ are for after
    # hooks, and nil before the tool runs.
    Call = Struct.new(:tool_name, :args, :agent, :call_id, :result, :error, keyword_init: true)

    # Runs a harness's hooks. They run one at a time, each on its own thread
    # with its own timeout, so a hook needn't be thread-safe and a hook that
    # hangs can be abandoned.
    #
    # Before hooks fail closed: only true or nil let a call run. Everything
    # else refuses it, including a hook that raises anything at all (even exit
    # or a stack overflow), times out, or ends its thread without returning.
    class Hooks
      # +hook+ is the label of the hook that refused, +error+ describes how it
      # failed ("RuntimeError: ..." or "timed out after 60 seconds"), and is
      # nil when the hook returned a refusal.
      Refusal = Struct.new(:reason, :hook, :error, keyword_init: true)

      Hook = Struct.new(:phase, :tool_names, :body, :label, keyword_init: true) do
        def applies?(tool_name)
          tool_names.empty? || tool_names.include?(tool_name)
        end
      end

      PASS = Object.new.freeze
      # Marks the threads hooks run on, so a hook that makes a tool call on its
      # own harness is refused at once instead of waiting for the lock its
      # caller holds. A thread variable, so a Fiber inside the hook carries it.
      RUNNING = :rcrewai_harness_hooks

      def initialize(timeout:)
        @timeout = timeout
        @hooks = []
        @lock = Mutex.new
        # Hook threads that were killed but haven't stopped, with their labels.
        # Only read or changed while holding @lock.
        @stuck = {}
      end

      def add(phase, tools, body)
        raise ArgumentError, "#{phase} needs a block: #{phase}(:tool) { |call| ... }" unless body

        names = tools.map { |tool| Rule.tool_name(tool) }.freeze
        position = @hooks.count { |hook| hook.phase == phase } + 1
        label = "#{phase}(#{names.empty? ? '*' : names.join(', ')}) ##{position}".freeze
        @hooks << Hook.new(phase: phase, tool_names: names, body: body, label: label).freeze
        self
      end

      def tool_names(phase)
        @hooks.select { |hook| hook.phase == phase }.flat_map(&:tool_names).uniq
      end

      # Returns a Refusal from the first before hook that refuses, or nil.
      def check_before(call)
        return reentry_refusal if Thread.current.thread_variable_get(RUNNING).equal?(self)

        hooks = @hooks.select { |hook| hook.phase == :before && hook.applies?(call.tool_name) }
        return nil if hooks.empty?

        # The lock is taken before any hook starts, so the time a call waits
        # for it never counts against a hook's timeout.
        @lock.synchronize do
          stuck = stuck_refusal
          return stuck if stuck

          hooks.each do |hook|
            refusal = run_before(hook, call)
            return refusal if refusal
          end
        end
        nil
      end

      private

      def reentry_refusal
        Refusal.new(reason: "A before hook can't make tool calls through the harness that is checking it", hook: nil,
                    error: nil)
      end

      # A killed hook thread still runs its ensure blocks. Until it stops, no
      # other hook on this harness may run, since hooks needn't be thread-safe;
      # rather than wait for it, calls that need a hook are refused.
      def stuck_refusal
        @stuck.delete_if { |thread, _| !thread.alive? }
        return nil if @stuck.empty?

        Refusal.new(reason: "The before hook #{@stuck.values.first} timed out and is still running, so no hooks on " \
                            'this harness can run until it stops, and the call was not run',
                    hook: @stuck.values.first, error: nil)
      end

      def run_before(hook, call)
        thread = Thread.new { verdict(hook, call) }
        outcome = thread.join(@timeout) ? thread.value : timed_out(hook)
        return nil if PASS.equal?(outcome)
        return outcome if outcome.is_a?(Refusal)

        # Only a thread that was killed or exited ends without a verdict.
        failure(hook, 'ended its thread without returning')
      rescue StandardError, ScriptError => e
        failure(hook, "could not be run (#{e.class})")
      ensure
        stop(thread, hook) if thread
      end

      # Kills the hook's thread and gives its cleanup up to one more timeout to
      # finish, still holding the lock. It's recorded as stuck first, so it
      # stays recorded if this wait is interrupted.
      def stop(thread, hook)
        thread.kill
        return unless thread.alive?

        @stuck[thread] = hook.label
        begin
          thread.join(@timeout)
        rescue StandardError, ScriptError
          nil # join re-raises whatever ended the thread; either way it's stopped
        end
        @stuck.delete(thread) unless thread.alive?
      end

      # Runs on the hook's thread. Everything that touches what the hook
      # returned or raised happens here, under the timeout.
      # rubocop:disable Lint/RescueException
      def verdict(hook, call)
        Thread.current.report_on_exception = false
        Thread.current.thread_variable_set(RUNNING, self)
        judge(hook, hook.body.call(call))
      rescue Exception => e # exit, a stack overflow and the rest must refuse too
        raised(hook, e)
      end
      # rubocop:enable Lint/RescueException

      def judge(hook, value)
        return PASS if true.equal?(value) || nil.equal?(value)
        return refusal_from(hook, String.new(value)) if String === value # rubocop:disable Style/CaseEquality

        Refusal.new(reason: "The before hook #{hook.label} returned #{describe(value)}; only true or nil let a " \
                            'call run, and a String refuses it with that reason',
                    hook: hook.label, error: nil)
      end

      def refusal_from(hook, reason)
        reason = "The before hook #{hook.label} refused the call" if reason.strip.empty?
        Refusal.new(reason: reason.freeze, hook: hook.label, error: nil)
      end

      # Bound methods, so an object can't misreport its own class.
      def describe(value)
        klass = Kernel.instance_method(:class).bind_call(value)
        name = Module.instance_method(:name).bind_call(klass) || 'an anonymous class'
        "a value of class #{name}"
      end

      # rubocop:disable Lint/RescueException
      def raised(hook, error)
        klass = Kernel.instance_method(:class).bind_call(error)
        class_name = Module.instance_method(:name).bind_call(klass) || 'an anonymous exception'
        message = begin
          error.message.to_s
        rescue Exception
          '(its message could not be read)'
        end
        Refusal.new(reason: "The before hook #{hook.label} raised #{class_name}, so the call was not run",
                    hook: hook.label, error: "#{class_name}: #{message}")
      rescue Exception
        failure(hook, 'raised an error that could not be described')
      end
      # rubocop:enable Lint/RescueException

      def timed_out(hook)
        failure(hook, "timed out after #{@timeout} seconds")
      end

      def failure(hook, what)
        Refusal.new(reason: "The before hook #{hook.label} #{what}, so the call was not run", hook: hook.label,
                    error: what)
      end
    end
  end
end
