# frozen_string_literal: true

require 'base64'

module RCrewAI
  # Builds multimodal message content (text + images) in the OpenAI
  # chat-completions format:
  #   [{ type: 'text', text: '...' },
  #    { type: 'image_url', image_url: { url: '...' } }]
  #
  # Local image paths are base64-encoded into data URLs; URLs pass through.
  # Only OpenAI-style multimodal is supported today; other providers raise.
  module Multimodal
    SUPPORTED_PROVIDERS = %i[openai azure].freeze

    MIME_TYPES = {
      '.png' => 'image/png',
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp'
    }.freeze

    module_function

    # Returns an OpenAI-style content-parts array for the given text and
    # attachments. With no attachments this is a single text part.
    def content_parts(text, attachments)
      parts = [{ type: 'text', text: text.to_s }]
      Array(attachments).each { |att| parts << image_part(att) }
      parts
    end

    def supported_provider?(provider)
      SUPPORTED_PROVIDERS.include?(provider.to_sym)
    end

    def ensure_supported_provider!(provider)
      return if supported_provider?(provider)

      raise UnsupportedProviderError,
            "multimodal attachments are not supported for provider #{provider}"
    end

    def image_part(attachment)
      type = attachment[:type] || attachment['type']
      raise UnsupportedAttachmentError, "unsupported attachment type: #{type.inspect}" unless type.to_sym == :image

      url = attachment[:url] || attachment['url']
      path = attachment[:path] || attachment['path']
      resolved = url || data_url_for(path)

      { type: 'image_url', image_url: { url: resolved } }
    end

    def data_url_for(path)
      raise UnsupportedAttachmentError, 'image attachment needs a :url or :path' unless path

      mime = MIME_TYPES[File.extname(path).downcase] || 'application/octet-stream'
      encoded = Base64.strict_encode64(File.binread(path))
      "data:#{mime};base64,#{encoded}"
    end

    class UnsupportedAttachmentError < RCrewAI::Error; end
    class UnsupportedProviderError < RCrewAI::Error; end
  end
end
