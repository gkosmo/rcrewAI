# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::CLI do
  it 'loads from the main library' do
    expect(defined?(RCrewAI::CLI)).to eq('constant')
  end

  it 'registers every subcommand' do
    expect(described_class.subcommand_classes.keys)
      .to include('agent', 'task', 'checkpoint')
  end

  describe 'run' do
    it 'is invocable as `run` despite Thor reserving the name' do
      expect(described_class.all_commands.keys).to include('run_crew')
      expect(described_class.map['run']).to eq(:run_crew)
    end

    it 'loads and executes the named crew' do
      crew = instance_double(RCrewAI::Crew)
      allow(RCrewAI::Crew).to receive(:load).with('demo').and_return(crew)
      allow(crew).to receive(:execute)

      with_captured_io { described_class.start(['run', '--crew', 'demo']) }

      expect(crew).to have_received(:execute)
    end
  end

  describe 'version' do
    it 'prints the gem version' do
      out = with_captured_io { described_class.start(['version']) }
      expect(out[:stdout]).to include(RCrewAI::VERSION)
    end
  end

  describe 'list' do
    it 'prints the available crews' do
      allow(RCrewAI::Crew).to receive(:list).and_return(%w[alpha beta])

      out = with_captured_io { described_class.start(['list']) }

      expect(out[:stdout]).to include('alpha').and include('beta')
    end
  end
end
