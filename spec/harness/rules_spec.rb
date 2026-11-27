# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Harness do
  def outcome(harness, tool, args = {})
    harness.decide(tool, args).outcome
  end

  shared_examples 'the writer and mailer rules' do
    it 'allows a call that no stricter rule applies to' do
      expect(outcome(harness, 'writer', { 'path' => 'a.txt' })).to eq(:allow)
    end

    it 'blocks a matching call with the rule reason' do
      expect(harness.decide('writer', { 'path' => '.env' }).to_h)
        .to eq(outcome: :block, reason: 'Secrets are read-only.')
    end

    it 'does not apply matching: to a missing argument' do
      expect(outcome(harness, 'writer')).to eq(:allow)
    end

    it 'asks for an ask rule and for an unlisted tool' do
      expect(outcome(harness, 'mailer')).to eq(:ask)
      expect(outcome(harness, 'other')).to eq(:ask)
    end
  end

  context 'with allow declared before block' do
    let(:harness) do
      described_class.new do
        allow :writer
        block :writer, matching: { path: /\.env\z/ }, reason: 'Secrets are read-only.'
        ask :mailer
      end
    end

    it_behaves_like 'the writer and mailer rules'
  end

  context 'with block declared before allow' do
    let(:harness) do
      described_class.new do
        ask :mailer
        block :writer, matching: { path: /\.env\z/ }, reason: 'Secrets are read-only.'
        allow :writer
      end
    end

    it_behaves_like 'the writer and mailer rules'
  end

  describe 'precedence' do
    it 'prefers ask over allow in either order' do
      first = described_class.new do
        allow :writer
        ask :writer
      end
      second = described_class.new do
        ask :writer
        allow :writer
      end

      expect([outcome(first, 'writer'), outcome(second, 'writer')]).to eq(%i[ask ask])
    end

    it 'prefers block over ask in either order' do
      first = described_class.new do
        ask :writer
        block :writer
      end
      second = described_class.new do
        block :writer
        ask :writer
      end

      expect([outcome(first, 'writer'), outcome(second, 'writer')]).to eq(%i[block block])
    end
  end

  describe 'defaults' do
    it 'applies default: :allow to an unlisted tool' do
      expect(described_class.new(default: :allow).decide('other', {}).to_h).to eq(outcome: :allow, reason: nil)
    end

    it 'applies default: :block with a reason' do
      expect(described_class.new(default: :block).decide('other', {}).to_h)
        .to eq(outcome: :block, reason: 'No rule allows this tool')
    end

    it 'gives a block rule without reason: a stock reason' do
      harness = described_class.new { block :writer }

      expect(harness.decide('writer', {}).reason).to eq('Blocked by the harness')
    end

    it 'stores hook_timeout, which defaults to 60' do
      expect(described_class.new.hook_timeout).to eq(60)
      expect(described_class.new(hook_timeout: 5).hook_timeout).to eq(5)
    end
  end

  describe 'tool names' do
    it 'accepts Strings and several names per rule' do
      harness = described_class.new(default: :allow) { block 'writer', :srv__send }

      expect([outcome(harness, 'writer'), outcome(harness, 'srv__send')]).to eq(%i[block block])
    end

    it 'matches whole names only' do
      harness = described_class.new(default: :allow) { block :writer }

      expect(outcome(harness, 'writer_two')).to eq(:allow)
    end

    it 'accepts a Symbol in decide' do
      harness = described_class.new(default: :allow) { block :writer }

      expect(outcome(harness, :writer)).to eq(:block)
    end

    it 'is not affected by the caller changing a name later' do
      name = +'writer'
      harness = described_class.new(default: :allow) { block name }
      name << '_gone'

      expect(outcome(harness, 'writer')).to eq(:block)
    end
  end

  describe 'matching:' do
    let(:blocking) { described_class.new(default: :allow) { block :writer, matching: { path: /\.env\z/ } } }
    let(:asking) { described_class.new(default: :allow) { ask :writer, matching: { path: /\.env\z/ } } }
    let(:allowing) { described_class.new(default: :block) { allow :writer, matching: { path: /\.txt\z/ } } }

    it 'blocks and asks when any element of an array matches' do
      args = { 'path' => ['a.txt', '.env'] }

      expect([outcome(blocking, 'writer', args), outcome(asking, 'writer', args)]).to eq(%i[block ask])
    end

    it 'does not block an array in which no element matches' do
      expect(outcome(blocking, 'writer', { 'path' => ['a.txt'] })).to eq(:allow)
    end

    it 'allows an array only when every element matches' do
      expect(outcome(allowing, 'writer', { 'path' => ['a.txt', '.env'] })).to eq(:block)
      expect(outcome(allowing, 'writer', { 'path' => ['a.txt', 'b.txt'] })).to eq(:allow)
    end

    [5, nil, true, {}, { 'name' => 'a.txt' }, [], [5], ['a.txt', 5], [['a.txt']], :'a.txt'].each do |value|
      it "applies block and ask, but not allow, to #{value.inspect}" do
        args = { 'path' => value }

        expect([outcome(blocking, 'writer', args), outcome(asking, 'writer', args)]).to eq(%i[block ask])
        expect(outcome(allowing, 'writer', args)).to eq(:block)
      end
    end

    it 'needs every entry to match' do
      harness = described_class.new(default: :allow) do
        block :writer, matching: { path: /\.env\z/, mode: /\Aw\z/ }
      end

      expect(outcome(harness, 'writer', { 'path' => '.env', 'mode' => 'w' })).to eq(:block)
      expect(outcome(harness, 'writer', { 'path' => '.env', 'mode' => 'a' })).to eq(:allow)
      expect(outcome(harness, 'writer', { 'path' => '.env' })).to eq(:allow)
    end

    it 'keeps both patterns given for a Symbol and a String key' do
      harness = described_class.new(default: :block) do
        allow :writer, matching: { path: /\.txt\z/, 'path' => /\Anotes/ }
      end

      expect(outcome(harness, 'writer', { 'path' => 'notes.txt' })).to eq(:allow)
      expect(outcome(harness, 'writer', { 'path' => 'other.txt' })).to eq(:block)
    end

    it 'is not affected by the caller changing the hash later' do
      patterns = { path: /\.env\z/ }
      harness = described_class.new(default: :allow) { block :writer, matching: patterns }
      patterns[:mode] = /x/

      expect(outcome(harness, 'writer', { 'path' => '.env' })).to eq(:block)
    end

    it 'blocks a string that cannot be searched' do
      invalid = (+"\xFF.env").force_encoding(Encoding::UTF_8)
      decision = blocking.decide('writer', { 'path' => invalid })

      expect(decision.outcome).to eq(:block)
      expect(decision.reason).to include('rule condition failed')
    end
  end

  describe 'arguments given to decide' do
    let(:harness) { described_class.new(default: :allow) { block :writer, matching: { path: /\.env\z/ } } }

    it 'checks Symbol keys as if they were Strings' do
      expect(outcome(harness, 'writer', { path: '.env' })).to eq(:block)
    end

    it 'blocks when two keys name the same argument' do
      expect(outcome(harness, 'writer', { 'path' => '.env', :path => 'a.txt' })).to eq(:block)
      expect(outcome(harness, 'writer', { :path => '.env', 'path' => 'a.txt' })).to eq(:block)
    end

    it 'blocks arguments that are not a Hash' do
      expect(outcome(harness, 'writer', ['.env'])).to eq(:block)
      expect(outcome(harness, 'writer', '.env')).to eq(:block)
    end

    it 'treats nil as no arguments' do
      expect(outcome(harness, 'writer', nil)).to eq(:allow)
    end
  end

  describe 'if:' do
    it 'receives the args' do
      seen = nil
      harness = described_class.new { allow :writer, if: ->(args) { seen = args } }
      harness.decide('writer', { 'path' => 'a.txt' })

      expect(seen).to eq('path' => 'a.txt')
    end

    it 'decides whether the rule applies' do
      harness = described_class.new(default: :allow) { block :writer, if: ->(args) { args['force'] } }

      expect(outcome(harness, 'writer', { 'force' => true })).to eq(:block)
      expect(outcome(harness, 'writer', { 'force' => false })).to eq(:allow)
    end

    it 'combines with matching:' do
      harness = described_class.new(default: :allow) do
        block :writer, matching: { path: /\.env\z/ }, if: ->(args) { args['mode'] == 'w' }
      end

      expect(outcome(harness, 'writer', { 'path' => '.env', 'mode' => 'w' })).to eq(:block)
      expect(outcome(harness, 'writer', { 'path' => '.env', 'mode' => 'a' })).to eq(:allow)
      expect(outcome(harness, 'writer', { 'path' => 'a.txt', 'mode' => 'w' })).to eq(:allow)
    end

    it 'is not called for another tool' do
      harness = described_class.new(default: :allow) { block :writer, if: ->(_) { raise 'boom' } }

      expect(outcome(harness, 'mailer')).to eq(:allow)
    end

    %i[allow ask block].each do |effect|
      it "blocks when the condition of an #{effect} rule raises" do
        harness = described_class.new(default: :allow) do
          public_send(effect, :writer, if: ->(_) { raise 'boom' })
        end
        decision = harness.decide('writer', {})

        expect(decision.outcome).to eq(:block)
        expect(decision.reason).to include('rule condition failed')
      end
    end

    it 'blocks when a condition raises NotImplementedError' do
      harness = described_class.new(default: :allow) { allow :writer, if: ->(_) { raise NotImplementedError } }

      expect(outcome(harness, 'writer')).to eq(:block)
    end

    it 'cannot change what other rules see' do
      harness = described_class.new(default: :allow) do
        allow :writer, if: ->(args) { args.delete('path') }
        block :writer, matching: { path: /\.env\z/ }
      end

      expect(outcome(harness, 'writer', { 'path' => '.env' })).to eq(:block)
    end

    it 'cannot change the strings or nested values it is given' do
      harness = described_class.new(default: :allow) do
        allow :writer, if: ->(args) { args['paths'].first.replace('a.txt') }
        block :writer, matching: { paths: /\.env\z/ }
      end
      args = { 'paths' => [+'.env'] }

      expect(outcome(harness, 'writer', args)).to eq(:block)
      expect(args).to eq('paths' => ['.env'])
    end
  end

  describe 'invalid definitions' do
    def define(&definition)
      -> { described_class.new(&definition) }
    end

    it 'rejects an unknown default' do
      expect { described_class.new(default: :maybe) }.to raise_error(ArgumentError, /maybe/)
    end

    it 'rejects a rule with no tool names' do
      %i[allow ask block].each do |effect|
        expect(&define { public_send(effect) }).to raise_error(ArgumentError, /tool name/)
      end
    end

    it 'rejects a name that could never match a tool' do
      [%i[writer mailer], nil, '', String, { path: /x/ }].each do |name|
        expect(&define { block name }).to raise_error(ArgumentError, /tool name/)
      end
    end

    it 'rejects a matching: value that is not a Regexp' do
      expect(&define { block :writer, matching: { path: '.env' } }).to raise_error(ArgumentError, /Regexp/)
    end

    it 'rejects a matching: that is not a Hash' do
      expect(&define { block :writer, matching: /x/ }).to raise_error(ArgumentError, /matching/)
    end

    it 'rejects a matching: key that is not a Symbol or String' do
      expect(&define { block :writer, matching: { %i[path] => /x/ } }).to raise_error(ArgumentError, /matching/)
    end

    it 'rejects an if: that cannot be called' do
      [false, true, :force].each do |condition|
        expect(&define { allow :writer, if: condition }).to raise_error(ArgumentError, /if:/)
      end
    end

    it 'rejects a misspelled keyword' do
      expect(&define { allow :writer, macthing: { path: /x/ } }).to raise_error(ArgumentError, /macthing/)
    end

    it 'rejects a Ruby block, which would otherwise be ignored' do
      expect(&define { allow(:writer) { false } }).to raise_error(ArgumentError, /block/)
    end
  end

  describe '#validate_tools' do
    def tool_class(*param_names)
      Class.new(RCrewAI::Tools::Base) do
        tool_name 'writer'
        param_names.each { |name| param name, type: :string }
      end
    end

    let(:writer) { tool_class(:path).new }

    it 'returns no warnings when every rule names a tool' do
      harness = described_class.new { block :writer, matching: { path: /x/ } }

      expect(harness.validate_tools([writer])).to eq([])
    end

    it 'warns about a rule for a tool the agent does not have' do
      harness = described_class.new do
        block :writr
        allow :writr, :writer
      end
      warnings = harness.validate_tools([writer])

      expect(warnings.size).to eq(1)
      expect(warnings.first).to include('writr')
    end

    it 'raises when matching: names an undeclared argument' do
      harness = described_class.new { block :writer, matching: { file: /x/ } }

      expect { harness.validate_tools([writer]) }.to raise_error(ArgumentError, /file/)
    end

    it 'checks every tool a rule names' do
      mailer = Class.new(RCrewAI::Tools::Base) do
        tool_name 'mailer'
        param :to, type: :string
      end.new
      harness = described_class.new { block :writer, :mailer, matching: { path: /x/ } }

      expect { harness.validate_tools([writer, mailer]) }.to raise_error(ArgumentError, /mailer/)
    end

    it 'does not check a tool that declares no params' do
      harness = described_class.new { block :writer, matching: { file: /x/ } }

      expect(harness.validate_tools([tool_class.new])).to eq([])
    end

    it 'does not check a duck-typed tool' do
      duck = Struct.new(:name).new('writer')
      harness = described_class.new { block :writer, matching: { file: /x/ } }

      expect(harness.validate_tools([duck])).to eq([])
    end

    it 'uses the instance name of an MCP tool' do
      adapter = RCrewAI::MCP::ToolAdapter.new(nil, { 'name' => 'send' }, 'srv')
      harness = described_class.new { block :srv__send, matching: { to: /x/ } }

      expect(harness.validate_tools([adapter])).to eq([])
    end
  end
end
