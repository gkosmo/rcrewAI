# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Crew do
  let(:agent) { create_test_agent(name: 'agent') }
  let(:task)  { create_test_task(name: 'task', agent: agent) }

  subject do
    crew = described_class.new('kickoff_crew')
    crew.add_agent(agent)
    crew.add_task(task)
    crew
  end

  before do
    allow_any_instance_of(RCrewAI::Process::Sequential)
      .to receive(:execute).and_return([{ status: :completed }])
  end

  describe 'before_kickoff / after_kickoff hooks' do
    it 'runs a before_kickoff hook before execution' do
      order = []
      allow_any_instance_of(RCrewAI::Process::Sequential).to receive(:execute) do
        order << :execute
        []
      end
      subject.before_kickoff do |inputs|
        order << :before
        inputs
      end

      subject.execute

      expect(order).to eq(%i[before execute])
    end

    it 'runs an after_kickoff hook after execution' do
      order = []
      allow_any_instance_of(RCrewAI::Process::Sequential).to receive(:execute) do
        order << :execute
        []
      end
      subject.after_kickoff do |result|
        order << :after
        result
      end

      subject.execute

      expect(order).to eq(%i[execute after])
    end

    it 'lets before_kickoff transform the inputs' do
      seen = nil
      subject.before_kickoff { |inputs| inputs.merge(added: true) }
      subject.after_kickoff  do |result|
        seen = subject.last_inputs
        result
      end

      subject.execute(inputs: { original: 1 })

      expect(seen).to eq({ original: 1, added: true })
    end

    it 'lets after_kickoff transform the result' do
      subject.after_kickoff { |result| result.merge(annotated: true) }

      result = subject.execute

      expect(result[:annotated]).to be true
    end

    it 'runs multiple hooks in registration order' do
      calls = []
      subject.before_kickoff do |i|
        calls << :b1
        i
      end
      subject.before_kickoff do |i|
        calls << :b2
        i
      end
      subject.after_kickoff do |r|
        calls << :a1
        r
      end
      subject.after_kickoff do |r|
        calls << :a2
        r
      end

      subject.execute

      expect(calls).to eq(%i[b1 b2 a1 a2])
    end
  end

  describe '#kickoff_for_each' do
    it 'runs the crew once per input set and returns results in order' do
      seen = []
      subject.before_kickoff do |inputs|
        seen << inputs
        inputs
      end

      results = subject.kickoff_for_each(inputs: [{ n: 1 }, { n: 2 }, { n: 3 }])

      expect(results.length).to eq(3)
      expect(seen).to eq([{ n: 1 }, { n: 2 }, { n: 3 }])
    end

    it 'returns an empty array for empty inputs' do
      expect(subject.kickoff_for_each(inputs: [])).to eq([])
    end

    it 'isolates runs so inputs do not leak between them' do
      captured = []
      subject.before_kickoff do |inputs|
        captured << subject.last_inputs
        inputs
      end

      subject.kickoff_for_each(inputs: [{ a: 1 }, { b: 2 }])

      # each run sees only its own inputs, not a merge of prior runs
      expect(captured).to eq([{ a: 1 }, { b: 2 }])
    end
  end
end
