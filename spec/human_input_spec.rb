# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::HumanInput do
  subject(:human) { described_class.new }

  around do |example|
    stdin = $stdin
    stdout = $stdout
    $stdout = StringIO.new
    example.run
  ensure
    $stdin = stdin
    $stdout = stdout
  end

  context 'without a terminal' do
    before { $stdin = StringIO.new('yes') } # piped input is not a person at a prompt

    it 'refuses approvals rather than answering yes' do
      result = human.request_approval('Drop the table?')

      expect(result[:approved]).to be false
      expect(result[:no_response]).to be true
    end

    it 'refuses confirmations rather than answering yes' do
      result = human.confirm_action('Deploy')

      expect(result[:approved]).to be false
      expect(result[:no_response]).to be true
    end

    it 'does not invent input text' do
      result = human.request_input('Your name?')

      expect(result[:input]).to be_nil
      expect(result[:valid]).to be false
      expect(result[:no_response]).to be true
    end

    it 'does not pick a choice' do
      result = human.request_choice('Which?', %w[keep delete])

      expect(result[:choice]).to be_nil
      expect(result[:choice_index]).to be_nil
      expect(result[:no_response]).to be true
    end

    it 'does not invent a review' do
      result = human.request_review('Draft')

      expect(result[:feedback]).to be_nil
      expect(result[:approved]).to be false
      expect(result[:no_response]).to be true
    end

    it 'does not invent feedback' do
      result = human.get_feedback('Thoughts?')

      expect(result[:feedback]).to be_nil
      expect(result[:no_response]).to be true
    end

    it 'still honours an explicit auto_approve' do
      expect(described_class.new(auto_approve: true).request_approval('Go?')[:approved]).to be true
    end
  end

  context 'at a terminal' do
    def answer(text)
      $stdin = StringIO.new(text.nil? ? '' : "#{text}\n")
      $stdin.define_singleton_method(:tty?) { true }
    end

    %w[yes y YES Yes. ok approve].each do |text|
      it "treats #{text.inspect} as approval" do
        answer(text)
        expect(human.request_approval('Go?')[:approved]).to be true
      end
    end

    ['no', 'n', 'deny', 'nay', 'refuse', 'not ok', 'do not approve', 'maybe', 'hello', 'no, try again', ''].each do |text|
      it "does not treat #{text.inspect} as approval" do
        answer(text)
        expect(human.request_approval('Go?')[:approved]).to be false
      end
    end

    it 'treats end of input as no response' do
      answer(nil)
      result = human.request_approval('Go?')

      expect(result[:approved]).to be false
      expect(result[:no_response]).to be true
    end

    it 'treats a timeout as a refusal' do
      reader, writer = IO.pipe
      reader.define_singleton_method(:tty?) { true }
      $stdin = reader

      expect(human.request_approval('Go?', timeout: 0.05)[:approved]).to be false
    ensure
      writer&.close
      reader&.close
    end

    it 'does not take an empty answer as the first choice' do
      answer('')
      expect(human.request_choice('Which?', %w[keep delete])[:choice]).to be_nil
    end
  end
end
