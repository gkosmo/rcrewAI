# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'consensual process concurrency' do
  # Every LLM call sleeps, so serial vs concurrent is visible as wall clock.
  let(:delay) { 0.1 }

  def crew_with(agents: 3, delay: 0.1)
    llm = instance_double('LLMClient')
    allow(llm).to receive(:supports_native_tools?).and_return(false)
    allow(llm).to receive(:chat) do
      sleep delay
      { content: 'FINAL_ANSWER[candidate]', finish_reason: :stop,
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
    end
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(llm)

    crew = RCrewAI::Crew.new('consensus', process: :consensual, consensus_agents: agents)
    agents.times do |i|
      crew.add_agent(RCrewAI::Agent.new(name: "a#{i}", role: 'W', goal: 'G', backstory: 'B'))
    end
    crew.add_task(
      RCrewAI::Task.new(name: 't1', description: 'do it',
                        expected_output: 'out', agent: crew.agents.first)
    )
    crew
  end

  it 'gathers proposals concurrently' do
    crew = crew_with(agents: 3, delay: delay)

    started = Time.now
    crew.execute
    elapsed = Time.now - started

    # Serial: 3 proposals + 9 scores = 12 x 0.1 = 1.2s.
    # Concurrent proposals and scoring should be far below that.
    expect(elapsed).to be < 0.8,
                       "consensus ran serially (#{elapsed.round(2)}s for 3 agents)"
  end

  it 'still produces a completed result' do
    crew = crew_with(agents: 3, delay: 0.01)

    result = crew.execute

    expect(result[:results].first[:status]).to eq(:completed)
    expect(result[:results].first[:result]).to include('candidate')
  end

  it 'drops a proposer that raises without failing the task' do
    good = instance_double('LLMClient')
    allow(good).to receive(:supports_native_tools?).and_return(false)
    allow(good).to receive(:chat).and_return(
      content: 'FINAL_ANSWER[ok]', finish_reason: :stop,
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    )
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(good)

    crew = RCrewAI::Crew.new('consensus', process: :consensual, consensus_agents: 3)
    3.times { |i| crew.add_agent(RCrewAI::Agent.new(name: "a#{i}", role: 'W', goal: 'G', backstory: 'B')) }
    crew.add_task(RCrewAI::Task.new(name: 't1', description: 'd', expected_output: 'o',
                                    agent: crew.agents.first))

    allow(crew.agents[1]).to receive(:execute_task).and_raise('proposer boom')

    result = crew.execute

    expect(result[:results].first[:status]).to eq(:completed)
  end

  it 'fails the task when every proposer fails' do
    llm = instance_double('LLMClient')
    allow(llm).to receive(:supports_native_tools?).and_return(false)
    allow(llm).to receive(:chat).and_return(content: 'x', finish_reason: :stop, usage: {})
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(llm)

    crew = RCrewAI::Crew.new('consensus', process: :consensual, consensus_agents: 2)
    2.times { |i| crew.add_agent(RCrewAI::Agent.new(name: "a#{i}", role: 'W', goal: 'G', backstory: 'B')) }
    crew.add_task(RCrewAI::Task.new(name: 't1', description: 'd', expected_output: 'o',
                                    agent: crew.agents.first))
    crew.agents.each { |a| allow(a).to receive(:execute_task).and_raise('boom') }

    result = crew.execute

    expect(result[:results].first[:status]).to eq(:failed)
  end
end

RSpec.describe 'consensual scoring fan-out' do
  it 'bounds concurrent scoring calls' do
    inflight = 0
    peak = 0
    lock = Mutex.new
    llm = instance_double('LLMClient')
    allow(llm).to receive(:supports_native_tools?).and_return(false)
    allow(llm).to receive(:chat) do
      lock.synchronize do
        inflight += 1
        peak = [peak, inflight].max
      end
      sleep 0.02
      lock.synchronize { inflight -= 1 }
      { content: 'FINAL_ANSWER[c]', finish_reason: :stop,
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
    end
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(llm)

    crew = RCrewAI::Crew.new('big', process: :consensual, consensus_agents: 6)
    6.times { |i| crew.add_agent(RCrewAI::Agent.new(name: "a#{i}", role: 'W', goal: 'G', backstory: 'B')) }
    crew.add_task(RCrewAI::Task.new(name: 't', description: 'd', expected_output: 'o',
                                    agent: crew.agents.first))

    crew.execute

    # 6 agents x 6 candidates = 36 scoring calls. Without a bound they would
    # all be in flight at once, which is a thundering herd at the provider.
    expect(peak).to be <= 12, "peak in-flight LLM calls was #{peak}"
  end
end
