# frozen_string_literal: true

module RCrewAI
  class Harness
    # One allow, ask or block rule. It says whether it applies to a call; the
    # Harness decides between the rules that do.
    class Rule
      attr_reader :effect, :tool_names, :reason

      # A name of any other type would never equal a tool's name, so the rule or
      # hook would silently do nothing.
      def self.tool_name(tool)
        raise ArgumentError, "a tool name must be a Symbol or a String, got #{tool.inspect}" unless (tool.is_a?(String) || tool.is_a?(Symbol)) && !tool.empty?

        tool.to_s.dup.freeze
      end

      def initialize(effect, tools, matching: nil, condition: nil, reason: nil)
        @effect = effect
        @tool_names = names_from(tools)
        @patterns = patterns_from(matching)
        raise ArgumentError, "if: must respond to call, got #{condition.inspect}" unless condition.nil? || condition.respond_to?(:call)

        @condition = condition
        @reason = reason
      end

      def names?(tool_name)
        @tool_names.include?(tool_name)
      end

      def matched_arguments
        @patterns.map(&:first).uniq
      end

      # +args+ has string keys. Raises whatever the +if:+ condition or a Regexp
      # raises; the caller has to treat that as a block.
      def applies?(tool_name, args)
        return false unless names?(tool_name)
        return false unless @patterns.all? { |key, pattern| args.key?(key) && matches?(pattern, args[key]) }

        @condition ? !!@condition.call(args) : true
      end

      private

      # When a value can't be checked, block and ask rules apply and allow rules
      # don't, so doubt never loosens anything.
      def matches?(pattern, value)
        case value
        when String then pattern.match?(value)
        when Array then matches_list?(pattern, value)
        else strict?
        end
      end

      def matches_list?(pattern, list)
        return strict? if list.empty? || !list.all?(String)

        check = ->(item) { pattern.match?(item) }
        strict? ? list.any?(&check) : list.all?(&check)
      end

      def strict?
        @effect != :allow
      end

      def names_from(tools)
        raise ArgumentError, "#{@effect} needs at least one tool name" if tools.empty?

        tools.map { |tool| self.class.tool_name(tool) }.freeze
      end

      # Pairs rather than a Hash, so :path and 'path' can't replace one another.
      def patterns_from(matching)
        return [].freeze if matching.nil?
        raise ArgumentError, "matching: must be a Hash, got #{matching.inspect}" unless matching.is_a?(Hash)

        matching.map { |key, pattern| pattern_pair(key, pattern) }.freeze
      end

      def pattern_pair(key, pattern)
        raise ArgumentError, "matching: keys must be Symbols or Strings, got #{key.inspect}" unless key.is_a?(String) || key.is_a?(Symbol)
        raise ArgumentError, "matching: #{key} must be a Regexp, got #{pattern.inspect}" unless pattern.is_a?(Regexp)

        [key.to_s.dup.freeze, pattern].freeze
      end
    end
  end
end
