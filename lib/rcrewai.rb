# frozen_string_literal: true

require 'thor'
require 'faraday'
require 'json'
require 'logger'
require 'concurrent'
require 'nokogiri'

module RCrewAI
  class Error < StandardError; end

  def self.root
    @root ||= Pathname.new(File.expand_path('..', __dir__))
  end
end

# Load all components manually to ensure proper order
require_relative 'rcrewai/version'
require_relative 'rcrewai/configuration'
require_relative 'rcrewai/events'
require_relative 'rcrewai/sse_parser'
require_relative 'rcrewai/pricing'
require_relative 'rcrewai/llm_client'
require_relative 'rcrewai/similarity'
require_relative 'rcrewai/memory'
require_relative 'rcrewai/memory/in_memory_store'
require_relative 'rcrewai/memory/sqlite_store'
require_relative 'rcrewai/memory/base_memory'
require_relative 'rcrewai/memory/short_term_memory'
require_relative 'rcrewai/memory/long_term_memory'
require_relative 'rcrewai/memory/entity_memory'
require_relative 'rcrewai/memory/llm_entity_extractor'
require_relative 'rcrewai/memory/tool_memory'
require_relative 'rcrewai/rate_limiter'
require_relative 'rcrewai/context_window'
require_relative 'rcrewai/multimodal'
require_relative 'rcrewai/knowledge'
require_relative 'rcrewai/human_input'
require_relative 'rcrewai/tool_schema'
require_relative 'rcrewai/provider_schema'
require_relative 'rcrewai/tools/base'
require_relative 'rcrewai/tools/web_search'
require_relative 'rcrewai/tools/file_reader'
require_relative 'rcrewai/tools/file_writer'
require_relative 'rcrewai/tools/sql_database'
require_relative 'rcrewai/tools/email_sender'
require_relative 'rcrewai/tools/code_executor'
require_relative 'rcrewai/tools/pdf_processor'
require_relative 'rcrewai/tool_runner'
require_relative 'rcrewai/legacy_react_runner'
require_relative 'rcrewai/process'
require_relative 'rcrewai/async_executor'
require_relative 'rcrewai/agent'
require_relative 'rcrewai/task'
require_relative 'rcrewai/crew'
require_relative 'rcrewai/flow'
require_relative 'rcrewai/mcp'
