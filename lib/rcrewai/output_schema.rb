# frozen_string_literal: true

require 'json'

module RCrewAI
  # Validates and coerces a task's raw string output against a JSON-Schema
  # subset (object / type / required / property types). Used by Task for the
  # `output_schema:` option. Kept intentionally small: it covers the shapes an
  # LLM is realistically asked to emit, not the whole JSON Schema spec.
  module OutputSchema
    module_function

    # Returns the validated/coerced object.
    # Raises OutputSchemaError if the string can't be parsed or doesn't conform.
    def coerce(raw, schema)
      data = parse(raw)
      validate!(data, schema)
      data
    end

    # Extracts a JSON document from a string that may contain surrounding prose,
    # then parses it. Prefers a fenced ```json block, then the first balanced
    # object/array, then the whole string.
    def parse(raw)
      candidate = extract_json(raw.to_s)
      JSON.parse(candidate)
    rescue JSON::ParserError => e
      raise OutputSchemaError, "output is not valid JSON: #{e.message}"
    end

    def extract_json(text)
      if (fenced = text[/```(?:json)?\s*(\{.*?\}|\[.*?\])\s*```/m, 1])
        return fenced
      end

      first = text.index(/[{\[]/)
      last  = text.rindex(/[}\]]/)
      return text if first.nil? || last.nil? || last < first

      text[first..last]
    end

    def validate!(data, schema)
      type = (schema[:type] || schema['type'])&.to_s
      case type
      when 'object' then validate_object!(data, schema)
      when 'array'  then raise_unless(data.is_a?(Array), 'expected an array')
      when 'string' then raise_unless(data.is_a?(String), 'expected a string')
      when 'integer' then raise_unless(data.is_a?(Integer), 'expected an integer')
      when 'number' then raise_unless(data.is_a?(Numeric), 'expected a number')
      when 'boolean' then raise_unless([true, false].include?(data), 'expected a boolean')
      end
      data
    end

    def validate_object!(data, schema)
      raise_unless(data.is_a?(Hash), 'expected a JSON object')

      required = schema[:required] || schema['required'] || []
      required.each do |key|
        raise_unless(data.key?(key.to_s), "missing required property '#{key}'")
      end

      props = schema[:properties] || schema['properties'] || {}
      props.each do |name, subschema|
        value = data[name.to_s]
        next if value.nil?

        validate!(value, subschema)
      end
    end

    def raise_unless(condition, message)
      raise OutputSchemaError, message unless condition
    end
  end

  class OutputSchemaError < Error; end
end
