# frozen_string_literal: true

module RCrewAI
  # Similarity measures shared across Knowledge and Memory. `cosine` compares
  # embedding vectors; `lexical` is the word-overlap fallback used when no
  # embedder is available.
  module Similarity
    STOPWORDS = %w[the a an and or but in on at to for of with by is are was were be].freeze

    module_function

    def cosine(vec_a, vec_b)
      dot = 0.0
      norm_a = 0.0
      norm_b = 0.0
      length = [vec_a.length, vec_b.length].max
      length.times do |i|
        ai = (vec_a[i] || 0).to_f
        bi = (vec_b[i] || 0).to_f
        dot += ai * bi
        norm_a += ai * ai
        norm_b += bi * bi
      end
      return 0.0 if norm_a.zero? || norm_b.zero?

      dot / (Math.sqrt(norm_a) * Math.sqrt(norm_b))
    end

    # Jaccard-style overlap of content words. Cheap, no embeddings.
    def lexical(text_a, text_b)
      words_a = keywords(text_a)
      words_b = keywords(text_b)
      union = (words_a | words_b).length
      return 0.0 if union.zero?

      (words_a & words_b).length.to_f / union
    end

    def keywords(text)
      text.to_s.downcase.split(/\W+/).reject { |w| w.length < 3 || STOPWORDS.include?(w) }
    end
  end
end
