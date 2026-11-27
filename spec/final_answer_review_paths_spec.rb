# frozen_string_literal: true

require 'spec_helper'

# A rejected final answer through the paths around a single task run.
RSpec.describe 'final answer rejection outside a plain task run' do
  let(:llm) do
    double('LLM', supports_native_tools?: true,
                  chat: { content: 'draft', tool_calls: [], usage: {}, finish_reason: :stop })
  end

  before do
    configure_test_llm
    allow(RCrewAI::LLMClient).to receive(:for_provider).and_return(llm)
  end

  def reviewed_agent(name = 'a')
    create_test_agent(name: name, require_approval_for_final_answer: true)
  end

  let(:silence) { { approved: false, no_response: true } }

  it 'fails a consensual task instead of letting another proposal stand in' do
    crew = RCrewAI::Crew.new('c', process: :consensual, consensus_agents: 2)
    careful = reviewed_agent('careful')
    allow(careful).to receive(:request_human_review).and_return(silence)
    crew.add_agent(careful)
    crew.add_agent(create_test_agent(name: 'other'))
    crew.add_task(create_test_task(name: 't', agent: careful))

    outcome = crew.execute[:results].first

    expect(outcome[:status]).to eq(:failed)
    expect(outcome[:result]).to include('was not approved')
  end

  it 'asks about one answer at a time' do
    open_reviews = 0
    most_open = 0
    lock = Mutex.new
    agents = %w[a b c].map do |name|
      reviewed_agent(name).tap do |agent|
        allow(agent).to receive(:request_human_review) do
          lock.synchronize { most_open = [most_open, open_reviews += 1].max }
          sleep 0.05
          lock.synchronize { open_reviews -= 1 }
          { approved: true }
        end
      end
    end

    agents.map { |a| Thread.new { a.execute_task(create_test_task(agent: a)) } }.each(&:join)

    expect(most_open).to eq(1)
  end

  { 'raises' => -> { raise 'overloaded' }, 'returns no text' => -> { { content: nil } } }.each do |what, revision|
    it "rejects, without rerunning the task, when the revision call #{what}" do
      replies = [-> { { content: 'draft', tool_calls: [], usage: {} } }, revision]
      allow(llm).to receive(:chat) { (replies.shift || revision).call }
      agent = reviewed_agent
      allow(agent).to receive(:request_human_review).and_return({ approved: false, feedback: 'redo' })
      allow(agent).to receive(:request_human_choice).and_return({ choice_index: 0 })
      task = create_test_task(agent: agent, max_retries: 2)
      allow(task).to receive(:sleep)

      expect { task.execute }.to raise_error(RCrewAI::FinalAnswerRejected)
      expect(agent).to have_received(:request_human_review).once
    end
  end
end
