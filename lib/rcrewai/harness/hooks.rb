# frozen_string_literal: true

module RCrewAI
  class Harness
    # What a hook is given. +args+ is the frozen, string-keyed copy the rules
    # saw; +agent+ is the agent's name. +result+ and +error+ are for after
    # hooks, and nil before the tool runs.
    Call = Struct.new(:tool_name, :args, :agent, :call_id, :result, :error, keyword_init: true)

    # Runs a harness's hooks. They run one at a time, before and after hooks
    # alike, each on its own thread with its own timeout, so a hook needn't be
    # thread-safe and a hook that hangs can be abandoned.
    #
    # Before hooks fail closed: only true or nil let a call run. Everything
    # else refuses it, including a hook that raises anything at all (even exit
    # or a stack overflow), times out, or ends its thread without returning.
    #
    # After hooks run once the tool has, so nothing they do can undo the call:
    # a String they return becomes a note for the model, and a hook that fails
    # becomes a note saying so. The tool's result always stands.
    class Hooks
      # +hook+ is the label of the hook that refused, +error+ describes how it
      # failed ("RuntimeError: ..." or "timed out after 60 seconds"), and is
      # nil when the hook returned a refusal.
      Refusal = Struct.new(:reason, :hook, :error, keyword_init: true)

      # What an after hook adds to what the model reads. +error+ is set, as in
      # a Refusal, when the hook failed and +text+ says so.
      Note = Struct.new(:text, :hook, :error, keyword_init: true)

      Hook = Struct.new(:phase, :tool_names, :body, :label, keyword_init: true) do
        def applies?(tool_name)
          tool_names.empty? || tool_names.include?(tool_name)
        end
      end

      PASS = Object.new.freeze
      NO_NOTE = Object.new.freeze
      # Marks the threads hooks run on with the harnesses whose hooks are
      # running there, so a hook that makes a tool call through any of them
      # (its own, or one whose hook led to it) is refused at once instead of
      # waiting for the lock its caller holds. A thread variable, so a Fiber
      # inside the hook carries it. Threads the library starts carry it too:
      # see Hooks.running and Hooks.carrying.
      RUNNING = :rcrewai_harness_hooks

      # This thread's mark, for a thread the library starts to pass on with
      # Hooks.carrying.
      def self.running
        Thread.current.thread_variable_get(RUNNING)
      end

      # Runs the block with +running+ (Hooks.running on the thread that started
      # this one) as this thread's mark, then restores the mark it had, since a
      # pooled thread outlives the block.
      def self.carrying(running)
        previous = Thread.current.thread_variable_get(RUNNING)
        Thread.current.thread_variable_set(RUNNING, running)
        yield
      ensure
        Thread.current.thread_variable_set(RUNNING, previous)
      end

      # Joins +pieces+, then the +notes+ on lines of their own, into the text
      # the model reads after a tool call. Never raises: a tool call that ran
      # must not look failed because its text was in another encoding. Text
      # that joins as it is stays as it is; otherwise every part is made UTF-8.
      def self.model_text(pieces, notes = [])
        head = join(Array(pieces), '')
        notes.empty? ? head : join([head, *notes], "\n")
      end

      def self.join(parts, separator)
        parts.join(separator)
      rescue StandardError
        parts.map { |part| utf8(part) }.join(separator)
      end

      # Valid UTF-8 text for +value+. Bytes that aren't UTF-8 (and characters
      # UTF-8 can't hold) are replaced. Never raises.
      def self.utf8(value)
        text = String.new(String === value ? value : value.to_s) # rubocop:disable Style/CaseEquality
        text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
        text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless text.encoding == Encoding::UTF_8
        text.scrub
      rescue StandardError
        ascii_only(value)
      end

      # For text whose encoding can't be converted (a dummy encoding, say).
      def self.ascii_only(value)
        String.new(value.to_s).b.gsub(/[^\t\n\r\x20-\x7e]/n, '?').force_encoding(Encoding::UTF_8)
      rescue StandardError
        +'(text that could not be read)'
      end

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

      def any?(phase, tool_name)
        @hooks.any? { |hook| hook.phase == phase && hook.applies?(tool_name) }
      end

      def tool_names(phase)
        @hooks.select { |hook| hook.phase == phase }.flat_map(&:tool_names).uniq
      end

      # Returns a Refusal from the first before hook that refuses, or nil.
      def check_before(call)
        return reentry_refusal if reentered?

        hooks = applicable(:before, call)
        return nil if hooks.empty?

        # The lock is taken before any hook starts, so the time a call waits
        # for it never counts against a hook's timeout.
        @lock.synchronize do
          stuck = stuck_label
          return stuck_refusal(stuck) if stuck

          hooks.each do |hook|
            refusal = run_before(hook, call)
            return refusal if refusal
          end
        end
        nil
      end

      # Runs every after hook for +call+ in declaration order and returns their
      # Notes. A hook that fails doesn't stop the later ones. While a timed-out
      # hook is still running, the rest aren't run but reported as failed.
      def run_after(call)
        hooks = applicable(:after, call)
        return [] if hooks.empty?
        # Only a hook calling this directly gets here: its tool calls are
        # refused by check_before. Waiting for the lock would wait for itself.
        return hooks.map { |hook| not_run(hook, 'called from inside a hook on this harness') } if reentered?

        @lock.synchronize do
          hooks.filter_map do |hook|
            stuck = stuck_label
            next not_run(hook, "the hook #{stuck} timed out and is still running") if stuck

            run_after_hook(hook, call)
          end
        end
      end

      private

      def applicable(phase, call)
        @hooks.select { |hook| hook.phase == phase && hook.applies?(call.tool_name) }
      end

      def reentered?
        (Hooks.running || []).any? { |hooks| hooks.equal?(self) }
      end

      def reentry_refusal
        Refusal.new(reason: "A hook can't make tool calls through the harness that is running it", hook: nil,
                    error: nil)
      end

      # A killed hook thread still runs its ensure blocks. Until it stops, no
      # other hook on this harness may run, since hooks needn't be thread-safe;
      # rather than wait for it, calls that need a hook are refused, and after
      # hooks are reported as failed. Returns the stuck hook's label, or nil.
      def stuck_label
        @stuck.delete_if { |thread, _| !thread.alive? }
        @stuck.values.first
      end

      def stuck_refusal(label)
        Refusal.new(reason: "The hook #{label} timed out and is still running, so no hooks on this harness can " \
                            'run until it stops, and the call was not run',
                    hook: label, error: nil)
      end

      def run_before(hook, call)
        running = Hooks.running
        thread = Thread.new { verdict(hook, call, running) }
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

      # Returns a Note, or nil when the hook has nothing to add.
      def run_after_hook(hook, call)
        running = Hooks.running
        thread = Thread.new { note_from(hook, call, running) }
        outcome = thread.join(@timeout) ? thread.value : failed_note(hook, 'timed out', "timed out after #{@timeout} seconds")
        return nil if NO_NOTE.equal?(outcome)
        return outcome if outcome.is_a?(Note)

        failed_note(hook, 'ended its thread', 'ended its thread without returning')
      rescue StandardError, ScriptError => e
        failed_note(hook, e.class.name, "could not be run (#{e.class})")
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
      def verdict(hook, call, running)
        mark_thread(running)
        judge(hook, hook.body.call(call))
      rescue Exception => e # exit, a stack overflow and the rest must refuse too
        raised(hook, e)
      end

      # The after hook's counterpart of #verdict: a non-empty String is a note,
      # any other value adds nothing, and whatever it raises is reported.
      def note_from(hook, call, running)
        mark_thread(running)
        value = hook.body.call(call)
        return NO_NOTE unless String === value # rubocop:disable Style/CaseEquality

        text = Hooks.utf8(value).freeze
        text.empty? ? NO_NOTE : Note.new(text: text, hook: hook.label, error: nil)
      rescue Exception => e # exit, a stack overflow and the rest are reported too
        raised_after(hook, e)
      end

      def raised_after(hook, error)
        class_name, message = error_details(error)
        failed_note(hook, class_name, "#{class_name}: #{message}")
      rescue Exception
        failed_note(hook, 'an error that could not be described', 'raised an error that could not be described')
      end
      # rubocop:enable Lint/RescueException

      # +running+ is the mark of the thread that started the hook's, when that
      # thread was itself running hooks, of this harness or another.
      def mark_thread(running)
        Thread.current.report_on_exception = false
        Thread.current.thread_variable_set(RUNNING, [*running, self].freeze)
      end

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
        class_name, message = error_details(error)
        Refusal.new(reason: "The before hook #{hook.label} raised #{class_name}, so the call was not run",
                    hook: hook.label, error: "#{class_name}: #{message}")
      rescue Exception
        failure(hook, 'raised an error that could not be described')
      end

      # The error's class name and message, read so that the error can't lie
      # about its class or break the report by failing to give a message.
      def error_details(error)
        klass = Kernel.instance_method(:class).bind_call(error)
        class_name = Module.instance_method(:name).bind_call(klass) || 'an anonymous exception'
        message = begin
          Hooks.utf8(error.message)
        rescue Exception
          '(its message could not be read)'
        end
        [class_name, message]
      end
      # rubocop:enable Lint/RescueException

      def timed_out(hook)
        failure(hook, "timed out after #{@timeout} seconds")
      end

      def failure(hook, what)
        Refusal.new(reason: "The before hook #{hook.label} #{what}, so the call was not run", hook: hook.label,
                    error: what)
      end

      def failed_note(hook, what, error)
        Note.new(text: "Note: the after hook #{hook.label} failed (#{what}). The tool call itself was not undone.",
                 hook: hook.label, error: error)
      end

      def not_run(hook, why)
        failed_note(hook, "not run: #{why}", "not run: #{why}")
      end
    end
  end
end
