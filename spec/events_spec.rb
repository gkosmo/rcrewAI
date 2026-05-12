# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Events do
  it 'TextDelta carries text + agent + iteration' do
    e = described_class::TextDelta.new(text: 'hi', agent: 'a', iteration: 0, timestamp: Time.now)
    expect(e.text).to eq('hi')
    expect(e.agent).to eq('a')
    expect(e.iteration).to eq(0)
  end

  describe '.fan_out' do
    it 'forwards events to every sink' do
      received_a = []
      received_b = []
      sink_a = ->(e) { received_a << e }
      sink_b = ->(e) { received_b << e }
      fan = described_class.fan_out([sink_a, sink_b])

      e = described_class::TextDelta.new(text: 'x', agent: 'a', iteration: 0, timestamp: Time.now)
      fan.call(e)
      expect(received_a).to eq([e])
      expect(received_b).to eq([e])
    end

    it 'isolates one sink raising from the others' do
      received = []
      bad  = ->(_) { raise 'boom' }
      good = ->(e) { received << e }
      fan = described_class.fan_out([bad, good])
      e = described_class::TextDelta.new(text: 'x', agent: 'a', iteration: 0, timestamp: Time.now)
      expect { fan.call(e) }.not_to raise_error
      expect(received).to eq([e])
    end
  end
end
