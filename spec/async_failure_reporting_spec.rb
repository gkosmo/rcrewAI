# frozen_string_literal: true

require 'spec_helper'
require 'rcrewai/async_executor'

RSpec.describe RCrewAI::AsyncExecutor, '#wait_for_completion' do
  let(:executor) { described_class.new }
  let(:task) { double('Task', name: 't') }

  after { executor.shutdown }

  def outcome(timeout: 1, &work)
    executor.wait_for_completion({ task => Concurrent::Future.execute(&work) }, timeout).first
  end

  it 'reports a task that raised as failed' do
    expect(outcome { raise 'rejected' }).to include(status: :failed, result: 'rejected')
  end

  it 'reports a task still running at the deadline as timed out' do
    expect(outcome(timeout: 0.01) { sleep 0.3 }).to include(status: :timeout)
  end

  it 'reports a finished task as completed' do
    expect(outcome { 'ok' }).to include(status: :completed, result: 'ok')
  end
end
