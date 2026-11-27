# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'require_approval_for_final_answer during a task run' do
  let(:llm) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def supports_native_tools?(**) = true

      def chat(**)
        @calls += 1
        { content: "answer #{@calls}", tool_calls: [], usage: {}, finish_reason: :stop }
      end
    end.new
  end

  let(:agent) { create_test_agent(require_approval_for_final_answer: true) }
  let(:task) { create_test_task(agent: agent) }
  let(:approved) { { approved: true, feedback: 'approve' } }
  let(:feedback) { { approved: false, feedback: 'shorter', suggested_changes: [] } }
  let(:silence) { { approved: false, feedback: nil, no_response: true } }

  before do
    configure_test_llm
    agent.instance_variable_set(:@llm_client, llm)
  end

  def reviews(*answers)
    allow(agent).to receive(:request_human_review).and_return(*answers)
  end

  def choices(*indexes)
    allow(agent).to receive(:request_human_choice).and_return(*indexes.map { |i| { choice_index: i } })
  end

  it 'returns the answer once a person approves it' do
    reviews(approved)

    expect(agent.execute_task(task)[:content]).to eq('answer 1')
    expect(agent).to have_received(:request_human_review).once
  end

  it 'fails the task when nobody can answer' do
    reviews(silence)

    expect { agent.execute_task(task) }.to raise_error(RCrewAI::FinalAnswerRejected)
    expect(task.result).not_to include('answer 1')
  end

  it 'fails the task when the follow-up question gets no answer' do
    reviews(feedback)
    choices(nil)

    expect { agent.execute_task(task) }.to raise_error(RCrewAI::FinalAnswerRejected)
  end

  it 'reviews a revised answer before returning it' do
    reviews(feedback, approved)
    choices(0)

    expect(agent.execute_task(task)[:content]).to eq('answer 2')
    expect(agent).to have_received(:request_human_review).twice
  end

  it 'gives up after three reviews' do
    reviews(feedback)
    choices(0)

    expect { agent.execute_task(task) }.to raise_error(RCrewAI::FinalAnswerRejected)
    expect(agent).to have_received(:request_human_review).exactly(3).times
  end

  it 'lets the person keep the answer or replace it' do
    reviews(feedback)
    choices(1)

    expect(agent.execute_task(task)[:content]).to eq('answer 1')
  end

  it 'returns the replacement the person typed' do
    reviews(feedback)
    choices(2)
    allow(agent).to receive(:request_human_input).and_return({ input: 'mine' })

    expect(agent.execute_task(task)[:content]).to eq('mine')
  end

  it 'does not retry a rejected task, which would run its tools again' do
    reviews(silence)

    expect { task.execute }.to raise_error(RCrewAI::FinalAnswerRejected)
    expect(llm.calls).to eq(1)
    expect(task.status).to eq(:failed)
  end

  it 'stays on after a task toggles human input' do
    agent.enable_human_input
    agent.disable_human_input
    reviews(silence)

    expect { agent.execute_task(task) }.to raise_error(RCrewAI::FinalAnswerRejected)
  end

  it 'asks nothing when the option is off' do
    plain = create_test_agent
    plain.instance_variable_set(:@llm_client, llm)
    allow(plain).to receive(:request_human_review)

    plain.execute_task(create_test_task(agent: plain))

    expect(plain).not_to have_received(:request_human_review)
  end
end
