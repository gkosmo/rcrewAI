# frozen_string_literal: true

require_relative 'base'
require 'net/smtp'
require 'mail'

module RCrewAI
  module Tools
    class EmailSender < Base
      tool_name        "email_sender"
      description      "Send an email via configured SMTP"
      param :to,       type: :string, required: true,
                       description: "Recipient address. Multiple addresses may be separated by commas."
      param :subject,  type: :string, required: true, description: "Email subject"
      param :body,     type: :string, required: true, description: "Email body (plain text or HTML)"
      param :cc,       type: :string, required: false, description: "CC recipients (comma-separated)"
      param :bcc,      type: :string, required: false, description: "BCC recipients (comma-separated)"
      param :reply_to, type: :string, required: false, description: "Reply-to address"
      param :attachments, type: :array, required: false, items: { type: :string },
                          description: "File paths to attach. Allowed extensions: pdf, txt, doc(x), xls(x), jpg, png, gif, zip."

      def initialize(**options)
        super()
        @smtp_server = options[:smtp_server] || 'localhost'
        @smtp_port = options[:smtp_port] || 587
        @username = options[:username]
        @password = options[:password]
        @from_address = options[:from_address] || @username
        @use_tls = options.fetch(:use_tls, true)
        @max_recipients = options.fetch(:max_recipients, 10)
        setup_mail_configuration
      end

      def execute(**params)
        validate_params!(
          params,
          required: %i[to subject body],
          optional: %i[cc bcc reply_to attachments]
        )

        to_addresses = normalize_email_addresses(params[:to])
        cc_addresses = normalize_email_addresses(params[:cc]) if params[:cc]
        bcc_addresses = normalize_email_addresses(params[:bcc]) if params[:bcc]

        begin
          validate_email_params!(to_addresses, cc_addresses, bcc_addresses, params)
          result = send_email(to_addresses, cc_addresses, bcc_addresses, params)
          format_email_result(result, to_addresses)
        rescue StandardError => e
          "Email sending failed: #{e.message}"
        end
      end

      private

      def setup_mail_configuration
        Mail.defaults do
          delivery_method :smtp, {
            address: @smtp_server,
            port: @smtp_port,
            user_name: @username,
            password: @password,
            authentication: 'login',
            enable_starttls_auto: @use_tls
          }
        end
      end

      def normalize_email_addresses(addresses)
        case addresses
        when String
          addresses.split(/[,;]/).map(&:strip)
        when Array
          addresses.map(&:to_s).map(&:strip)
        else
          [addresses.to_s.strip]
        end
      end

      def validate_email_params!(to_addresses, cc_addresses, bcc_addresses, params)
        # Validate email addresses
        all_addresses = to_addresses + (cc_addresses || []) + (bcc_addresses || [])

        all_addresses.each do |address|
          raise ToolError, "Invalid email address: #{address}" unless valid_email?(address)
        end

        # Check recipient limits
        if all_addresses.length > @max_recipients
          raise ToolError, "Too many recipients: #{all_addresses.length} (max: #{@max_recipients})"
        end

        # Validate subject and body
        raise ToolError, 'Email subject cannot be empty' if params[:subject].to_s.strip.empty?

        raise ToolError, 'Email body cannot be empty' if params[:body].to_s.strip.empty?

        # Check for spam-like content
        validate_content_safety!(params[:subject], params[:body])
      end

      def valid_email?(address)
        address.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
      end

      def validate_content_safety!(subject, body)
        # Basic spam detection
        spam_indicators = [
          'viagra', 'casino', 'lottery', 'winner', 'congratulations',
          'million dollars', 'click here', 'urgent', 'act now'
        ]

        content = "#{subject} #{body}".downcase

        spam_indicators.each do |indicator|
          raise ToolError, "Potentially spam content detected: #{indicator}" if content.include?(indicator)
        end

        # Check for excessive caps
        caps_ratio = content.gsub(/[^A-Z]/, '').length.to_f / content.gsub(/[^A-Za-z]/, '').length
        return unless caps_ratio > 0.5 && content.length > 50

        raise ToolError, 'Excessive capitalization detected (possible spam)'
      end

      def send_email(to_addresses, cc_addresses, bcc_addresses, params)
        mail = Mail.new do
          from     @from_address
          to       to_addresses
          cc       cc_addresses if cc_addresses&.any?
          bcc      bcc_addresses if bcc_addresses&.any?
          subject  params[:subject]
          body     params[:body]

          reply_to params[:reply_to] if params[:reply_to]
        end

        # Add attachments if provided
        add_attachments(mail, params[:attachments]) if params[:attachments]

        # Send the email
        mail.deliver!

        {
          message_id: mail.message_id,
          to: to_addresses,
          cc: cc_addresses,
          bcc: bcc_addresses,
          subject: params[:subject],
          sent_at: Time.now,
          size: mail.to_s.bytesize
        }
      end

      def add_attachments(mail, attachments)
        attachment_list = case attachments
                          when String
                            [attachments]
                          when Array
                            attachments
                          else
                            [attachments.to_s]
                          end

        attachment_list.each do |attachment_path|
          raise ToolError, "Attachment file not found: #{attachment_path}" unless File.exist?(attachment_path)

          # Security check - only allow certain file types
          allowed_extensions = %w[.pdf .txt .doc .docx .xls .xlsx .jpg .png .gif .zip]
          extension = File.extname(attachment_path).downcase

          unless allowed_extensions.include?(extension)
            raise ToolError, "Attachment file type not allowed: #{extension}"
          end

          # Size check (max 10MB per attachment)
          if File.size(attachment_path) > 10_000_000
            raise ToolError, "Attachment too large: #{File.basename(attachment_path)} (max 10MB)"
          end

          mail.add_file(attachment_path)
        end
      end

      def format_email_result(result, to_addresses)
        output = []
        output << 'Email sent successfully!'
        output << "Message ID: #{result[:message_id]}"
        output << "Recipients: #{to_addresses.join(', ')}"
        output << "Subject: #{result[:subject]}"
        output << "Sent at: #{result[:sent_at].strftime('%Y-%m-%d %H:%M:%S')}"
        output << "Message size: #{result[:size]} bytes"

        output << "CC: #{result[:cc].join(', ')}" if result[:cc]&.any?

        output << "BCC: #{result[:bcc].length} recipients" if result[:bcc]&.any?

        output.join("\n")
      end
    end
  end
end
