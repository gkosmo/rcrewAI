# frozen_string_literal: true

module RCrewAI
  # The check behind +require_approval_for_final_answer+, mixed into Agent. It
  # uses the agent's terminal prompts, so without a terminal it rejects.
  module FinalAnswerReview
    # How many times a person is asked about one final answer.
    MAX_REVIEWS = 3

    private

    # Returns the answer a person accepted: the proposed one, a revision they
    # went on to accept, or their own. Raises FinalAnswerRejected otherwise, so
    # silence never counts as a yes.
    def request_final_answer_approval(proposed_answer)
      # Agents running side by side share one terminal, with tool approvals too.
      ToolApproval::TerminalHandler::LOCK.synchronize { review_final_answer(proposed_answer) }
    rescue FinalAnswerRejected
      raise
    rescue StandardError => e
      # Any other error would let Task retry, running the agent's tools again.
      reject_final_answer("the review failed (#{e.class}: #{e.message})")
    end

    def review_final_answer(proposed_answer)
      MAX_REVIEWS.times do |attempt|
        review = request_human_review(
          proposed_answer,
          review_criteria: %w[Accuracy Completeness Clarity Relevance],
          timeout: 180
        )
        return proposed_answer if review[:approved] == true

        reject_final_answer('nobody answered the review') if review[:no_response]

        choice = request_human_choice(
          'How should I handle your feedback?',
          [
            'Revise the answer based on feedback',
            'Use the answer as-is despite feedback',
            'Let me provide a completely new answer'
          ]
        )

        case choice[:choice_index]
        when 0
          break if attempt == MAX_REVIEWS - 1

          proposed_answer = revise_answer_with_feedback(
            "Original answer: #{proposed_answer}\n\nFeedback: #{review[:feedback]}"
          )
          reject_final_answer('the revision came back empty') if proposed_answer.to_s.strip.empty?
        when 1
          return proposed_answer
        when 2
          replacement = request_human_input('Please provide the final answer:',
                                            help_text: 'Provide the complete answer for this task')[:input]
          return replacement if replacement && !replacement.strip.empty?

          reject_final_answer('no replacement answer was given')
        else
          reject_final_answer('no choice was made about the feedback')
        end
      end

      reject_final_answer("it was not accepted after #{MAX_REVIEWS} reviews")
    end

    def reject_final_answer(why)
      raise FinalAnswerRejected, "Final answer from agent #{name} was not approved: #{why}"
    end
  end
end
