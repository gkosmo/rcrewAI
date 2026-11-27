# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Real files and symlinks:
#
#   base/proj           the working directory
#   base/proj-other     a sibling whose name starts the same way
#   base/outside
RSpec.describe 'file tools stay inside the working directory' do
  around do |example|
    Dir.mktmpdir do |tmp|
      @base = File.realpath(tmp)
      %w[proj/docs proj-other outside/deep].each { |dir| FileUtils.mkdir_p(File.join(@base, dir)) }
      Dir.chdir(File.join(@base, 'proj')) { example.run }
    end
  end

  def outside(name) = File.join(@base, name)

  def put(path, text = 'secret')
    File.write(path, text)
    path
  end

  def link(target, name) = File.symlink(target, name)

  describe RCrewAI::Tools::FileReader do
    subject(:reader) { described_class.new }

    def read(path) = reader.execute(file_path: path)

    def expect_denied(path)
      result = read(path)

      expect(result).to include('Access denied')
      expect(result).not_to include('secret')
    end

    it 'reads a file inside, by relative or absolute path' do
      put('docs/a.txt', 'hello')

      expect(read('docs/a.txt')).to include('hello')
      expect(read(File.expand_path('docs/a.txt'))).to include('hello')
    end

    it 'refuses a sibling directory with the same prefix' do
      put(outside('proj-other/a.txt'))

      expect_denied('../proj-other/a.txt')
      expect_denied(outside('proj-other/a.txt'))
    end

    it 'refuses symlinks that lead outside' do
      put(outside('outside/a.txt'))
      link(outside('outside/a.txt'), 'file.txt')
      link(outside('outside'), 'dir')

      expect_denied('file.txt')
      expect_denied('dir/a.txt')
    end

    it 'follows ".." after a symlink the way the system does' do
      put(outside('outside/a.txt'))
      put('a.txt', 'harmless')
      link(outside('outside/deep'), 'dir')

      # Lexically this is ./a.txt, but opening it reaches outside/a.txt.
      expect_denied('dir/../a.txt')
    end

    it "doesn't say whether a file outside exists" do
      put(outside('outside/a.txt'))

      expect(read('../outside/a.txt')).to eq(read('../outside/missing.txt'))
    end

    it 'follows a symlink that stays inside' do
      put('docs/a.txt', 'hello')
      link('docs/a.txt', 'alias.txt')

      expect(read('alias.txt')).to include('hello')
    end

    it 'checks the extension of the file a symlink points to' do
      put('.env')
      link('.env', 'notes.txt')

      result = read('notes.txt')

      expect(result).to include('File type not allowed')
      expect(result).not_to include('secret')
    end

    it 'reports a missing file inside by the path that was asked for' do
      result = read('docs/none.txt')

      expect(result).to include('does not exist: docs/none.txt')
      expect(result).not_to include(Dir.pwd)
    end

    it 'says nothing about a disallowed file beyond its type' do
      put('.env', 'x' * 20)
      small = described_class.new(max_file_size: 1)

      expect(small.execute(file_path: '.env')).to include('File type not allowed')
      expect(read('missing.env')).to include('File type not allowed')
    end

    it 'describes the file it read when the given path only resolves to it' do
      put('a.txt', 'hello')

      expect(read('missing/../a.txt')).to include('hello', 'Size: 5 bytes')
    end
  end

  describe RCrewAI::Tools::FileWriter do
    subject(:writer) { described_class.new }

    def write(path, mode: 'w') = writer.execute(file_path: path, content: 'written', mode: mode)

    def expect_denied(path)
      expect(write(path)).to include('Access denied')
    end

    it 'writes inside, creating directories' do
      expect(write('new/dir/a.txt')).to start_with('Content successfully written')
      expect(File.read('new/dir/a.txt')).to eq('written')
    end

    it 'refuses a sibling directory with the same prefix' do
      expect_denied('../proj-other/a.txt')

      expect(File).not_to exist(outside('proj-other/a.txt'))
    end

    it 'refuses to write or append through a symlinked file' do
      target = put(outside('outside/a.txt'))
      link(target, 'file.txt')

      expect_denied('file.txt')
      expect(write('file.txt', mode: 'a')).to include('Access denied')
      expect(File.read(target)).to eq('secret')
    end

    it 'refuses a symlink to a file that does not exist yet' do
      link(outside('outside/new.txt'), 'dangling.txt')

      expect_denied('dangling.txt')
      expect(File).not_to exist(outside('outside/new.txt'))
    end

    it 'refuses a symlinked directory, without creating anything beyond it' do
      link(outside('outside'), 'dir')

      expect_denied('dir/a.txt')
      expect_denied('dir/made/a.txt')
      expect(Dir.children(outside('outside'))).to eq(['deep'])
    end

    it 'follows ".." after a symlink the way the system does' do
      link(outside('outside/deep'), 'dir')

      expect_denied('dir/../a.txt')
      expect(File).not_to exist(outside('outside/a.txt'))
    end

    it 'refuses ".." out of a directory that does not exist yet' do
      expect_denied('missing/../../outside/a.txt')

      expect(File).not_to exist(outside('outside/a.txt'))
    end

    it 'refuses a symlink loop' do
      link('loop.txt', 'loop.txt')

      expect_denied('loop.txt')
    end

    it 'follows a symlink that stays inside' do
      put('docs/a.txt', 'old')
      link('docs/a.txt', 'alias.txt')

      expect(write('alias.txt')).to start_with('Content successfully')
      expect(File.read('docs/a.txt')).to eq('written')
    end

    it 'checks the extension of the file a symlink points to' do
      put('.env')
      link('.env', 'notes.txt')

      expect(write('notes.txt')).to include('File type not allowed')
      expect(File.read('.env')).to eq('secret')
    end

    ['notes.txt/', 'notes.txt/.', 'new.txt/'].each do |path|
      it "refuses #{path.inspect}, which names a directory" do
        put('notes.txt', 'keep')

        expect(write(path)).to include('Path is not a file')
        expect(File.read('notes.txt')).to eq('keep')
        expect(File).not_to exist('new.txt')
      end
    end

    it 'names the path that was asked for in errors' do
      FileUtils.mkdir('folder.txt')

      result = write('folder.txt')

      expect(result).to include('Path is not a file: folder.txt')
      expect(result).not_to include(Dir.pwd)
    end

    it 'treats "~" as an ordinary directory name, as opening it does' do
      expect(write('~/a.txt')).to start_with('Content successfully')
      expect(File.read(File.join(Dir.pwd, '~', 'a.txt'))).to eq('written')
    end
  end

  describe RCrewAI::Tools::PdfProcessor do
    def process(path, **options) = described_class.new(**options).execute(file_path: path)

    it 'refuses a sibling directory with the same prefix' do
      put(outside('proj-other/a.pdf'))

      expect(process('../proj-other/a.pdf')).to include('Access denied')
    end

    it 'refuses a symlink that leads outside' do
      put(outside('outside/a.pdf'))
      link(outside('outside/a.pdf'), 'a.pdf')

      expect(process('a.pdf')).to include('Access denied')
    end

    it 'opens exactly the file it checked' do
      put('docs/a.pdf', '%PDF-1.4')
      link('docs/a.pdf', 'alias.pdf')
      allow(PDF::Reader).to receive(:new).and_raise('stop here')

      process('alias.pdf')

      expect(PDF::Reader).to have_received(:new).with(File.join(Dir.pwd, 'docs/a.pdf'))
    end

    it 'accepts a relative or symlinked working_directory' do
      put('docs/a.pdf', '%PDF-1.4')
      link('docs', 'shortcut')
      allow(PDF::Reader).to receive(:new).and_raise('reached the reader')

      %w[docs shortcut].each do |dir|
        expect(process('docs/a.pdf', working_directory: dir)).to include('reached the reader')
      end
    end

    it 'refuses everything when the working_directory is missing' do
      put('docs/a.pdf', '%PDF-1.4')

      expect(process('docs/a.pdf', working_directory: 'nope')).to include('Access denied')
    end
  end

  it 'allows everything under the filesystem root when that is the working directory' do
    put('a.pdf', '%PDF-1.4')
    allow(PDF::Reader).to receive(:new).and_raise('reached the reader')

    result = RCrewAI::Tools::PdfProcessor.new(working_directory: '/').execute(file_path: 'a.pdf')

    expect(result).to include('reached the reader')
  end
end
