# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::SSEParser do
  it 'parses a simple data event' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("data: hello\n\n")
    expect(events).to eq([{ event: 'message', data: 'hello' }])
  end

  it 'splits multi-line data with newlines preserved' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("data: one\ndata: two\n\n")
    expect(events.first[:data]).to eq("one\ntwo")
  end

  it 'respects event: field' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed("event: ping\ndata: {}\n\n")
    expect(events.first[:event]).to eq('ping')
  end

  it 'handles chunked feeds across event boundary' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed('data: par')
    p.feed("tial\n")
    p.feed("\n")
    expect(events.first[:data]).to eq('partial')
  end

  it 'ignores comment lines' do
    events = []
    p = described_class.new { |evt| events << evt }
    p.feed(": heartbeat\n\ndata: x\n\n")
    expect(events.length).to eq(1)
    expect(events.first[:data]).to eq('x')
  end
end
