# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::ToolSchema do
  describe 'DSL on Tools::Base subclass' do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name        "demo_tool"
        description      "A demo tool"
        param :query,       type: :string,  required: true, description: "A query"
        param :max_results, type: :integer, default: 10,    description: "How many"
        param :tags,        type: :array,   items: { type: :string }
        param :verbose,     type: :boolean, default: false
        param :mode,        type: :enum,    values: %w[fast slow]

        def execute(query:, max_results: 10, tags: [], verbose: false, mode: "fast")
          { query: query, max_results: max_results }
        end
      end
    end

    it 'exposes tool_name and description' do
      expect(tool_class.tool_name).to eq("demo_tool")
      expect(tool_class.description).to eq("A demo tool")
    end

    it 'emits canonical JSON schema' do
      schema = tool_class.json_schema
      expect(schema[:name]).to eq("demo_tool")
      expect(schema[:description]).to eq("A demo tool")
      expect(schema.dig(:parameters, :type)).to eq("object")
      expect(schema.dig(:parameters, :required)).to eq(["query"])
      props = schema.dig(:parameters, :properties)
      expect(props[:query]).to eq(type: "string", description: "A query")
      expect(props[:max_results]).to include(type: "integer", default: 10)
      expect(props[:tags]).to include(type: "array", items: { type: "string" })
      expect(props[:verbose]).to include(type: "boolean", default: false)
      expect(props[:mode]).to include(type: "string", enum: %w[fast slow])
    end

    it 'instance exposes json_schema' do
      expect(tool_class.new.json_schema).to eq(tool_class.json_schema)
    end
  end

  describe 'fallback when no DSL declared' do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        def execute(**params); params; end
      end
    end

    it 'returns a permissive schema' do
      schema = tool_class.json_schema
      expect(schema[:parameters]).to eq(
        type: "object",
        additionalProperties: true
      )
    end

    it 'prints deprecation warning once per class' do
      expect { tool_class.json_schema }.to output(/no DSL declarations/).to_stderr
      expect { tool_class.json_schema }.not_to output.to_stderr
    end
  end

  describe '#execute_with_validation' do
    let(:tool_class) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name "v"
        description "v"
        param :n, type: :integer, required: true
        def execute(n:); n * 2; end
      end
    end

    it 'coerces string integers' do
      expect(tool_class.new.execute_with_validation({ "n" => "7" })).to eq(14)
    end

    it 'raises ToolError on missing required' do
      expect { tool_class.new.execute_with_validation({}) }
        .to raise_error(RCrewAI::Tools::ToolError, /missing required param: n/i)
    end

    it 'raises ToolError on wrong type' do
      expect { tool_class.new.execute_with_validation({ "n" => "abc" }) }
        .to raise_error(RCrewAI::Tools::ToolError, /n must be integer/i)
    end
  end
end
