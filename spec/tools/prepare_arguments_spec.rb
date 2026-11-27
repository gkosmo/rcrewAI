# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Tools::Base, '#prepare_arguments' do
  let(:tool) do
    Class.new(described_class) do
      tool_name 'prepared'
      description 'prepared'
      param :path, type: :string, required: true
      param :limit, type: :integer

      def execute(**) = raise('prepare_arguments must not execute the tool')
    end.new
  end

  let(:schemaless) do
    Class.new(described_class) do
      def execute(**) = raise('prepare_arguments must not execute the tool')
    end.new
  end

  it 'coerces arguments to their declared types, keyed by symbol' do
    expect(tool.prepare_arguments({ 'path' => 7, 'limit' => '3' })).to eq(path: '7', limit: 3)
  end

  it 'raises ToolError on a missing required param' do
    expect { tool.prepare_arguments({}) }
      .to raise_error(RCrewAI::Tools::ToolError, 'missing required param: path')
  end

  it 'drops undeclared arguments by default' do
    expect(tool.prepare_arguments({ 'path' => 'a', 'x' => 1 })).to eq(path: 'a')
  end

  it 'raises ToolError on an undeclared argument when rejecting them' do
    expect { tool.prepare_arguments({ 'path' => 'a', 'x' => 1 }, reject_undeclared: true) }
      .to raise_error(RCrewAI::Tools::ToolError, 'unknown param: x')
  end

  it 'accepts symbol-keyed declared arguments when rejecting undeclared ones' do
    expect(tool.prepare_arguments({ path: 'a', limit: 2 }, reject_undeclared: true))
      .to eq(path: 'a', limit: 2)
  end

  it 'passes everything through for a tool with no declared params, even when rejecting' do
    expect(schemaless.prepare_arguments({ 'x' => 1 }, reject_undeclared: true)).to eq(x: 1)
  end
end
