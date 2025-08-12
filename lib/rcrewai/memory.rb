# frozen_string_literal: true

require 'json'
require 'digest'

module RCrewAI
  class Memory
    attr_reader :short_term, :long_term, :tool_usage

    def initialize
      @short_term = []  # Recent executions, limited size
      @long_term = {}   # Persistent memory, keyed by task type/similarity
      @tool_usage = []  # Tool usage history
      @max_short_term = 100
      @similarity_threshold = 0.7
    end

    def add_execution(task, result, execution_time)
      execution_data = {
        task_name: task.name,
        task_description: task.description,
        task_type: classify_task_type(task),
        result: result,
        execution_time: execution_time,
        timestamp: Time.now,
        success: !result.to_s.downcase.include?('failed'),
        hash: generate_task_hash(task)
      }

      # Add to short-term memory
      @short_term.unshift(execution_data)
      @short_term = @short_term.first(@max_short_term)

      # Add to long-term memory if successful
      if execution_data[:success]
        task_type = execution_data[:task_type]
        @long_term[task_type] ||= []
        @long_term[task_type] << execution_data
        
        # Keep only best executions for each type
        @long_term[task_type] = @long_term[task_type]
          .sort_by { |e| [e[:success] ? 0 : 1, -e[:execution_time]] }
          .first(10)
      end
    end

    def add_tool_usage(tool_name, params, result)
      usage_data = {
        tool_name: tool_name,
        params: params,
        result: result,
        timestamp: Time.now,
        success: !result.to_s.downcase.include?('error')
      }

      @tool_usage.unshift(usage_data)
      @tool_usage = @tool_usage.first(50)  # Keep last 50 tool usages
    end

    def relevant_executions(task, limit = 3)
      task_type = classify_task_type(task)
      task_hash = generate_task_hash(task)

      # Get similar executions from both short and long term memory
      candidates = []

      # Check short-term for exact or similar matches
      @short_term.each do |execution|
        if execution[:hash] == task_hash
          candidates << { execution: execution, similarity: 1.0 }
        elsif execution[:task_type] == task_type
          similarity = calculate_similarity(task, execution)
          candidates << { execution: execution, similarity: similarity } if similarity > @similarity_threshold
        end
      end

      # Check long-term memory
      if @long_term[task_type]
        @long_term[task_type].each do |execution|
          similarity = calculate_similarity(task, execution)
          candidates << { execution: execution, similarity: similarity } if similarity > @similarity_threshold
        end
      end

      # Sort by similarity and success, return top results
      relevant = candidates
        .sort_by { |c| [-c[:similarity], c[:execution][:success] ? 0 : 1] }
        .first(limit)
        .map { |c| format_execution_for_context(c[:execution]) }

      relevant.empty? ? nil : relevant.join("\n---\n")
    end

    def tool_usage_for(tool_name, limit = 5)
      @tool_usage
        .select { |usage| usage[:tool_name] == tool_name }
        .first(limit)
        .map { |usage| format_tool_usage_for_context(usage) }
        .join("\n")
    end

    def clear_short_term!
      @short_term.clear
    end

    def clear_all!
      @short_term.clear
      @long_term.clear
      @tool_usage.clear
    end

    def stats
      {
        short_term_count: @short_term.length,
        long_term_types: @long_term.keys.length,
        long_term_total: @long_term.values.flatten.length,
        tool_usage_count: @tool_usage.length,
        success_rate: calculate_success_rate
      }
    end

    private

    def classify_task_type(task)
      description = task.description.downcase
      
      return :research if description.include?('research') || description.include?('find') || description.include?('search')
      return :analysis if description.include?('analyze') || description.include?('examine') || description.include?('study')
      return :writing if description.include?('write') || description.include?('create') || description.include?('compose')
      return :coding if description.include?('code') || description.include?('program') || description.include?('develop')
      return :planning if description.include?('plan') || description.include?('strategy') || description.include?('organize')
      
      :general
    end

    def generate_task_hash(task)
      content = "#{task.name}:#{task.description}"
      Digest::SHA256.hexdigest(content)[0..16]
    end

    def calculate_similarity(task, execution)
      # Simple similarity based on common words and task type
      task_words = extract_keywords(task.description)
      execution_words = extract_keywords(execution[:task_description])
      
      common_words = (task_words & execution_words).length
      total_words = (task_words | execution_words).length
      
      return 0.0 if total_words == 0
      
      word_similarity = common_words.to_f / total_words
      
      # Boost similarity if task types match
      type_bonus = (classify_task_type(task) == execution[:task_type]) ? 0.2 : 0.0
      
      [word_similarity + type_bonus, 1.0].min
    end

    def extract_keywords(text)
      # Simple keyword extraction - remove common words
      stopwords = %w[the a an and or but in on at to for of with by]
      text.downcase.split(/\W+/).reject { |w| w.length < 3 || stopwords.include?(w) }
    end

    def format_execution_for_context(execution)
      success_indicator = execution[:success] ? "✓" : "✗"
      <<~CONTEXT
        #{success_indicator} Task: #{execution[:task_name]}
        Description: #{execution[:task_description]}
        Result: #{execution[:result][0..200]}#{'...' if execution[:result].length > 200}
        Time: #{execution[:execution_time].round(2)}s
        Date: #{execution[:timestamp].strftime('%Y-%m-%d %H:%M')}
      CONTEXT
    end

    def format_tool_usage_for_context(usage)
      success_indicator = usage[:success] ? "✓" : "✗"
      params_str = usage[:params].map { |k, v| "#{k}=#{v}" }.join(', ')
      <<~CONTEXT
        #{success_indicator} Tool: #{usage[:tool_name]}
        Params: #{params_str}
        Result: #{usage[:result][0..100]}#{'...' if usage[:result].to_s.length > 100}
        Date: #{usage[:timestamp].strftime('%Y-%m-%d %H:%M')}
      CONTEXT
    end

    def calculate_success_rate
      return 0.0 if @short_term.empty?
      
      successful = @short_term.count { |e| e[:success] }
      (successful.to_f / @short_term.length * 100).round(1)
    end
  end
end