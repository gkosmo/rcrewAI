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

  it 'delivers events from tasks executed on async worker threads' do
    crew = RCrewAI::Crew.new('async-observed')
    2.times do |i|
      agent = RCrewAI::Agent.new(
        name: "writer#{i}", role: 'Writer', goal: 'Write', backstory: 'A writer'
      )
      crew.add_agent(agent)
      crew.add_task(
        RCrewAI::Task.new(
          name: "write#{i}", description: 'Write a line',
          expected_output: 'A line', agent: agent
        )
      )
    end

    mutex    = Mutex.new
    received = []
    crew.execute(async: true, stream: ->(e) { mutex.synchronize { received << e } })

    expect(received).not_to be_empty
    expect(received.map(&:agent).uniq.compact.size).to be >= 1
  end

  # Events.fan_out serializes delivery: sinks are invoked under a mutex, so a
  # sink shared by several concurrently-running agents is never entered from
  # two threads at once and needs no locking of its own. (Before 0.8.0 it
  # offered no such guarantee and every subscriber had to lock; see
  # spec/events_hierarchy_spec.rb for the serialization contract itself.)
  #
  # Delivery is still driven FROM several pool worker threads -- serialization
  # orders those calls, it does not funnel them onto one thread. This asserts
  # the observable half: one sink really does receive the interleaved output of
  # multiple agents running on distinct workers. Each task runs to completion
  # before +execute+ returns, so the expected agent names and thread count are
  # deterministic. The mutex below is now belt-and-braces rather than required.
  it 'funnels events from concurrently executing agents into one shared sink' do
    crew = RCrewAI::Crew.new('async-shared-sink')
    3.times do |i|
      agent = RCrewAI::Agent.new(
        name: "writer#{i}", role: 'Writer', goal: 'Write', backstory: 'A writer'
      )
      crew.add_agent(agent)
      crew.add_task(
        RCrewAI::Task.new(
          name: "write#{i}", description: 'Write a line',
          expected_output: 'A line', agent: agent
        )
      )
    end

    mutex   = Mutex.new
    records = []
    crew.execute(
      async: true, max_concurrency: 3,
      stream: ->(e) { mutex.synchronize { records << [e.agent, Thread.current.object_id] } }
    )

    # Every agent's events reached the one sink the caller handed to execute.
    expect(records.map(&:first).uniq).to match_array(%w[writer0 writer1 writer2])

    # Delivery was driven from more than one worker thread. fan_out serializes
    # those calls rather than collapsing them onto a single thread, so the
    # distinct-thread count still exceeds one.
    expect(records.map(&:last).uniq.size).to be > 1
  end
end
