# frozen_string_literal: true

module RCrewAI
  class CLI < Thor
    desc 'new CREW_NAME', 'Create a new AI crew'
    def new(crew_name)
      puts "Creating new crew: #{crew_name}"
      Crew.create(crew_name)
    end

    # Thor reserves #run, so the command is defined under another name and
    # mapped back. Without this the whole class raises on load, which is why
    # cli.rb went unrequired -- and why bin/rcrewai never worked.
    desc 'run', 'Run the AI crew'
    option :crew, type: :string, required: true, desc: 'Name of the crew to run'
    map 'run' => :run_crew
    def run_crew
      crew_name = options[:crew]
      puts "Running crew: #{crew_name}"
      crew = Crew.load(crew_name)
      crew.execute
    end

    desc 'list', 'List all available crews'
    def list
      puts 'Available crews:'
      Crew.list.each do |crew|
        puts "  - #{crew}"
      end
    end

    desc 'agent SUBCOMMAND ...ARGS', 'Manage agents'
    subcommand 'agent', Agent::CLI

    desc 'task SUBCOMMAND ...ARGS', 'Manage tasks'
    subcommand 'task', Task::CLI

    desc 'checkpoint SUBCOMMAND ...ARGS', 'Inspect run checkpoints'
    subcommand 'checkpoint', Checkpoint::CLI

    desc 'version', 'Show version'
    def version
      puts "rcrewai version #{RCrewAI::VERSION}"
    end

    def self.exit_on_failure?
      true
    end
  end
end
