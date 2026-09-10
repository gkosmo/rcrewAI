# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'parallel tool execution' do
  # A tool that sleeps, so concurrency is visible as wall-clock time.
  def slow_tool(name, delay: 0.15, &body)
    Class.new(RCrewAI::Tools::Base) do
      define_singleton_method(:tool_name_value) { name }
      define_method(:name) { name }
      define_method(:description) { "slow #{name}" }
      define_method(:execute) do |**args|
        sleep delay
        body ? body.call(args) : "#{name}-done"
      end
      define_method(:execute_with_validation) { |args| execute(**(args || {})) }
      define_method(:json_schema) do
        { name: name, description: "slow #{name}",
          parameters: { type: 'object', properties: {}, required: [] } }
      end
    end.new
  end

  def llm_returning(tool_calls)
    calls = 0
    llm = instance_double('LLMClient')
    allow(llm).to receive(:supports_native_tools?).and_return(true)
    allow(llm).to receive(:chat) do
      calls += 1
      if calls == 1
        { content: nil, tool_calls: tool_calls, finish_reason: :tool_calls,
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
      else
        { content: 'done', tool_calls: [], finish_reason: :stop,
          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
      end
    end
    llm
  end

  let(:agent) { create_test_agent(name: 'w') }

  let(:three_calls) do
    [{ id: 'c1', name: 'alpha', arguments: {} },
     { id: 'c2', name: 'beta',  arguments: {} },
     { id: 'c3', name: 'gamma', arguments: {} }]
  end

  let(:tools) { [slow_tool('alpha'), slow_tool('beta'), slow_tool('gamma')] }

  it 'runs several tool calls from one turn concurrently' do
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(three_calls), tools: tools)

    started = Time.now
    runner.run(messages: [{ role: 'user', content: 'go' }])
    elapsed = Time.now - started

    # Serial would be ~0.45s (3 x 0.15). Concurrent should be well under.
    expect(elapsed).to be < 0.35,
                       "tool calls ran serially (#{elapsed.round(2)}s for 3 x 0.15s)"
  end

  it 'preserves tool result order regardless of completion order' do
    fast = slow_tool('alpha', delay: 0.01)
    slow = slow_tool('beta', delay: 0.2)
    last = slow_tool('gamma', delay: 0.05)

    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(three_calls),
                                     tools: [fast, slow, last])
    result = runner.run(messages: [{ role: 'user', content: 'go' }])

    names = result[:tool_calls_history].map { |h| h[:tool] }
    expect(names).to eq(%w[alpha beta gamma]),
                     'results must follow the order the model requested, not completion order'
  end

  it 'still reports a failing tool without losing the others' do
    boom = Class.new(RCrewAI::Tools::Base) do
      def name = 'beta'
      def description = 'raises'
      def execute(**) = raise('boom')
      def execute_with_validation(_args) = execute

      def json_schema = { name: 'beta', description: 'raises',
                          parameters: { type: 'object', properties: {}, required: [] } }
    end.new

    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(three_calls),
                                     tools: [slow_tool('alpha'), boom, slow_tool('gamma')])
    result = runner.run(messages: [{ role: 'user', content: 'go' }])

    expect(result[:tool_calls_history].map { |h| h[:tool] }).to include('alpha', 'gamma')
  end

  it 'emits an event for every tool call' do
    events = []
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(three_calls),
                                     tools: tools, event_sink: ->(e) { events << e })

    runner.run(messages: [{ role: 'user', content: 'go' }])

    starts = events.select { |e| e.is_a?(RCrewAI::Events::ToolCallStart) }
    results = events.select { |e| e.is_a?(RCrewAI::Events::ToolCallResult) }
    expect(starts.map(&:tool)).to match_array(%w[alpha beta gamma])
    expect(results.map(&:tool)).to match_array(%w[alpha beta gamma])
  end

  it 'stamps the run span on events emitted from worker threads' do
    events = []
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(three_calls),
                                     tools: tools, event_sink: ->(e) { events << e })

    runner.run(messages: [{ role: 'user', content: 'go' }])

    tool_events = events.select { |e| e.is_a?(RCrewAI::Events::ToolCallResult) }
    expect(tool_events).not_to be_empty
    expect(tool_events.map(&:parent_id).compact.uniq.size).to eq(1),
                                                              'tool events lost their parent span when run off-thread'
  end

  # A NameError inside execute_tool_call was once swallowed by the rescue and
  # returned to the model as an ERROR string, so a broken code path looked like
  # a broken tool. A successful call must record history, not just a message.
  it 'records history for a single successful tool call' do
    one = [{ id: 'c1', name: 'alpha', arguments: {} }]
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(one),
                                     tools: [slow_tool('alpha', delay: 0.01)])

    result = runner.run(messages: [{ role: 'user', content: 'go' }])

    expect(result[:tool_calls_history].size).to eq(1)
    expect(result[:tool_calls_history].first[:result]).to eq('alpha-done')
  end

  it 'does not disguise an internal error as a tool failure' do
    one = [{ id: 'c1', name: 'alpha', arguments: {} }]
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(one),
                                     tools: [slow_tool('alpha', delay: 0.01)])

    result = runner.run(messages: [{ role: 'user', content: 'go' }])

    expect(result[:tool_calls_history]).not_to be_empty,
                                               'a successful tool call produced no history -- an internal error was swallowed'
  end

  it 'runs a single tool call without a thread' do
    one = [{ id: 'c1', name: 'alpha', arguments: {} }]
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(one),
                                     tools: [slow_tool('alpha')])

    result = runner.run(messages: [{ role: 'user', content: 'go' }])

    expect(result[:tool_calls_history].map { |h| h[:tool] }).to eq(['alpha'])
  end

  it 'can be disabled' do
    runner = RCrewAI::ToolRunner.new(agent: agent, llm: llm_returning(three_calls),
                                     tools: tools, parallel_tools: false)

    started = Time.now
    runner.run(messages: [{ role: 'user', content: 'go' }])
    elapsed = Time.now - started

    expect(elapsed).to be >= 0.4, 'parallel_tools: false should run serially'
  end
end

RSpec.describe 'Agent parallel_tools option' do
  it 'defaults to enabled' do
    expect(create_test_agent(name: 'a').instance_variable_get(:@parallel_tools)).to be(true)
  end

  it 'can be disabled per agent' do
    agent = create_test_agent(name: 'a', parallel_tools: false)
    expect(agent.instance_variable_get(:@parallel_tools)).to be(false)
  end
end
