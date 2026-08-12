# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'stream sink threading' do
  let(:fake_llm) do
    instance_double('LLMClient').tap do |llm|
      allow(llm).to receive(:chat).and_return(
        content: 'FINAL_ANSWER[done]',
        finish_reason: :stop,
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
      )
      allow(llm).to receive(:supports_native_tools?).and_return(false)
    end
  end

  before { allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(fake_llm) }

  it 'delivers agent-level events to a sink passed to crew.execute' do
    crew  = RCrewAI::Crew.new('observed')
    agent = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write', backstory: 'A writer')
    task  = RCrewAI::Task.new(
      name: 'write', description: 'Write a line', expected_output: 'A line', agent: agent
    )
    crew.add_agent(agent)
    crew.add_task(task)

    received = []
    crew.execute(stream: ->(event) { received << event })

    expect(received).not_to be_empty,
                            'sink received no events — the stream sink is not reaching Agent#execute_task'
    expect(received.map { |e| e.class.name.split('::').last })
      .to include('IterationStart', 'IterationEnd')
  end
end
