# frozen_string_literal: true

module RCrewAI
  module Knowledge
    # A knowledge source yields plain text via #read. Concrete sources load from
    # strings, files, PDFs, CSVs, or URLs.
    class Source
      def read
        raise NotImplementedError, 'Subclasses must implement #read'
      end
    end

    class StringSource < Source
      def initialize(text)
        super()
        @text = text.to_s
      end

      def read
        @text
      end
    end

    class FileSource < Source
      def initialize(path)
        super()
        @path = path
      end

      def read
        File.read(@path)
      end
    end

    class PdfSource < Source
      def initialize(path)
        super()
        @path = path
      end

      def read
        require 'pdf-reader'
        reader = PDF::Reader.new(@path)
        reader.pages.map(&:text).join("\n")
      end
    end

    class CsvSource < Source
      def initialize(path)
        super()
        @path = path
      end

      def read
        require 'csv'
        CSV.read(@path).map { |row| row.join(', ') }.join("\n")
      end
    end

    class UrlSource < Source
      def initialize(url, fetcher: nil)
        super()
        @url = url
        @fetcher = fetcher
      end

      def read
        html = @fetcher ? @fetcher.call(@url) : fetch(@url)
        require 'nokogiri'
        doc = Nokogiri::HTML(html)
        doc.search('script, style').remove
        doc.text.gsub(/\s+/, ' ').strip
      end

      private

      def fetch(url)
        require 'faraday'
        Faraday.get(url).body
      end
    end
  end
end
