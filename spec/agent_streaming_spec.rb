# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Agent streaming pass-through' do
  it 'forwards events from runner to user sink' do
    fake_llm = double('LLM')
    allow(fake_llm).to receive(:supports_native_tools?).and_return(true)
    allow(fake_llm).to receive(:config).and_return(RCrewAI.configuration)
    allow(fake_llm).to receive(:chat) do |**kwargs|
      kwargs[:stream]&.call(RCrewAI::Events::TextDelta.new(
                              type: :text_delta, timestamp: Time.now,
                              agent: nil, iteration: nil, text: 'hi'
                            ))
      { content: 'hi', tool_calls: [], usage: {}, finish_reason: :stop,
        model: 'm', provider: :openai }
    end

    configure_test_llm
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [])
    agent.instance_variable_set(:@llm_client, fake_llm)

    task = RCrewAI::Task.new(name: 't', description: 'say hi',
                             agent: agent, expected_output: 'x')

    received = []
    agent.execute_task(task, stream: ->(e) { received << e })

    text_events = received.select { |e| e.is_a?(RCrewAI::Events::TextDelta) }
    expect(text_events.map(&:text)).to include('hi')
    expect(text_events.first.agent).to eq('a')
  end
end
