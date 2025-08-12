# frozen_string_literal: true

require "thor"
require "faraday"
require "json"
require "logger"
require "concurrent"
require "nokogiri"

module RCrewAI
  class Error < StandardError; end
  
  def self.root
    @root ||= Pathname.new(File.expand_path("..", __dir__))
  end
end

# Load all components manually to ensure proper order
require_relative 'rcrewai/version'
require_relative 'rcrewai/configuration'
require_relative 'rcrewai/llm_client'
require_relative 'rcrewai/memory'
require_relative 'rcrewai/human_input'
require_relative 'rcrewai/tools/base'
require_relative 'rcrewai/tools/web_search'
require_relative 'rcrewai/tools/file_reader'
require_relative 'rcrewai/tools/file_writer'
require_relative 'rcrewai/tools/sql_database'
require_relative 'rcrewai/tools/email_sender'
require_relative 'rcrewai/tools/code_executor'
require_relative 'rcrewai/tools/pdf_processor'
require_relative 'rcrewai/process'
require_relative 'rcrewai/async_executor'
require_relative 'rcrewai/agent'
require_relative 'rcrewai/task'  
require_relative 'rcrewai/crew'