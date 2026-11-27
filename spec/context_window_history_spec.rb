# frozen_string_literal: true

require 'spec_helper'

# A tool-using run: the task, then assistant tool calls and their results.
RSpec.describe RCrewAI::ContextWindow, '.fit on a run history' do
  def turn(id, size: 400)
    [
      { role: 'assistant', content: nil, tool_calls: [{ id: id, name: 'read', arguments: {} }] },
      { role: 'tool', tool_call_id: id, content: 'r' * size }
    ]
  end

  let(:task) { { role: 'user', content: 'Task: ship it' } }
  let(:history) { [{ role: 'system', content: 's' }, task, *turn('1'), *turn('2'), *turn('3')] }

  def call_ids(messages)
    messages.flat_map { |m| Array(m[:tool_calls]).map { |c| c[:id] } }
  end

  def result_ids(messages)
    messages.filter_map { |m| m[:tool_call_id] }
  end

  it 'keeps the task when it has to drop older turns' do
    expect(described_class.fit(history, limit: 220)).to include(task)
  end

  it 'drops a tool call and its results together at every budget' do
    (1..320).each do |limit|
      fitted = described_class.fit(history, limit: limit)

      expect(result_ids(fitted)).to eq(call_ids(fitted)), "unpaired at limit #{limit}"
    end
  end

  it 'keeps the call that the final tool result answers' do
    fitted = described_class.fit(history, limit: 1)

    expect(fitted.last(2)).to eq(history.last(2))
  end

  it 'keeps all results of a turn with several calls' do
    parallel = [
      { role: 'assistant', content: nil, tool_calls: [{ id: 'a' }, { id: 'b' }] },
      { role: 'tool', tool_call_id: 'a', content: 'x' * 400 },
      { role: 'tool', tool_call_id: 'b', content: 'y' * 40 }
    ]
    fitted = described_class.fit([task, *turn('1'), *parallel], limit: 60)

    expect(result_ids(fitted)).to eq(%w[a b])
    expect(call_ids(fitted)).to eq(%w[a b])
  end

  it 'counts tool call arguments toward the estimate' do
    message = { role: 'assistant', content: nil, tool_calls: [{ id: '1', arguments: { 'body' => 'x' * 400 } }] }

    expect(described_class.estimate_tokens([message])).to be >= 100
  end

  it 'drops a legacy runner tool request together with its result' do
    legacy = (1..3).flat_map do |i|
      [{ role: 'assistant', content: "USE_TOOL[read](n=#{i})" },
       { role: 'user', content: "Tool read result: #{i}#{'r' * 400}" }]
    end

    (1..400).each do |limit|
      fitted = described_class.fit([task, *legacy], limit: limit)

      expect(fitted.map { |m| m[:role] }.drop(1)).to eq(%w[assistant user] * (fitted.length / 2)),
                                                     "unpaired at limit #{limit}"
    end
  end
end
