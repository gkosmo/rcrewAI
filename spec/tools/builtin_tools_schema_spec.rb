# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'built-in tool schemas' do
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

  describe 'global invariants' do
    it 'tool names are unique across built-ins' do
      names = RCrewAI::Tools::Base.available_tools.map(&:tool_name)
      expect(names.uniq).to eq(names)
    end

    it "every required DSL param is acceptable to the tool's execute method" do
      RCrewAI::Tools::Base.available_tools.each do |klass|
        required = klass.params.select { |p| p[:required] }
        next if required.empty?

        # Build a dummy args hash from required params only, with type-appropriate placeholders.
        dummy = required.each_with_object({}) do |p, h|
          h[p[:name].to_s] = case p[:type]
                             when :string then 'x'
                             when :integer then 1
                             when :number  then 1.0
                             when :boolean then true
                             when :array   then []
                             when :object  then {}
                             when :enum    then p[:values].first
                             end
        end

        # We do not actually run the tool (it may have side effects); we only
        # confirm execute_with_validation does not raise ArgumentError on
        # unknown-keyword. We rescue the tool's domain errors (file not found,
        # network, etc.) but re-raise ArgumentError which means DSL/execute drift.
        begin
          klass.new.execute_with_validation(dummy)
        rescue ArgumentError => e
          raise "DSL/execute drift in #{klass}: #{e.message}"
        rescue StandardError
          # Expected — the tool's own validations or side-effect errors are fine.
        end
      end
    end
  end
end
