# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RCrewAI::ProviderSchema do
  let(:canonical) do
    {
      name: "search",
      description: "Search",
      parameters: {
        type: "object",
        properties: { q: { type: "string", description: "query" } },
        required: ["q"]
      }
    }
  end

  it 'reshapes for OpenAI' do
    expect(described_class.for(:openai, canonical)).to eq(
      type: "function",
      function: canonical
    )
  end

  it 'reshapes for Anthropic' do
    out = described_class.for(:anthropic, canonical)
    expect(out).to eq(
      name: "search",
      description: "Search",
      input_schema: canonical[:parameters]
    )
  end

  it 'reshapes for Google' do
    out = described_class.for(:google, canonical)
    expect(out).to eq(
      function_declarations: [{
        name: "search",
        description: "Search",
        parameters: canonical[:parameters]
      }]
    )
  end

  it 'reshapes for Ollama (same as OpenAI minus wrapper)' do
    out = described_class.for(:ollama, canonical)
    expect(out).to eq(type: "function", function: canonical)
  end

  it 'raises on unknown provider' do
    expect { described_class.for(:unknown, canonical) }
      .to raise_error(ArgumentError, /unknown provider/i)
  end
end
