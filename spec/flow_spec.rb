# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RCrewAI::Flow do
  describe 'start and listen' do
    it 'runs a single start method' do
      klass = Class.new(described_class) do
        start :begin
        def begin
          state.value = 1
        end
      end

      flow = klass.new
      flow.kickoff

      expect(flow.state.value).to eq(1)
    end

    it 'runs listeners after their trigger, passing the trigger output' do
      klass = Class.new(described_class) do
        start :first
        def first
          'hello'
        end

        listen :first
        def second(prev)
          state.seen = prev
        end
      end

      flow = klass.new
      flow.kickoff

      expect(flow.state.seen).to eq('hello')
    end

    it 'chains listeners transitively' do
      klass = Class.new(described_class) do
        start :a
        def a = 1

        listen :a
        def b(prev) = prev + 1

        listen :b
        def c(prev)
          state.total = prev + 1
        end
      end

      flow = klass.new
      flow.kickoff

      expect(flow.state.total).to eq(3)
    end
  end

  describe 'router' do
    it 'branches based on the routed method output' do
      klass = Class.new(described_class) do
        start :roll
        def roll = state.dice || 6

        router :roll
        def route(prev)
          prev > 3 ? :high : :low
        end

        listen :high
        def on_high
          state.result = 'high'
        end

        listen :low
        def on_low
          state.result = 'low'
        end
      end

      high = klass.new
      high.state.dice = 5
      high.kickoff
      expect(high.state.result).to eq('high')

      low = klass.new
      low.state.dice = 2
      low.kickoff
      expect(low.state.result).to eq('low')
    end
  end

  describe 'and_/or_ combinators' do
    it 'or_ triggers when any listed method completes' do
      klass = Class.new(described_class) do
        start :a
        def a = 1

        start :b
        def b = 2

        listen or_(:a, :b)
        def either
          state.count = (state.count || 0) + 1
        end
      end

      flow = klass.new
      flow.kickoff

      expect(flow.state.count).to eq(2) # fires once per completed trigger
    end

    it 'and_ triggers only after all listed methods complete' do
      klass = Class.new(described_class) do
        start :a
        def a = 1

        start :b
        def b = 2

        listen and_(:a, :b)
        def both
          state.fired = (state.fired || 0) + 1
        end
      end

      flow = klass.new
      flow.kickoff

      expect(flow.state.fired).to eq(1)
    end
  end

  describe 'state' do
    it 'exposes a mutable state object with a unique id' do
      klass = Class.new(described_class) do
        start :noop
        def noop = nil
      end

      flow = klass.new
      expect(flow.state.id).to be_a(String)
      expect(flow.state.id).not_to be_empty
    end

    it 'accepts initial state via kickoff inputs' do
      klass = Class.new(described_class) do
        start :use
        def use
          state.doubled = state.n * 2
        end
      end

      flow = klass.new
      flow.kickoff(inputs: { n: 21 })

      expect(flow.state.doubled).to eq(42)
    end
  end

  describe 'persistence' do
    it 'persists state and restores it by id' do
      store = RCrewAI::Flow::MemoryStateStore.new
      klass = Class.new(described_class) do
        start :grow
        def grow
          state.n = 10
        end
      end

      flow = klass.new(state_store: store)
      flow.kickoff
      id = flow.state.id

      restored = klass.new(state_store: store)
      restored.restore(id)

      expect(restored.state.n).to eq(10)
    end
  end

  describe 'invoking a crew as a step' do
    it 'can run a crew inside a flow method and store the result' do
      crew = instance_double(RCrewAI::Crew)
      allow(crew).to receive(:execute).and_return({ crew: 'c', success_rate: 100.0 })

      klass = Class.new(described_class) do
        start :run_crew
        define_method(:run_crew) do
          state.crew_result = @crew.execute
        end

        def initialize(crew:, **opts)
          super(**opts)
          @crew = crew
        end
      end

      flow = klass.new(crew: crew)
      flow.kickoff

      expect(flow.state.crew_result[:success_rate]).to eq(100.0)
    end
  end

  describe 'human_feedback pause point' do
    it 'invokes the provided feedback handler and exposes the response' do
      klass = Class.new(described_class) do
        start :draft
        def draft
          state.approved = human_feedback('Approve this draft?')
        end
      end

      flow = klass.new(feedback_handler: ->(prompt) { "approved: #{prompt}" })
      flow.kickoff

      expect(flow.state.approved).to eq('approved: Approve this draft?')
    end
  end
end
