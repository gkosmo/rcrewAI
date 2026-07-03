#!/usr/bin/env ruby
# frozen_string_literal: true

# Flows — event-driven workflows (RCrewAI's second pillar).
#
# Subclass RCrewAI::Flow and wire methods together with the class-level DSL:
# `start` kicks things off, `listen` reacts to another method's output, and
# `router` branches by emitting a label that listeners can trigger on. State
# is a schemaless object with an automatic UUID, and can be persisted so a run
# can be resumed later.
#
# This example needs no API key — it demonstrates the engine itself.
#
# Run:
#   ruby examples/flow_example.rb

require_relative '../lib/rcrewai'

# A tiny content pipeline: outline -> draft -> review (router) -> publish/expand.
class ArticleFlow < RCrewAI::Flow
  start :outline
  def outline
    state.sections = %w[intro body conclusion]
    state.sections.length # this return value is passed to listeners of :outline
  end

  listen :outline
  def draft(section_count)
    state.words = section_count * 100
    state.words
  end

  # A router's return value (:publish / :expand) becomes a label that the
  # matching `listen` methods fire on.
  router :draft
  def review(words)
    words >= 250 ? :publish : :expand
  end

  listen :publish
  def publish
    state.status = 'published'
  end

  listen :expand
  def expand
    state.status = 'needs more work'
  end
end

puts '== Basic run =='
flow = ArticleFlow.new
flow.kickoff(inputs: { author: 'Ada' })
puts "id:       #{flow.state.id}"
puts "author:   #{flow.state.author}      (seeded via kickoff inputs)"
puts "sections: #{flow.state.sections.inspect}"
puts "words:    #{flow.state.words}"
puts "status:   #{flow.state.status.inspect}   (routed to :publish since words >= 250)"

puts "\n== and_/or_ combinators =="
class GateFlow < RCrewAI::Flow
  start :fetch_a
  def fetch_a = 'A'

  start :fetch_b
  def fetch_b = 'B'

  # Fires only after BOTH starts complete.
  listen and_(:fetch_a, :fetch_b)
  def merge
    state.merged = 'both done'
  end
end

gate = GateFlow.new
gate.kickoff
puts "merged: #{gate.state.merged.inspect}   (and_ waited for both starts)"

puts "\n== Persistence round-trip =="
require 'tmpdir'
store = RCrewAI::Flow::FileStateStore.new(File.join(Dir.tmpdir, 'rcrewai-flow-demo'))

original = ArticleFlow.new(state_store: store)
original.kickoff
id = original.state.id

resumed = ArticleFlow.new(state_store: store)
resumed.restore(id)
puts "restored status for #{id[0, 8]}...: #{resumed.state.status.inspect}"
