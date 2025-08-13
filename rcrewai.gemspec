# frozen_string_literal: true

require_relative "lib/rcrewai/version"

Gem::Specification.new do |spec|
  spec.name = "rcrewai"
  spec.version = RCrewAI::VERSION
  spec.authors = ["gkosmo"]
  spec.email = ["gkosmo1@hotmail.com"]

  spec.summary = "Build intelligent AI agent crews in Ruby - CrewAI implementation with multi-LLM support"
  spec.description = <<~DESC
    RCrewAI is a powerful Ruby framework for creating autonomous AI agent crews that collaborate to solve complex tasks.
    Build intelligent workflows with reasoning agents, tool usage, memory systems, and human oversight.

    Key Features:
    • Multi-Agent Orchestration: Create crews of specialized AI agents that work together
    • Multi-LLM Support: OpenAI GPT-4, Anthropic Claude, Google Gemini, Azure OpenAI, Ollama
    • Rich Tool Ecosystem: Web search, file operations, SQL databases, email, code execution, PDF processing
    • Agent Memory: Short-term and long-term memory for learning from past executions
    • Human-in-the-Loop: Interactive approval workflows and collaborative decision making
    • Advanced Task Management: Dependencies, retries, async execution, and context sharing
    • Hierarchical Teams: Manager agents that coordinate and delegate to specialist agents
    • Production Ready: Security controls, error handling, comprehensive logging, and monitoring
    • Ruby-First Design: Built specifically for Ruby developers with idiomatic patterns
    • CLI Tools: Command-line interface for creating and managing AI crews
  DESC
  spec.homepage = "https://github.com/gkosmo/rcrewAI"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://gkosmo.github.io/rcrewAI/"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["rcrewai"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "logger", "~> 1.5"
  spec.add_dependency "concurrent-ruby", "~> 1.2"
  spec.add_dependency "nokogiri", "~> 1.15"
  spec.add_dependency "ruby-openai", "~> 6.3"
  spec.add_dependency "anthropic", "~> 0.2"
  spec.add_dependency "pdf-reader", "~> 2.11"
  spec.add_dependency "mail", "~> 2.8"
  
  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rspec", "~> 2.20"
end