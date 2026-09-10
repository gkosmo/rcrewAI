# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RCrewAI::Checkpoint::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:store) { RCrewAI::Checkpoint::FileStore.new(@dir) }

  def seed(run_id, tasks:, parent: nil, crew: 'demo')
    store.save(run_id, RCrewAI::Checkpoint.record_for(
                         run_id: run_id, crew_name: crew,
                         tasks: tasks, parent_run_id: parent
                       ))
  end

  def entry(status) = { 'status' => status, 'result' => 'r', 'execution_time' => 1.0 }

  describe 'list' do
    it 'reports when there are no checkpoints' do
      out = with_captured_io { described_class.start(['list', '--dir', @dir]) }
      expect(out[:stdout]).to match(/no checkpoints/i)
    end

    it 'lists each run id' do
      seed('run-a', tasks: { 't1' => entry('completed') })
      seed('run-b', tasks: { 't1' => entry('completed') })

      out = with_captured_io { described_class.start(['list', '--dir', @dir]) }

      expect(out[:stdout]).to include('run-a').and include('run-b')
    end

    it 'shows the crew name and task tally' do
      seed('run-a', crew: 'research',
                    tasks: { 't1' => entry('completed'), 't2' => entry('failed') })

      out = with_captured_io { described_class.start(['list', '--dir', @dir]) }

      expect(out[:stdout]).to include('research')
      expect(out[:stdout]).to match(%r{1\s*/\s*2})
    end
  end

  describe 'info' do
    it 'reports an unknown run id' do
      out = with_captured_io { described_class.start(['info', 'nope', '--dir', @dir]) }
      expect(out[:stdout]).to match(/no checkpoint/i)
    end

    it 'shows per-task status' do
      seed('run-a', tasks: { 't1' => entry('completed'), 't2' => entry('failed') })

      out = with_captured_io { described_class.start(['info', 'run-a', '--dir', @dir]) }

      expect(out[:stdout]).to include('t1').and include('completed')
      expect(out[:stdout]).to include('t2').and include('failed')
    end

    it 'shows the lineage chain for a resumed run' do
      seed('root', tasks: { 't1' => entry('completed') })
      seed('child', tasks: { 't1' => entry('completed') }, parent: 'root')

      out = with_captured_io { described_class.start(['info', 'child', '--dir', @dir]) }

      expect(out[:stdout]).to include('root')
    end

    it 'omits the lineage section for a root run' do
      seed('root', tasks: { 't1' => entry('completed') })

      out = with_captured_io { described_class.start(['info', 'root', '--dir', @dir]) }

      expect(out[:stdout]).not_to match(/lineage/i)
    end
  end

  describe 'delete' do
    it 'removes a checkpoint' do
      seed('run-a', tasks: { 't1' => entry('completed') })

      with_captured_io { described_class.start(['delete', 'run-a', '--dir', @dir]) }

      expect(store.load('run-a')).to be_nil
    end

    it 'reports an unknown run id' do
      out = with_captured_io { described_class.start(['delete', 'nope', '--dir', @dir]) }
      expect(out[:stdout]).to match(/no checkpoint/i)
    end
  end

  it 'is registered as a subcommand of the main CLI' do
    expect(RCrewAI::CLI.subcommand_classes['checkpoint']).to eq(described_class)
  end
end
