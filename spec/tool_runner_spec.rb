# frozen_string_literal: true

require 'spec_helper'

class FakeTool < RCrewAI::Tools::Base
  tool_name 'echo'
  description 'echo args back'
  param :msg, type: :string, required: true
  def execute(msg:)
    "echoed: #{msg}"
  end
end

RSpec.describe RCrewAI::ToolRunner do
  let(:tool) { FakeTool.new }
  let(:agent) do
    double('Agent',
           name: 'a',
           memory: double('Memory', add_tool_usage: nil),
           require_approval_for_tools?: false)
  end

  context 'when LLM responds with a tool_call then a final answer' do
    let(:llm) do
      responses = [
        { content: nil, tool_calls: [{ id: 'c1', name: 'echo', arguments: { 'msg' => 'hi' } }],
          usage: {}, finish_reason: :tool_calls, model: 'm', provider: :test },
        { content: 'Done.', tool_calls: [], usage: {},
          finish_reason: :stop, model: 'm', provider: :test }
      ]
      llm = double('LLM')
      allow(llm).to receive(:chat) { responses.shift }
      llm
    end

    it 'runs to completion in 2 iterations with tool result threaded in' do
      events = []
      runner = described_class.new(agent: agent, llm: llm, tools: [tool],
                                   event_sink: ->(e) { events << e })
      result = runner.run(messages: [{ role: 'user', content: 'echo hi' }])

      expect(result[:content]).to eq('Done.')
      expect(result[:iterations]).to eq(2)
      expect(result[:tool_calls_history]).to match([
                                                     a_hash_including(tool: 'echo',
                                                                      args: { 'msg' => 'hi' },
                                                                      result: 'echoed: hi',
                                                                      duration_ms: kind_of(Integer))
                                                   ])
      types = events.map(&:class)
      expect(types).to include(RCrewAI::Events::ToolCallStart, RCrewAI::Events::ToolCallResult)
    end

    it 'records tool usage in agent memory' do
      expect(agent.memory).to receive(:add_tool_usage).with('echo', { 'msg' => 'hi' }, 'echoed: hi')
      runner = described_class.new(agent: agent, llm: llm, tools: [tool])
      runner.run(messages: [{ role: 'user', content: 'echo hi' }])
    end
  end

  context 'when a tool raises' do
    let(:bad_tool) do
      Class.new(RCrewAI::Tools::Base) do
        tool_name 'bad'
        description 'bad'
        param :x, type: :string, required: true
        def execute(x:) = raise('boom') # rubocop:disable Lint/UnusedMethodArgument,Naming/MethodParameterName
      end.new
    end

    let(:llm) do
      responses = [
        { content: nil, tool_calls: [{ id: 'c1', name: 'bad', arguments: { 'x' => 'y' } }],
          usage: {}, finish_reason: :tool_calls, model: 'm', provider: :test },
        { content: 'Recovered.', tool_calls: [], usage: {},
          finish_reason: :stop, model: 'm', provider: :test }
      ]
      double('LLM').tap { |l| allow(l).to receive(:chat) { responses.shift } }
    end

    it 'emits ToolCallError, threads error back into messages, continues' do
      events = []
      runner = described_class.new(agent: agent, llm: llm, tools: [bad_tool],
                                   event_sink: ->(e) { events << e })
      result = runner.run(messages: [{ role: 'user', content: 'go' }])

      expect(result[:content]).to eq('Recovered.')
      expect(events.any? { |e| e.is_a?(RCrewAI::Events::ToolCallError) }).to be true
    end
  end

  context 'when max_iterations is reached' do
    let(:llm) do
      always_tool = {
        content: nil, tool_calls: [{ id: 'c', name: 'echo', arguments: { 'msg' => 'x' } }],
        usage: {}, finish_reason: :tool_calls, model: 'm', provider: :test
      }
      double('LLM').tap { |l| allow(l).to receive(:chat).and_return(always_tool) }
    end

    it 'stops after max_iterations and returns best-effort' do
      runner = described_class.new(agent: agent, llm: llm, tools: [tool], max_iterations: 3)
      result = runner.run(messages: [{ role: 'user', content: 'loop' }])
      expect(result[:iterations]).to eq(3)
      expect(result[:finish_reason]).to eq(:max_iterations)
    end
  end
end
