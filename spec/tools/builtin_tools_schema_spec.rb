# frozen_string_literal: true
require 'spec_helper'

RSpec.describe "built-in tool schemas" do
  RCrewAI::Tools::Base.available_tools.each do |klass|
    describe klass do
      it 'declares a tool_name' do
        expect(klass.tool_name).not_to be_empty
      end

      it 'declares a description' do
        expect(klass.description).not_to be_empty
      end

      it 'declares at least one param' do
        expect(klass.params).not_to be_empty
      end

      it 'emits a non-permissive JSON schema' do
        schema = klass.json_schema
        expect(schema.dig(:parameters, :additionalProperties)).to be_nil
        expect(schema.dig(:parameters, :properties)).to be_a(Hash)
      end
    end
  end
end
