# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'event hierarchy and safe fan-out' do
  describe 'event identity' do
    it 'gives every event an id' do
      e = RCrewAI::Events::TextDelta.new(
        type: :text_delta, timestamp: Time.now, agent: 'a', iteration: 0, text: 'hi'
      )
      expect(e.id).to be_a(String)
      expect(e.id).not_to be_empty
    end

    it 'gives distinct events distinct ids' do
      mk = lambda do
        RCrewAI::Events::TextDelta.new(
          type: :text_delta, timestamp: Time.now, agent: 'a', iteration: 0, text: 'hi'
        )
      end
      expect(mk.call.id).not_to eq(mk.call.id)
    end

    it 'accepts an explicit parent_id' do
      e = RCrewAI::Events::TextDelta.new(
        type: :text_delta, timestamp: Time.now, agent: 'a', iteration: 0,
        text: 'hi', parent_id: 'parent-1'
      )
      expect(e.parent_id).to eq('parent-1')
    end

    it 'leaves parent_id nil at the root' do
      e = RCrewAI::Events::TextDelta.new(
        type: :text_delta, timestamp: Time.now, agent: 'a', iteration: 0, text: 'hi'
      )
      expect(e.parent_id).to be_nil
    end
  end

  describe 'RCrewAI::Events.with_parent' do
    it 'stamps parent_id on events emitted inside the block' do
      seen = []
      sink = ->(e) { seen << e }

      RCrewAI::Events.with_parent('span-1') do
        RCrewAI::Events.emit(sink, RCrewAI::Events::TextDelta.new(
                                     type: :text_delta, timestamp: Time.now,
                                     agent: 'a', iteration: 0, text: 'hi'
                                   ))
      end

      expect(seen.first.parent_id).to eq('span-1')
    end

    it 'does not stamp events emitted outside the block' do
      seen = []
      sink = ->(e) { seen << e }

      RCrewAI::Events.with_parent('span-1') { nil }
      RCrewAI::Events.emit(sink, RCrewAI::Events::TextDelta.new(
                                   type: :text_delta, timestamp: Time.now,
                                   agent: 'a', iteration: 0, text: 'hi'
                                 ))

      expect(seen.first.parent_id).to be_nil
    end

    it 'restores the previous parent after the block' do
      seen = []
      sink = ->(e) { seen << e }
      mk = lambda do
        RCrewAI::Events::TextDelta.new(type: :text_delta, timestamp: Time.now,
                                       agent: 'a', iteration: 0, text: 'x')
      end

      RCrewAI::Events.with_parent('outer') do
        RCrewAI::Events.with_parent('inner') { RCrewAI::Events.emit(sink, mk.call) }
        RCrewAI::Events.emit(sink, mk.call)
      end

      expect(seen.map(&:parent_id)).to eq(%w[inner outer])
    end

    it 'keeps parent scope thread-local' do
      seen = Queue.new
      sink = ->(e) { seen << e }
      mk = lambda do
        RCrewAI::Events::TextDelta.new(type: :text_delta, timestamp: Time.now,
                                       agent: 'a', iteration: 0, text: 'x')
      end

      RCrewAI::Events.with_parent('main-thread') do
        Thread.new { RCrewAI::Events.emit(sink, mk.call) }.join
      end

      expect(seen.pop.parent_id).to be_nil
    end

    it 'returns the block value' do
      expect(RCrewAI::Events.with_parent('s') { 42 }).to eq(42)
    end

    it 'restores the parent even when the block raises' do
      seen = []
      sink = ->(e) { seen << e }

      begin
        RCrewAI::Events.with_parent('outer') do
          RCrewAI::Events.with_parent('inner') { raise 'boom' }
        end
      rescue RuntimeError
        nil
      end

      RCrewAI::Events.emit(sink, RCrewAI::Events::TextDelta.new(
                                   type: :text_delta, timestamp: Time.now,
                                   agent: 'a', iteration: 0, text: 'x'
                                 ))
      expect(seen.first.parent_id).to be_nil
    end
  end

  describe 'RCrewAI::Events.fan_out serialization' do
    it 'never invokes a sink concurrently' do
      concurrent = false
      active = 0
      lock = Mutex.new

      sink = lambda do |_e|
        lock.synchronize do
          concurrent = true if active.positive?
          active += 1
        end
        sleep 0.001
        lock.synchronize { active -= 1 }
      end

      fan = RCrewAI::Events.fan_out(sink)
      threads = 8.times.map do
        Thread.new do
          5.times do
            fan.call(RCrewAI::Events::TextDelta.new(
                       type: :text_delta, timestamp: Time.now,
                       agent: 'a', iteration: 0, text: 'x'
                     ))
          end
        end
      end
      threads.each(&:join)

      expect(concurrent).to be(false),
                            'fan_out invoked a sink from two threads at once'
    end

    it 'delivers every event exactly once under concurrency' do
      lock = Mutex.new
      received = []
      fan = RCrewAI::Events.fan_out(->(e) { lock.synchronize { received << e.text } })

      threads = 4.times.map do |t|
        Thread.new do
          10.times do |i|
            fan.call(RCrewAI::Events::TextDelta.new(
                       type: :text_delta, timestamp: Time.now,
                       agent: 'a', iteration: 0, text: "#{t}-#{i}"
                     ))
          end
        end
      end
      threads.each(&:join)

      expect(received.size).to eq(40)
      expect(received.uniq.size).to eq(40)
    end

    it 'still isolates a raising sink' do
      good = []
      fan = RCrewAI::Events.fan_out([->(_e) { raise 'boom' }, ->(e) { good << e }])

      io = with_captured_io do
        fan.call(RCrewAI::Events::TextDelta.new(
                   type: :text_delta, timestamp: Time.now,
                   agent: 'a', iteration: 0, text: 'x'
                 ))
      end

      expect(good.size).to eq(1)
      expect(io[:stderr]).to include('boom')
    end

    it 'does not deadlock when a sink emits through the same fan-out' do
      seen = []
      fan = nil
      inner = lambda do |e|
        seen << e.text
        if e.text == 'outer'
          fan.call(RCrewAI::Events::TextDelta.new(
                     type: :text_delta, timestamp: Time.now,
                     agent: 'a', iteration: 0, text: 'inner'
                   ))
        end
      end
      fan = RCrewAI::Events.fan_out(inner)

      expect do
        Timeout.timeout(2) do
          fan.call(RCrewAI::Events::TextDelta.new(
                     type: :text_delta, timestamp: Time.now,
                     agent: 'a', iteration: 0, text: 'outer'
                   ))
        end
      end.not_to raise_error

      expect(seen).to eq(%w[outer inner])
    end
  end
end

RSpec.describe 'event hierarchy in the execution path' do
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

  def run_and_capture
    crew  = RCrewAI::Crew.new('traced')
    agent = RCrewAI::Agent.new(name: 'writer', role: 'Writer', goal: 'Write', backstory: 'A writer')
    task  = RCrewAI::Task.new(
      name: 'write', description: 'Write a line', expected_output: 'A line', agent: agent
    )
    crew.add_agent(agent)
    crew.add_task(task)

    received = []
    crew.execute(stream: ->(e) { received << e })
    received
  end

  it 'stamps an id on every emitted event' do
    events = run_and_capture
    expect(events).not_to be_empty
    expect(events.map(&:id)).to all(be_a(String))
    expect(events.map(&:id).uniq.size).to eq(events.size)
  end

  it 'nests iteration events under a per-task parent span' do
    events = run_and_capture
    parents = events.map(&:parent_id).compact.uniq

    expect(parents).not_to be_empty,
                           'no event carried a parent_id — with_parent is not wired into execution'
    expect(parents.size).to eq(1)
  end
end
