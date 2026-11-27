# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

# Real files and symlinks:
#
#   base/proj           the working directory
#   base/proj-other     a sibling whose name starts the same way
#   base/outside
RSpec.describe RCrewAI::Tools::EmailSender, 'attachments' do
  around do |example|
    Dir.mktmpdir do |tmp|
      @base = File.realpath(tmp)
      %w[proj/reports proj-other outside].each { |dir| FileUtils.mkdir_p(File.join(@base, dir)) }
      Dir.chdir(File.join(@base, 'proj')) { example.run }
    end
  end

  let(:sent) { [] }

  # Nothing is delivered. The message is kept so the test can look at it.
  before do
    delivered = sent
    allow_any_instance_of(Mail::Message).to receive(:deliver!) { |message| delivered << message }
  end

  def outside(name) = File.join(@base, name)

  def put(path, text = 'secret')
    File.write(path, text)
    path
  end

  def send_with(*paths, **options)
    described_class.new(**options).execute(to: 'someone@example.test', subject: 'report', body: 'attached',
                                           attachments: paths)
  end

  def attached
    sent.flat_map { |message| message.attachments.map { |a| [a.filename, a.body.decoded] } }
  end

  def expect_refused(result, why)
    expect(result).to start_with('Email sending failed:').and include(why)
    expect(sent).to be_empty
  end

  it 'attaches a file inside the working directory, under the name asked for' do
    put('reports/a.txt', 'numbers')

    expect(send_with('reports/a.txt')).to start_with('Email sent successfully')
    expect(attached).to eq([['a.txt', 'numbers']])
  end

  it 'refuses files outside, by relative or absolute path' do
    put(outside('outside/a.txt'))

    expect_refused(send_with('../outside/a.txt'), 'Access denied')
    expect_refused(send_with(outside('outside/a.txt')), 'Access denied')
  end

  it 'refuses a sibling directory with the same prefix' do
    put(outside('proj-other/a.txt'))

    expect_refused(send_with('../proj-other/a.txt'), 'Access denied')
  end

  it 'refuses a symlink that leads outside' do
    put(outside('outside/a.txt'))
    File.symlink(outside('outside/a.txt'), 'a.txt')

    expect_refused(send_with('a.txt'), 'Access denied')
  end

  it 'sends nothing when only one of several attachments is refused' do
    put('reports/a.txt')
    put(outside('outside/b.txt'))

    expect_refused(send_with('reports/a.txt', '../outside/b.txt'), 'Access denied')
  end

  it 'limits a single path given as a string too' do
    put(outside('outside/a.txt'))

    result = described_class.new.execute(to: 'someone@example.test', subject: 's', body: 'attached',
                                         attachments: '../outside/a.txt')

    expect_refused(result, 'Access denied')
  end

  it 'checks the type of the link and of the file it points to' do
    put('.env')
    put('notes.txt')
    File.symlink('.env', 'config.txt')
    File.symlink('notes.txt', 'notes.key')

    expect_refused(send_with('config.txt'), 'file type not allowed')
    expect_refused(send_with('notes.key'), 'file type not allowed')
  end

  it 'attaches the target of a link inside, under the name of the link' do
    put('reports/a.txt', 'numbers')
    File.symlink('reports/a.txt', 'latest.txt')

    send_with('latest.txt')

    expect(attached).to eq([%w[latest.txt numbers]])
  end

  it "doesn't say whether a file outside exists" do
    put(outside('outside/a.txt'))

    expect(send_with('../outside/a.txt').sub('a.txt', 'x')).to eq(send_with('../outside/none.txt').sub('none.txt', 'x'))
  end

  it 'names a missing file by the path that was asked for' do
    result = send_with('reports/none.txt')

    expect_refused(result, 'Attachment file not found: reports/none.txt')
    expect(result).not_to include(Dir.pwd)
  end

  it 'refuses a directory' do
    FileUtils.mkdir('folder.txt')

    expect_refused(send_with('folder.txt'), 'not found')
  end

  it 'still refuses a file that is too large' do
    put('big.txt', 'x' * 10_000_001)

    expect_refused(send_with('big.txt'), 'too large')
  end

  describe 'attachment_directory' do
    it 'allows only that directory, even within the working directory' do
      put('reports/a.txt', 'numbers')
      put('notes.txt')

      expect_refused(send_with('notes.txt', attachment_directory: 'reports'), 'Access denied')
      expect(send_with('reports/a.txt', attachment_directory: 'reports')).to start_with('Email sent')
    end

    it 'can be a directory outside the working directory' do
      put(outside('outside/a.txt'), 'numbers')

      send_with('../outside/a.txt', attachment_directory: outside('outside'))

      expect(attached).to eq([['a.txt', 'numbers']])
    end

    it 'allows nothing when it is missing' do
      put('reports/a.txt')

      expect_refused(send_with('reports/a.txt', attachment_directory: 'nope'), 'Access denied')
    end
  end

  it 'still sends a message without attachments' do
    result = described_class.new.execute(to: 'someone@example.test', subject: 's', body: 'hello')

    expect(result).to start_with('Email sent successfully')
  end
end
