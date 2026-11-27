# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/harness_helpers'

# Threads the library starts for work it does inside a hook carry the hook's
# mark, so a tool call on them is refused at once like one made on the hook's
# own thread. Without it, the call would wait for the lock the hook's caller
# holds until the hook timed out, and could then run after all.
RSpec.describe 'harness hooks: tool calls from threads the library starts inside a hook' do
  let(:spy) { HarnessSpyTool.new }
  let(:task) { RCrewAI::Task.new(name: 't', description: 'do it', expected_output: 'x') }

  around do |example|
    original = $stdin
    $stdin = StringIO.new # not a terminal: nobody can answer
    example.run
    $stdin = original
  end

  def native_turn(*calls)
    { content: nil,
      tool_calls: calls.each_with_index.map { |args, i| { id: "call_#{i}", name: 'spy_writer', arguments: args } },
      finish_reason: :tool_calls, usage: {} }
  end

  # Runs one native agent turn with the given calls through +harness+.
  def run_calls(harness, *calls)
    llm = HarnessLLM.new(native: true, turns: [native_turn(*calls)])
    RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g', tools: [spy], llm: llm, harness: harness).execute_task(task)
  end

  def allowing(**options, &hooks)
    RCrewAI::Harness.new(default: :allow, **options, &hooks)
  end

  # Runs one call whose before hook gives +work+ a lambda that makes a tool
  # call through the same harness. Returns what that call returned or raised,
  # the seconds the outer call took, and the tool the inner call would run.
  def call_from_hook(&work)
    other = HarnessSpyTool.new
    inner = nil
    harness = allowing(hook_timeout: 10)
    same_harness = Struct.new(:name, :harness).new('a', harness)
    tool_call = lambda do
      RCrewAI::ToolExecution.new(agent: same_harness).call(other, { 'path' => 'x' })
    rescue RCrewAI::ToolApproval::Refused => e
      e
    end
    harness.before(:spy_writer) do |call|
      next true unless call.args['path'] == 'a.txt'

      inner = work.call(tool_call)
      true
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run_calls(harness, { 'path' => 'a.txt' })
    [inner, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, other]
  end

  def expect_refused_at_once(inner, elapsed, other)
    expect(elapsed).to be < 5
    expect(inner).to be_a(RCrewAI::Harness::Blocked)
    expect(inner.message).to include("can't make tool calls")
    expect(other.calls).to be_empty
    expect(spy.calls).to eq([{ path: 'a.txt' }])
  end

  it 'refuses the parallel tool calls of an agent that shares the harness' do
    inner_spy = HarnessSpyTool.new
    inner_llm = HarnessLLM.new(native: true, turns: [native_turn({ 'path' => 'in1' }, { 'path' => 'in2' })])
    harness = allowing(hook_timeout: 10)
    inner_agent = RCrewAI::Agent.new(name: 'inner', role: 'r', goal: 'g', tools: [inner_spy], llm: inner_llm,
                                     harness: harness)
    harness.before(:spy_writer) do |call|
      inner_agent.execute_task(task) if call.args['path'] == 'a.txt'
      true
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run_calls(harness, { 'path' => 'a.txt' })
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(elapsed).to be < 5
    expect(spy.calls).to eq([{ path: 'a.txt' }])
    expect(inner_spy.calls).to be_empty
    sent = inner_llm.requests.last.map { |m| m[:content].to_s }
    expect(sent.grep(/can't make tool calls/).length).to eq(2)
  end

  it 'refuses a call made by a consensual process' do
    process = RCrewAI::Process::Consensual.new(Struct.new(:verbose).new(false))
    expect_refused_at_once(*call_from_hook do |tool_call|
      process.send(:bounded_parallel, [[1], [2]]) { tool_call.call }.first
    end)
  end

  it 'refuses a call made by an async executor' do
    executor = RCrewAI::AsyncExecutor.new
    executor.instance_variable_get(:@logger).level = Logger::FATAL
    expect_refused_at_once(*call_from_hook do |tool_call|
      work = Struct.new(:name).new('t')
      work.define_singleton_method(:execute) { tool_call.call }
      executor.execute_single_task_async(work).value(5)
    end)
  ensure
    executor&.shutdown
  end

  it "refuses a call made by an agent's approval handler" do
    expect_refused_at_once(*call_from_hook do |tool_call|
      inner = nil
      asking = RCrewAI::Agent.new(name: 'b', role: 'r', goal: 'g', tools: [],
                                  llm: HarnessLLM.new(native: true, turns: []),
                                  harness: RCrewAI::Harness.new(default: :ask),
                                  approval_handler: ->(_request) { (inner = tool_call.call) && true })
      RCrewAI::ToolExecution.new(agent: asking).call(HarnessSpyTool.new, { 'path' => 'y' })
      inner
    end)
  end
end
