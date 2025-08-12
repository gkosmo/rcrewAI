# frozen_string_literal: true

module RCrewAI
  class CLI < Thor
    desc "new CREW_NAME", "Create a new AI crew"
    def new(crew_name)
      puts "Creating new crew: #{crew_name}"
      Crew.create(crew_name)
    end

    desc "run", "Run the AI crew"
    option :crew, type: :string, required: true, desc: "Name of the crew to run"
    def run
      crew_name = options[:crew]
      puts "Running crew: #{crew_name}"
      crew = Crew.load(crew_name)
      crew.execute
    end

    desc "list", "List all available crews"
    def list
      puts "Available crews:"
      Crew.list.each do |crew|
        puts "  - #{crew}"
      end
    end

    desc "agent SUBCOMMAND ...ARGS", "Manage agents"
    subcommand "agent", Agent::CLI

    desc "task SUBCOMMAND ...ARGS", "Manage tasks"
    subcommand "task", Task::CLI

    desc "version", "Show version"
    def version
      puts "rcrewai version #{RCrewAI::VERSION}"
    end
  end
end