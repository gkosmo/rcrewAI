# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'

module AgentHarnessTutorial
  Block = Struct.new(:code, :line, :outputs, keyword_init: true)

  # What a run of the tutorial left behind.
  Run = Struct.new(:blocks, :stdout, :env_after, :env_writes, :received, :scripts, :sandbox, :scope, :keys_on_disk,
                   keyword_init: true)
end

# Runs docs/tutorials/agent-harness.md as a reader would: every ```ruby block, in
# order, in one binding, in an empty directory. The tutorial's own scripted model
# stands in for an LLM, and WebMock stops any network use.
#
# A block preceded by <!-- not-run --> is skipped. A ```text block preceded by
# <!-- output --> lists lines the ruby block before it must have printed.
RSpec.describe 'the agent harness tutorial' do
  tutorial = File.expand_path('../../docs/tutorials/agent-harness.md', __dir__)

  def parse(path)
    blocks = []
    marker = nil
    fence = nil
    File.readlines(path).each.with_index(1) do |line, number|
      if fence
        next fence[:body] << line unless line.start_with?('```')

        close_fence(fence, blocks)
        fence = nil
      elsif line.start_with?('```')
        fence = { language: line.delete_prefix('```').strip, marker: marker, line: number + 1, body: +'' }
        marker = nil
      elsif !line.strip.empty?
        marker = line.strip[/\A<!-- (not-run|output) -->\z/, 1]
      end
    end
    blocks
  end

  def close_fence(fence, blocks)
    case [fence[:language], fence[:marker]]
    in ['ruby', nil] then blocks << AgentHarnessTutorial::Block.new(code: fence[:body], line: fence[:line], outputs: [])
    in ['ruby', 'not-run'] then nil
    in [_, 'output'] then blocks.last.outputs << fence[:body]
    else nil
    end
  end

  def run_tutorial(path)
    run = AgentHarnessTutorial::Run.new(blocks: parse(path), stdout: [], env_after: [], env_writes: [], received: [], scripts: [])
    run.sandbox = Module.new.tap { |m| m.extend(m) }
    watch_env_writes(run)

    in_empty_project do
      run.scope = empty_scope(run.sandbox)
      run.blocks.each do |block|
        run.stdout << capture_stdout { run.scope.eval(block.code, path, block.line) }
        run.env_after << (File.exist?('.env') ? File.read('.env') : nil)
        watch_model(run)
      end
      run.keys_on_disk = Dir.glob('**/*', File::FNM_DOTMATCH).select do |file|
        File.file?(file) && File.read(file).include?('AKIAFAKE')
      end
    end
    run
  end

  # A binding with nothing of this spec's in it: from inside #run_tutorial, an
  # assignment in the tutorial could overwrite that method's own locals.
  def empty_scope(sandbox_module)
    sandbox_module.module_eval('binding', __FILE__, __LINE__)
  end

  # FileWriter writes through File.open, so this sees a write even when it
  # leaves the same bytes behind.
  def watch_env_writes(run)
    allow(File).to receive(:open).and_wrap_original do |original, *args, &body|
      # The keywords arrive as a last positional Hash, so pass them on as keywords.
      options = args.last.is_a?(Hash) ? args.pop : {}
      name, mode = args
      run.env_writes << run.stdout.length if File.basename(name.to_s).match?(/\A\.env/i) && mode.to_s.match?(/[wa+]/)
      original.call(*args, **options, &body)
    end
  end

  # Records every message sent to the tutorial's model, and each model made.
  def watch_model(run)
    return if @watching || !run.sandbox.const_defined?(:ScriptedModel, false)

    @watching = true
    run.sandbox.const_get(:ScriptedModel).prepend(Module.new do
      define_method(:initialize) do |*calls|
        super(*calls)
        run.scripts << @calls # the model's own queue, emptied as it plays
      end

      define_method(:chat) do |messages:, **options|
        run.received.concat(messages.map { |message| message[:content].to_s })
        super(messages: messages, **options)
      end
    end)
  end

  # $stdin claims to be a terminal, so the "no terminal" step only passes if the
  # tutorial takes the terminal away itself.
  def in_empty_project(&block)
    original = $stdin
    terminal = StringIO.new
    def terminal.tty? = true
    $stdin = terminal
    Dir.mktmpdir('harness-tutorial') do |root|
      project = File.join(root, 'assistant-demo')
      Dir.mkdir(project)
      Dir.chdir(project, &block)
    end
  ensure
    $stdin = original
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  let(:run) { run_tutorial(tutorial) }
  let(:first_guarded) { run.blocks.index { |block| block.code.include?('RCrewAI::Harness.new') } }
  let(:received) { run.received.join("\n") }

  it 'runs every block and prints what the text says it prints' do
    expect(run.blocks).not_to be_empty
    run.blocks.zip(run.stdout).each do |block, printed|
      block.outputs.flat_map(&:lines).map(&:chomp).reject(&:empty?).each do |line|
        expect(printed).to include(line), "block at line #{block.line} did not print #{line.inspect}:\n#{printed}"
      end
    end
    expect(run.blocks.sum { |block| block.outputs.length }).to be >= 7
  end

  it 'plays every scripted tool call' do
    expect(run.scripts).not_to be_empty
    expect(run.scripts).to all(be_empty)
  end

  it 'really overwrites .env while there is no harness' do
    expect(run.env_writes.count { |block| block < first_guarded }).to eq(1)
    expect(run.env_after.first(first_guarded)).to include("API_TOKEN=overwritten-by-the-model\n")
  end

  it 'never writes .env once the harness is in place' do
    expect(run.env_writes.select { |block| block >= first_guarded }).to be_empty
    expect(run.env_after.drop(first_guarded).uniq).to eq(["API_TOKEN=fake-original-token\n"])
  end

  it 'sends the model the refusals' do
    expect(received).to include("REFUSED: Tool 'file_reader' was not run: .env files are off limits")
    expect(received).to include("REFUSED: Tool 'file_writer' was not run: .env files are off limits")
    expect(received).to include("REFUSED: Tool 'file_writer' was not run: Lockfiles are generated")
    expect(received).to include('there is no terminal to ask')
    expect(received).to include('needs a person to agree')
    expect(received).to include('The content looks like it contains a key')
    expect(received).to include('returned a value of class FalseClass')
    expect(received).not_to include('fake-original-token')
  end

  it 'never writes the key-shaped sample to disk' do
    expect(run.keys_on_disk).to be_empty
  end

  it "sends the model the after hook's syntax error" do
    note = run.received.find { |content| content.include?('ruby -c found a syntax error in greeter.rb') }
    expect(note).to match(/syntax error.*greeter\.rb.*syntax error/m)
  end

  it 'has patterns that cover what the text says they cover' do
    secrets = run.sandbox.const_get(:SECRETS)
    locks = run.sandbox.const_get(:LOCKFILES)

    expect(%w[.env .env.local .ENV .Env.Production .envrc config/.env.example /srv/app/.env a/../.env]).to all(match(secrets))
    ['production.env', 'environment.rb', 'docs/env.md', '.env/notes.md', 'config/master.key', 'secrets.yml'].each do |path|
      expect(path).not_to match(secrets)
    end
    expect(%w[Gemfile.lock yarn.lock Cargo.LOCK poetry.lock composer.lock package-lock.json web/pnpm-lock.yaml
              npm-shrinkwrap.json]).to all(match(locks))
    %w[Gemfile package.json go.sum bun.lockb lock.rb my-package-lock.json].each do |path|
      expect(path).not_to match(locks)
    end
  end

  it 'syntax-checks a file whose name looks like a command-line option' do
    harness = run.scope.local_variable_get(:harness)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('-eputs.rb', "def broken(\n")
        call = RCrewAI::Harness::Call.new(tool_name: 'file_writer', args: { 'file_path' => '-eputs.rb' }.freeze)

        expect(harness.run_after(call).map(&:text).join).to include('ruby -c found a syntax error in -eputs.rb')
      end
    end
  end
end
