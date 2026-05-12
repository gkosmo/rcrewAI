# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::MCP::Transport::Stdio do
  it 'round-trips a line through a subprocess' do
    transport = described_class.new(command: 'ruby', args: ['-e', 'puts gets'])
    transport.open
    transport.send_line('hello')
    expect(transport.recv_line.strip).to eq('hello')
  ensure
    transport&.close
  end

  it 'close is idempotent' do
    transport = described_class.new(command: 'ruby', args: ['-e', 'sleep 5'])
    transport.open
    transport.close
    expect { transport.close }.not_to raise_error
  end
end
