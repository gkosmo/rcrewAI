# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'base64'

RSpec.describe RCrewAI::Multimodal do
  describe '.content_parts' do
    it 'returns a plain text part for text with no attachments' do
      parts = described_class.content_parts('hello', [])

      expect(parts).to eq([{ type: 'text', text: 'hello' }])
    end

    it 'adds an image_url part for a URL attachment' do
      parts = described_class.content_parts('look', [{ type: :image, url: 'https://x/y.png' }])

      expect(parts).to include({ type: 'text', text: 'look' })
      expect(parts).to include({ type: 'image_url', image_url: { url: 'https://x/y.png' } })
    end

    it 'base64-encodes a local image file as a data URL' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pic.png')
        File.binwrite(path, "\x89PNG\r\n\x1a\nDATA")

        parts = described_class.content_parts('see', [{ type: :image, path: path }])
        image_part = parts.find { |p| p[:type] == 'image_url' }

        expect(image_part[:image_url][:url]).to start_with('data:image/png;base64,')
        expect(image_part[:image_url][:url]).to include(Base64.strict_encode64("\x89PNG\r\n\x1a\nDATA"))
      end
    end

    it 'infers mime type from the file extension' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pic.jpg')
        File.binwrite(path, 'JPEGDATA')

        parts = described_class.content_parts('x', [{ type: :image, path: path }])
        url = parts.find { |p| p[:type] == 'image_url' }[:image_url][:url]

        expect(url).to start_with('data:image/jpeg;base64,')
      end
    end

    it 'raises for an unsupported attachment type' do
      expect { described_class.content_parts('x', [{ type: :video, url: 'v' }]) }
        .to raise_error(RCrewAI::Multimodal::UnsupportedAttachmentError)
    end
  end
end

RSpec.describe 'Multimodal wiring into Agent' do
  before { configure_test_llm(provider: :openai) }

  it 'builds a multimodal user message when the task has attachments' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')
    task = RCrewAI::Task.new(
      name: 't', description: 'Describe this', agent: agent,
      attachments: [{ type: :image, url: 'https://x/y.png' }]
    )

    messages = agent.send(:build_initial_messages, task)
    user = messages.find { |m| m[:role] == 'user' }

    expect(user[:content]).to be_an(Array)
    expect(user[:content]).to include({ type: 'image_url', image_url: { url: 'https://x/y.png' } })
  end

  it 'keeps a plain string user message when there are no attachments' do
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')
    task = RCrewAI::Task.new(name: 't', description: 'hi', agent: agent)

    messages = agent.send(:build_initial_messages, task)
    user = messages.find { |m| m[:role] == 'user' }

    expect(user[:content]).to be_a(String)
  end

  it 'raises a clear error when attachments are used with a non-OpenAI provider' do
    configure_test_llm(provider: :ollama)
    agent = RCrewAI::Agent.new(name: 'a', role: 'r', goal: 'g')
    task = RCrewAI::Task.new(
      name: 't', description: 'x', agent: agent,
      attachments: [{ type: :image, url: 'https://x/y.png' }]
    )

    expect { agent.send(:build_initial_messages, task) }
      .to raise_error(RCrewAI::Multimodal::UnsupportedProviderError, /ollama/)
  end
end
