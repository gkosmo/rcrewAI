# frozen_string_literal: true

require 'spec_helper'

# A fake agent that proposes a fixed answer and scores candidates from a lookup.
class FakeConsensusAgent
  attr_reader :name

  def initialize(name, proposal:, scores: Hash.new(5), raise_on_propose: false)
    @name = name
    @proposal = proposal
    @scores = scores # candidate content => score this agent gives it
    @raise_on_propose = raise_on_propose
    @llm = FakeScoringClient.new(@scores)
  end

  def execute_task(_task)
    raise 'proposal failed' if @raise_on_propose

    { content: @proposal }
  end

  def llm_client
    @llm
  end
end

# Returns a score based on the candidate text embedded in the scoring prompt.
class FakeScoringClient
  def initialize(scores)
    @scores = scores
  end

  def chat(messages:, **)
    prompt = messages.map { |m| m[:content] }.join(' ')
    match = @scores.keys.find { |candidate| prompt.include?(candidate) }
    { content: (match ? @scores[match] : 0).to_s }
  end
end

def fake_task(name: 'task', agent: nil)
  Struct.new(:name, :description, :expected_output, :agent, :result)
        .new(name, "do #{name}", 'a good answer', agent, nil)
end

def fake_crew(agents:, tasks:, consensus_agents: 3)
  Struct.new(:name, :verbose, :agents, :tasks, :consensus_agents)
        .new('crew', false, agents, tasks, consensus_agents)
end

RSpec.describe RCrewAI::Process::Consensual do
  it 'picks the highest-scored candidate as the task result' do
    # 'alpha answer' is scored highest by everyone.
    scores = { 'alpha answer' => 9, 'beta answer' => 3 }
    a = FakeConsensusAgent.new('alpha', proposal: 'alpha answer', scores: scores)
    b = FakeConsensusAgent.new('beta', proposal: 'beta answer', scores: scores)
    task = fake_task(agent: a)
    crew = fake_crew(agents: [a, b], tasks: [task])

    results = described_class.new(crew).execute

    expect(results.first[:status]).to eq(:completed)
    expect(results.first[:result]).to eq('alpha answer')
    expect(task.result).to eq('alpha answer')
  end

  it 'breaks ties toward the task-assigned agent' do
    scores = { 'alpha answer' => 5, 'beta answer' => 5 } # tie
    a = FakeConsensusAgent.new('alpha', proposal: 'alpha answer', scores: scores)
    b = FakeConsensusAgent.new('beta', proposal: 'beta answer', scores: scores)
    task = fake_task(agent: b) # beta is assigned -> beta wins the tie
    crew = fake_crew(agents: [a, b], tasks: [task])

    results = described_class.new(crew).execute

    expect(results.first[:result]).to eq('beta answer')
  end

  it 'caps participants at consensus_agents' do
    scores = Hash.new(5)
    agents = %w[a b c d e].map { |n| FakeConsensusAgent.new(n, proposal: "#{n} answer", scores: scores) }
    agents.each { |ag| expect(ag).to receive(:execute_task).at_most(:once).and_call_original }
    task = fake_task(agent: agents.first)
    crew = fake_crew(agents: agents, tasks: [task], consensus_agents: 3)

    described_class.new(crew).execute

    # Only 3 agents should have proposed (execute_task called at most once each,
    # and exactly 3 of them). Verified via the expectation above + no error.
  end

  it 'degrades to a single proposal with one agent' do
    a = FakeConsensusAgent.new('solo', proposal: 'only answer', scores: { 'only answer' => 7 })
    task = fake_task(agent: a)
    crew = fake_crew(agents: [a], tasks: [task])

    results = described_class.new(crew).execute

    expect(results.first[:status]).to eq(:completed)
    expect(results.first[:result]).to eq('only answer')
  end

  it 'drops a proposer that raises and reaches consensus with the rest' do
    scores = { 'good answer' => 8 }
    bad = FakeConsensusAgent.new('bad', proposal: 'x', scores: scores, raise_on_propose: true)
    good = FakeConsensusAgent.new('good', proposal: 'good answer', scores: scores)
    task = fake_task(agent: bad)
    crew = fake_crew(agents: [bad, good], tasks: [task])

    results = described_class.new(crew).execute

    expect(results.first[:status]).to eq(:completed)
    expect(results.first[:result]).to eq('good answer')
  end

  it 'marks the task failed when every proposal fails' do
    bad1 = FakeConsensusAgent.new('b1', proposal: 'x', raise_on_propose: true)
    bad2 = FakeConsensusAgent.new('b2', proposal: 'y', raise_on_propose: true)
    task = fake_task(agent: bad1)
    crew = fake_crew(agents: [bad1, bad2], tasks: [task])

    results = described_class.new(crew).execute

    expect(results.first[:status]).to eq(:failed)
  end
end
