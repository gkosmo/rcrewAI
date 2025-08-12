# frozen_string_literal: true

require 'io/console'
require 'json'
require 'logger'

module RCrewAI
  class HumanInput
    attr_reader :session_id, :interactions, :timeout, :logger

    def initialize(**options)
      @session_id = options[:session_id] || generate_session_id
      @timeout = options.fetch(:timeout, 300) # 5 minutes default
      @logger = Logger.new($stdout)
      @logger.level = options.fetch(:verbose, false) ? Logger::DEBUG : Logger::INFO
      @interactions = []
      @input_history = []
      @auto_approve = options.fetch(:auto_approve, false) # For testing/automation
      @approval_keywords = options.fetch(:approval_keywords, %w[yes y approve ok continue])
      @rejection_keywords = options.fetch(:rejection_keywords, %w[no n reject cancel abort])
    end

    def request_approval(message, **options)
      interaction = create_interaction(:approval, message, options)
      
      return handle_auto_approval(interaction) if @auto_approve
      
      display_approval_request(interaction)
      response = get_user_input(interaction)
      
      result = process_approval_response(response, interaction)
      record_interaction(interaction, response, result)
      
      result
    end

    def request_input(prompt, **options)
      interaction = create_interaction(:input, prompt, options)
      
      display_input_request(interaction)
      response = get_user_input(interaction)
      
      result = process_input_response(response, interaction)
      record_interaction(interaction, response, result)
      
      result
    end

    def request_choice(prompt, choices, **options)
      interaction = create_interaction(:choice, prompt, options.merge(choices: choices))
      
      display_choice_request(interaction)
      response = get_user_input(interaction)
      
      result = process_choice_response(response, interaction)
      record_interaction(interaction, response, result)
      
      result
    end

    def request_review(content, **options)
      interaction = create_interaction(:review, content, options)
      
      display_review_request(interaction)
      response = get_user_input(interaction)
      
      result = process_review_response(response, interaction)
      record_interaction(interaction, response, result)
      
      result
    end

    def confirm_action(action_description, **options)
      interaction = create_interaction(:confirmation, action_description, options)
      
      return handle_auto_approval(interaction) if @auto_approve
      
      display_confirmation_request(interaction)
      response = get_user_input(interaction)
      
      result = process_confirmation_response(response, interaction)
      record_interaction(interaction, response, result)
      
      result
    end

    def get_feedback(prompt, **options)
      interaction = create_interaction(:feedback, prompt, options)
      
      display_feedback_request(interaction)
      response = get_user_input(interaction)
      
      result = { feedback: response, timestamp: Time.now }
      record_interaction(interaction, response, result)
      
      result
    end

    def session_summary
      {
        session_id: @session_id,
        total_interactions: @interactions.length,
        interaction_types: @interactions.group_by { |i| i[:type] }.transform_values(&:count),
        approvals: @interactions.count { |i| i[:result]&.dig(:approved) },
        rejections: @interactions.count { |i| i[:result]&.dig(:approved) == false },
        duration: calculate_session_duration,
        first_interaction: @interactions.first&.dig(:timestamp),
        last_interaction: @interactions.last&.dig(:timestamp)
      }
    end

    private

    def generate_session_id
      "human_#{Time.now.to_i}_#{rand(1000)}"
    end

    def create_interaction(type, content, options)
      {
        id: generate_interaction_id,
        type: type,
        content: content,
        options: options,
        timestamp: Time.now,
        timeout: options[:timeout] || @timeout
      }
    end

    def generate_interaction_id
      "interaction_#{@interactions.length + 1}_#{rand(100)}"
    end

    def display_approval_request(interaction)
      puts "\n" + "="*60
      puts "🤝 HUMAN APPROVAL REQUIRED"
      puts "="*60
      puts "Request: #{interaction[:content]}"
      
      if interaction[:options][:context]
        puts "\nContext: #{interaction[:options][:context]}"
      end
      
      if interaction[:options][:consequences]
        puts "\nConsequences: #{interaction[:options][:consequences]}"
      end
      
      puts "\nDo you approve this action? (yes/no)"
      print "> "
    end

    def display_input_request(interaction)
      puts "\n" + "="*60
      puts "💬 HUMAN INPUT REQUESTED"
      puts "="*60
      puts "Prompt: #{interaction[:content]}"
      
      if interaction[:options][:help_text]
        puts "\nHelp: #{interaction[:options][:help_text]}"
      end
      
      if interaction[:options][:examples]
        puts "\nExamples: #{interaction[:options][:examples].join(', ')}"
      end
      
      puts "\nPlease provide your input:"
      print "> "
    end

    def display_choice_request(interaction)
      puts "\n" + "="*60
      puts "🎯 HUMAN CHOICE REQUIRED"
      puts "="*60
      puts "Question: #{interaction[:content]}"
      puts "\nAvailable choices:"
      
      interaction[:options][:choices].each_with_index do |choice, index|
        puts "  #{index + 1}. #{choice}"
      end
      
      puts "\nPlease select a choice (enter number or text):"
      print "> "
    end

    def display_review_request(interaction)
      puts "\n" + "="*60
      puts "👀 HUMAN REVIEW REQUESTED"
      puts "="*60
      puts "Content to review:"
      puts "-" * 40
      puts interaction[:content]
      puts "-" * 40
      
      if interaction[:options][:review_criteria]
        puts "\nReview criteria: #{interaction[:options][:review_criteria].join(', ')}"
      end
      
      puts "\nPlease review and provide feedback (or type 'approve' to approve as-is):"
      print "> "
    end

    def display_confirmation_request(interaction)
      puts "\n" + "="*60
      puts "⚠️  CONFIRMATION REQUIRED"
      puts "="*60
      puts "Action: #{interaction[:content]}"
      
      if interaction[:options][:risk_level]
        puts "Risk Level: #{interaction[:options][:risk_level]}"
      end
      
      if interaction[:options][:details]
        puts "Details: #{interaction[:options][:details]}"
      end
      
      puts "\nConfirm this action? (yes/no)"
      print "> "
    end

    def display_feedback_request(interaction)
      puts "\n" + "="*60
      puts "📝 FEEDBACK REQUESTED"
      puts "="*60
      puts "Request: #{interaction[:content]}"
      
      puts "\nPlease provide your feedback:"
      print "> "
    end

    def get_user_input(interaction)
      start_time = Time.now
      
      begin
        if STDIN.tty?
          # Interactive terminal input with timeout
          response = nil
          input_thread = Thread.new do
            response = STDIN.gets&.chomp
          end
          
          unless input_thread.join(interaction[:timeout])
            input_thread.kill
            puts "\n⏰ Input timed out after #{interaction[:timeout]} seconds"
            return nil
          end
          
          response
        else
          # Non-interactive mode (e.g., scripts, tests)
          puts "⚠️ Non-interactive mode detected, using default response"
          get_default_response(interaction[:type])
        end
      rescue Interrupt
        puts "\n🛑 User interrupted input"
        nil
      ensure
        @logger.debug "Input collection took #{(Time.now - start_time).round(2)}s"
      end
    end

    def get_default_response(interaction_type)
      case interaction_type
      when :approval, :confirmation
        'yes'
      when :choice
        '1'
      when :input, :review, :feedback
        'Default response - non-interactive mode'
      else
        'yes'
      end
    end

    def process_approval_response(response, interaction)
      return { approved: false, reason: 'No response provided' } if response.nil?
      
      response_clean = response.strip.downcase
      
      approved = if @approval_keywords.any? { |keyword| response_clean.include?(keyword) }
                   true
                 elsif @rejection_keywords.any? { |keyword| response_clean.include?(keyword) }
                   false
                 else
                   # Try to interpret ambiguous responses
                   response_clean.length > 0 && !response_clean.start_with?('n')
                 end
      
      {
        approved: approved,
        response: response,
        reason: approved ? 'User approved' : 'User rejected',
        timestamp: Time.now
      }
    end

    def process_input_response(response, interaction)
      return { input: nil, valid: false, reason: 'No response provided' } if response.nil?
      
      # Validate input if validation rules provided
      validation_result = validate_input(response, interaction[:options][:validation] || {})
      
      {
        input: response,
        valid: validation_result[:valid],
        reason: validation_result[:reason],
        processed_input: process_input_value(response, interaction[:options]),
        timestamp: Time.now
      }
    end

    def process_choice_response(response, interaction)
      return { choice: nil, valid: false, reason: 'No response provided' } if response.nil?
      
      choices = interaction[:options][:choices]
      response_clean = response.strip
      
      # Try to match by number
      if response_clean.match?(/^\d+$/)
        choice_index = response_clean.to_i - 1
        if choice_index >= 0 && choice_index < choices.length
          selected_choice = choices[choice_index]
          return {
            choice: selected_choice,
            choice_index: choice_index,
            valid: true,
            reason: 'Valid numeric selection',
            timestamp: Time.now
          }
        end
      end
      
      # Try to match by text
      selected_choice = choices.find { |choice| choice.downcase.include?(response_clean.downcase) }
      if selected_choice
        return {
          choice: selected_choice,
          choice_index: choices.index(selected_choice),
          valid: true,
          reason: 'Valid text selection',
          timestamp: Time.now
        }
      end
      
      # Invalid selection
      {
        choice: nil,
        choice_index: nil,
        valid: false,
        reason: "Invalid selection: #{response}. Please choose from: #{choices.join(', ')}",
        timestamp: Time.now
      }
    end

    def process_review_response(response, interaction)
      return { feedback: nil, approved: false, reason: 'No response provided' } if response.nil?
      
      response_clean = response.strip.downcase
      
      # Check if it's a simple approval
      if @approval_keywords.any? { |keyword| response_clean == keyword }
        return {
          feedback: response,
          approved: true,
          reason: 'Content approved without changes',
          timestamp: Time.now
        }
      end
      
      # Otherwise treat as feedback
      {
        feedback: response,
        approved: false,
        reason: 'Feedback provided for review',
        suggested_changes: extract_suggestions(response),
        timestamp: Time.now
      }
    end

    def process_confirmation_response(response, interaction)
      process_approval_response(response, interaction)
    end

    def validate_input(input, validation_rules)
      return { valid: true, reason: 'No validation rules' } if validation_rules.empty?
      
      # Check minimum length
      if validation_rules[:min_length] && input.length < validation_rules[:min_length]
        return { valid: false, reason: "Input too short (minimum #{validation_rules[:min_length]} characters)" }
      end
      
      # Check maximum length
      if validation_rules[:max_length] && input.length > validation_rules[:max_length]
        return { valid: false, reason: "Input too long (maximum #{validation_rules[:max_length]} characters)" }
      end
      
      # Check pattern matching
      if validation_rules[:pattern] && !input.match?(validation_rules[:pattern])
        return { valid: false, reason: "Input doesn't match required pattern" }
      end
      
      # Check required keywords
      if validation_rules[:required_keywords]
        missing_keywords = validation_rules[:required_keywords].reject { |keyword| input.downcase.include?(keyword.downcase) }
        unless missing_keywords.empty?
          return { valid: false, reason: "Missing required keywords: #{missing_keywords.join(', ')}" }
        end
      end
      
      { valid: true, reason: 'Input passes validation' }
    end

    def process_input_value(input, options)
      return input unless options[:type]
      
      case options[:type]
      when :integer
        input.to_i
      when :float
        input.to_f
      when :boolean
        %w[true yes 1 y].include?(input.downcase)
      when :json
        begin
          JSON.parse(input)
        rescue JSON::ParserError
          input
        end
      else
        input
      end
    end

    def extract_suggestions(feedback)
      suggestions = []
      
      # Simple pattern matching for common suggestion indicators
      suggestion_patterns = [
        /(?:should|could|might want to|consider|suggest|recommend)\s+(.+?)(?:\.|$)/i,
        /(?:change|modify|update|fix|improve)\s+(.+?)(?:\.|$)/i,
        /(?:add|include|remove|delete)\s+(.+?)(?:\.|$)/i
      ]
      
      suggestion_patterns.each do |pattern|
        matches = feedback.scan(pattern)
        suggestions.concat(matches.flatten)
      end
      
      suggestions.map(&:strip).reject(&:empty?).uniq
    end

    def handle_auto_approval(interaction)
      @logger.debug "Auto-approving interaction: #{interaction[:id]}"
      {
        approved: true,
        response: 'auto-approved',
        reason: 'Auto-approval enabled',
        timestamp: Time.now
      }
    end

    def record_interaction(interaction, response, result)
      interaction[:response] = response
      interaction[:result] = result
      interaction[:completed_at] = Time.now
      interaction[:duration] = interaction[:completed_at] - interaction[:timestamp]
      
      @interactions << interaction
      @input_history << {
        type: interaction[:type],
        response: response,
        timestamp: Time.now
      }
      
      @logger.info "Human interaction completed: #{interaction[:type]} - #{result[:reason] || 'Success'}"
    end

    def calculate_session_duration
      return 0 if @interactions.empty?
      
      first = @interactions.first[:timestamp]
      last = @interactions.last[:completed_at] || @interactions.last[:timestamp]
      last - first
    end
  end

  # Extensions for agents and tasks to support human input
  module HumanInteractionExtensions
    def request_human_approval(message, **options)
      human_input_client.request_approval(message, **options)
    end

    def request_human_input(prompt, **options)
      human_input_client.request_input(prompt, **options)
    end

    def request_human_choice(prompt, choices, **options)
      human_input_client.request_choice(prompt, choices, **options)
    end

    def request_human_review(content, **options)
      human_input_client.request_review(content, **options)
    end

    def confirm_with_human(action, **options)
      human_input_client.confirm_action(action, **options)
    end

    def get_human_feedback(prompt, **options)
      human_input_client.get_feedback(prompt, **options)
    end

    private

    def human_input_client
      @human_input_client ||= HumanInput.new(
        session_id: "#{self.class.name.downcase}_#{name}",
        verbose: respond_to?(:verbose) ? verbose : false
      )
    end
  end
end