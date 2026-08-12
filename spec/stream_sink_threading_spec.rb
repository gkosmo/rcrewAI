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

  it 'releases per-task sink references once execute returns' do
    crew  = RCrewAI::Crew.new('observed-cleanup')
    agent = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write', backstory: 'A writer')
    task  = RCrewAI::Task.new(
      name: 'write', description: 'Write a line', expected_output: 'A line', agent: agent
    )
    crew.add_agent(agent)
    crew.add_task(task)

    received = []
    result = crew.execute(stream: ->(event) { received << event })

    # Events still arrived, so the sink was cleared after use rather than before.
    expect(received).not_to be_empty
    expect(task.stream_sink).to be_nil,
                                'task still holds the caller sink after execute returned'

    # The ensure block must not swallow or replace the return value.
    expect(result).to be_a(Hash)
    expect(result[:results].map { |r| r[:task].name }).to eq(['write'])
    expect(result[:results].first[:status]).to eq(:completed)

    # The crew's own reader stays intact: Process reads crew.stream_sink.
    expect(crew.stream_sink).not_to be_nil
  end

  it 'clears task sinks even when execution raises' do
    crew  = RCrewAI::Crew.new('observed-failure')
    agent = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write', backstory: 'A writer')
    task  = RCrewAI::Task.new(
      name: 'write', description: 'Write a line', expected_output: 'A line', agent: agent
    )
    crew.add_agent(agent)
    crew.add_task(task)

    allow(crew).to receive(:execute_sync).and_raise(RuntimeError, 'boom')

    expect { crew.execute(stream: ->(_event) {}) }.to raise_error(RuntimeError, 'boom')
    expect(task.stream_sink).to be_nil
  end

  it 'nil-initializes stream_sink on a freshly built task' do
    task = RCrewAI::Task.new(name: 'fresh', description: 'Nothing', expected_output: 'Nothing')

    expect(task.stream_sink).to be_nil
  end
end
