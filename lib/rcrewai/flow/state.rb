# frozen_string_literal: true

require 'securerandom'

module RCrewAI
  class Flow
    # Mutable, schemaless flow state with a stable unique id. Access attributes
    # as methods (state.foo, state.foo = 1) or via [] / to_h. Mirrors CrewAI's
    # unstructured (dict-based) flow state, with an automatic UUID.
    class State
      def initialize(attributes = {})
        @attributes = {}
        attributes.each { |k, v| @attributes[k.to_sym] = v }
        @attributes[:id] ||= SecureRandom.uuid
      end

      def id
        @attributes[:id]
      end

      def [](key)
        @attributes[key.to_sym]
      end

      def []=(key, value)
        @attributes[key.to_sym] = value
      end

      def to_h
        @attributes.dup
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end

      def method_missing(name, *args)
        key = name.to_s
        if key.end_with?('=')
          @attributes[key[0..-2].to_sym] = args.first
        else
          @attributes[name]
        end
      end
    end
  end
end
