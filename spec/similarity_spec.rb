# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RCrewAI::Similarity do
  describe '.cosine' do
    it 'is 1.0 for identical direction vectors' do
      expect(described_class.cosine([1.0, 0.0], [2.0, 0.0])).to be_within(1e-9).of(1.0)
    end

    it 'is 0.0 for orthogonal vectors' do
      expect(described_class.cosine([1.0, 0.0], [0.0, 1.0])).to be_within(1e-9).of(0.0)
    end

    it 'is 0.0 when either vector is all zeros' do
      expect(described_class.cosine([0.0, 0.0], [1.0, 1.0])).to eq(0.0)
    end

    it 'tolerates vectors of differing length by treating missing components as zero' do
      expect(described_class.cosine([1.0, 0.0, 0.0], [1.0, 0.0])).to be_within(1e-9).of(1.0)
    end
  end

  describe '.lexical' do
    it 'is high for texts sharing most content words' do
      score = described_class.lexical('research the ruby language', 'research ruby language deeply')
      expect(score).to be > 0.4
    end

    it 'is low for unrelated texts' do
      score = described_class.lexical('bake a chocolate cake', 'deploy the kubernetes cluster')
      expect(score).to be < 0.2
    end

    it 'is 0.0 when there are no comparable words' do
      expect(described_class.lexical('', '')).to eq(0.0)
    end
  end
end
