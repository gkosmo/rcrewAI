#!/usr/bin/env ruby
# frozen_string_literal: true

# Cognitive Memory — semantic recall + persistence.
#
# Agents remember past executions and recall them by *meaning*, not just shared
# words. With a SQLite store, memory survives restarts.
#
# This example uses a fake, deterministic embedder so it runs WITHOUT an API
# key. In real use you'd pass `RCrewAI::Knowledge::Embedder.new` (OpenAI).
#
# Run:
#   ruby examples/cognitive_memory_example.rb

require_relative '../lib/rcrewai'
require 'tmpdir'

RCrewAI.configure(validate: false) do |c|
  c.llm_provider = :openai
  c.api_key = 'demo-key'
end

# Fake embedder: maps text to a concept vector by keyword. Any object
# responding to embed(texts) -> [[float, ...], ...] works.
class ConceptEmbedder
  def embed(texts)
    texts.map do |t|
      l = t.downcase
      [
        l.match?(/payment|billing|invoice|charge/) ? 1.0 : 0.0,
        l.match?(/auth|login|session|token/) ? 1.0 : 0.0,
        l.match?(/deploy|release|ci|pipeline/) ? 1.0 : 0.0
      ]
    end
  end
end

Task = Struct.new(:name, :description)

Dir.mktmpdir do |dir|
  store = RCrewAI::Memory::SqliteStore.new(path: File.join(dir, 'memory.db'))
  agent = RCrewAI::Agent.new(
    name: 'engineer', role: 'Senior engineer', goal: 'Ship reliable software',
    memory: { embedder: ConceptEmbedder.new, store: store }
  )

  # Record a few past executions.
  agent.memory.add_execution(Task.new('t1', 'fixed the billing invoice bug'),
                             'adjusted the payment retry logic', 1.2)
  agent.memory.add_execution(Task.new('t2', 'patched the login session flow'),
                             'rotated the auth tokens', 0.8)
  agent.memory.add_execution(Task.new('t3', 'sped up the release pipeline'),
                             'parallelized the CI stages', 2.0)

  puts '== Semantic recall =='
  # Query shares NO words with the billing execution, but is conceptually close.
  query = Task.new('q', 'a customer got double-charged on checkout')
  puts agent.memory.relevant_executions(query, 1)

  puts "\n== Persistence (reopen the DB in a fresh agent) =="
  store2 = RCrewAI::Memory::SqliteStore.new(path: File.join(dir, 'memory.db'))
  agent2 = RCrewAI::Agent.new(name: 'engineer', role: 'r', goal: 'g',
                              memory: { embedder: ConceptEmbedder.new, store: store2 })
  puts agent2.memory.relevant_executions(query, 1)
  puts "stats: #{agent2.memory.stats.inspect}"
end
