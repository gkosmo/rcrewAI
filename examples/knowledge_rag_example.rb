#!/usr/bin/env ruby
# frozen_string_literal: true

# Knowledge (RAG) — ground agents in your own documents.
#
# Sources (strings, files, PDFs, CSVs, URLs) are chunked, embedded, and stored
# in an in-memory cosine-similarity vector store. At execution time the most
# relevant chunks are injected into the agent's task prompt.
#
# This example uses a fake, deterministic embedder so it runs WITHOUT an API
# key. In real use you'd omit `embedder:` and let it default to OpenAI's
# text-embedding-3-small (set OPENAI_API_KEY).
#
# Run:
#   ruby examples/knowledge_rag_example.rb

require_relative '../lib/rcrewai'

# A toy embedder: maps text to a small vector by keyword presence. Any object
# responding to `embed(texts) -> [[float, ...], ...]` works here.
class KeywordEmbedder
  KEYWORDS = %w[refund shipping warranty].freeze

  def embed(texts)
    texts.map do |t|
      lower = t.downcase
      KEYWORDS.map { |kw| lower.include?(kw) ? 1.0 : 0.0 }
    end
  end
end

# 1. Build a knowledge base from a few policy snippets.
knowledge = RCrewAI::Knowledge::Base.new(
  sources: [
    RCrewAI::Knowledge::StringSource.new('Refunds are available within 30 days of purchase.'),
    RCrewAI::Knowledge::StringSource.new('Standard shipping takes 5-7 business days.'),
    RCrewAI::Knowledge::StringSource.new('The warranty covers manufacturing defects for one year.')
  ],
  embedder: KeywordEmbedder.new
)

# 2. Retrieve directly (what the agent does under the hood).
puts '== Direct retrieval =='
%w[refund shipping warranty].each do |query|
  top = knowledge.search(query, k: 1).first
  puts "#{query.ljust(9)} -> #{top}"
end

# 3. Attach the knowledge to an agent and see it injected into the prompt.
puts "\n== Injected into the agent prompt =="
RCrewAI.configure(validate: false) do |c|
  c.llm_provider = :openai
  c.api_key = 'demo-key' # not used — we only build the prompt below
end

agent = RCrewAI::Agent.new(
  name: 'support',
  role: 'Customer support specialist',
  goal: 'Answer customer questions using company policy',
  knowledge: knowledge
)
task = RCrewAI::Task.new(
  name: 'answer',
  description: 'What is the refund policy?',
  agent: agent
)

messages = agent.send(:build_initial_messages, task)
puts messages.find { |m| m[:role] == 'user' }[:content]

# Crew-level knowledge is shared with every agent, e.g.:
#   crew = RCrewAI::Crew.new('support', knowledge: knowledge)
