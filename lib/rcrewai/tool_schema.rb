# frozen_string_literal: true

module RCrewAI
  module ToolSchema
    TYPE_MAP = {
      string: "string", integer: "integer", number: "number",
      boolean: "boolean", array: "array", object: "object", enum: "string"
    }.freeze

    def self.extended(base)
      base.instance_variable_set(:@params, [])
      base.instance_variable_set(:@tool_name, nil)
      base.instance_variable_set(:@description, nil)
    end

    def tool_name(name = nil)
      return @tool_name || name_default if name.nil?
      @tool_name = name.to_s
    end

    def description(desc = nil)
      return @description || "" if desc.nil?
      @description = desc.to_s
    end

    def param(name, type:, required: false, default: nil, description: nil, items: nil, values: nil, properties: nil)
      @params ||= []
      @params << {
        name: name, type: type, required: required, default: default,
        description: description, items: items, values: values, properties: properties
      }
    end

    def params
      @params || []
    end

    def json_schema
      props = {}
      required = []
      params.each do |p|
        entry = { type: TYPE_MAP.fetch(p[:type]) }
        entry[:description] = p[:description] if p[:description]
        entry[:default]     = p[:default]     unless p[:default].nil?
        entry[:items]       = stringify_type(p[:items])   if p[:items]
        entry[:enum]        = p[:values]      if p[:type] == :enum
        entry[:properties]  = p[:properties]  if p[:properties]
        props[p[:name]] = entry
        required << p[:name].to_s if p[:required]
      end

      if params.empty?
        warn_once_no_dsl!
        return {
          name: tool_name,
          description: description,
          parameters: { type: "object", additionalProperties: true }
        }
      end

      {
        name: tool_name,
        description: description,
        parameters: {
          type: "object",
          properties: props,
          required: required
        }
      }
    end

    private

    def name_default
      raw = name.to_s.split("::").last
      return "" if raw.nil? || raw.empty?
      raw.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    def stringify_type(h)
      return h unless h.is_a?(Hash) && h[:type].is_a?(Symbol)
      h.merge(type: TYPE_MAP.fetch(h[:type]))
    end

    def warn_once_no_dsl!
      return if @warned_no_dsl
      @warned_no_dsl = true
      Kernel.warn "[rcrewai] Tool #{name} has no DSL declarations; using permissive schema. Declare tool_name/description/param to opt in to a strict JSON schema."
    end
  end
end
