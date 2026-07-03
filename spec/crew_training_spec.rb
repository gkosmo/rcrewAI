# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe RCrewAI::Crew do
  let(:agent) { create_test_agent(name: 'agent') }
  let(:task)  { create_test_task(name: 'task', agent: agent) }

  subject do
    crew = described_class.new('training_crew')
    crew.add_agent(agent)
    crew.add_task(task)
    crew
  end

  before do
    # Isolate from the real process/agent execution.
    allow(subject).to receive(:execute).and_return(
      { crew: 'training_crew', process: :sequential, total_tasks: 1,
        completed_tasks: 1, failed_tasks: 0, results: [], success_rate: 100.0 }
    )
  end

  describe '#train' do
    let(:tmpdir) { File.join(Dir.tmpdir, "rcrewai-train-#{rand(1_000_000)}") }
    let(:filename) { File.join(tmpdir, 'training.json') }

    after { FileUtils.rm_rf(tmpdir) }

    it 'runs the crew for the requested number of iterations' do
      expect(subject).to receive(:execute).exactly(3).times.and_return({ success_rate: 100.0 })

      subject.train(n_iterations: 3, filename: filename,
                    feedback: ->(_i, _r) { 'looks good' })
    end

    it 'persists collected feedback to the given file' do
      feedback = ->(i, _r) { "feedback for run #{i}" }

      subject.train(n_iterations: 2, filename: filename, feedback: feedback)

      data = JSON.parse(File.read(filename))
      expect(data.length).to eq(2)
      expect(data.first).to include('iteration' => 1, 'feedback' => 'feedback for run 1')
    end

    it 'creates parent directories for the training file' do
      subject.train(n_iterations: 1, filename: filename, feedback: ->(_i, _r) { 'ok' })

      expect(File).to exist(filename)
    end

    it 'returns a summary of the run' do
      result = subject.train(n_iterations: 2, filename: filename, feedback: ->(_i, _r) { 'ok' })

      expect(result[:iterations]).to eq(2)
      expect(result[:filename]).to eq(filename)
    end
  end

  describe '#test' do
    it 'runs the crew for the requested number of iterations' do
      expect(subject).to receive(:execute).exactly(4).times.and_return({ success_rate: 100.0 })

      subject.test(n_iterations: 4)
    end

    it 'returns aggregate scores across runs' do
      allow(subject).to receive(:execute).and_return(
        { success_rate: 100.0 }, { success_rate: 50.0 }
      )

      result = subject.test(n_iterations: 2)

      expect(result[:iterations]).to eq(2)
      expect(result[:scores]).to eq([100.0, 50.0])
      expect(result[:average_score]).to eq(75.0)
    end

    it 'uses a custom scorer when provided' do
      result = subject.test(n_iterations: 2, scorer: ->(_r) { 42.0 })

      expect(result[:scores]).to eq([42.0, 42.0])
      expect(result[:average_score]).to eq(42.0)
    end
  end
end
