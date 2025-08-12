# frozen_string_literal: true

require_relative 'base'
require 'faraday'
require 'nokogiri'
require 'uri'

module RCrewAI
  module Tools
    class WebSearch < Base
      def initialize(**options)
        super()
        @name = 'websearch'
        @description = 'Search the web for information using DuckDuckGo'
        @max_results = options.fetch(:max_results, 5)
        @timeout = options.fetch(:timeout, 30)
      end

      def execute(**params)
        validate_params!(params, required: [:query], optional: [:max_results])
        
        query = params[:query]
        max_results = params[:max_results] || @max_results
        
        begin
          search_results = perform_search(query, max_results)
          format_results(search_results)
        rescue => e
          "Search failed: #{e.message}"
        end
      end

      private

      def perform_search(query, max_results)
        # Use DuckDuckGo HTML search (no API key required)
        encoded_query = URI.encode_www_form_component(query)
        url = "https://html.duckduckgo.com/html/?q=#{encoded_query}"
        
        response = http_client.get(url, {}, headers)
        
        if response.success?
          parse_duckduckgo_results(response.body, max_results)
        else
          raise ToolError, "Search request failed with status: #{response.status}"
        end
      end

      def parse_duckduckgo_results(html, max_results)
        doc = Nokogiri::HTML(html)
        results = []

        # DuckDuckGo result selectors
        result_links = doc.css('.result__a')
        result_snippets = doc.css('.result__snippet')

        result_links.first(max_results).each_with_index do |link, index|
          title = link.text.strip
          url = link['href']
          snippet = result_snippets[index]&.text&.strip || ''

          # Clean up URL (DuckDuckGo sometimes wraps URLs)
          url = clean_duckduckgo_url(url) if url

          if title.present? && url.present?
            results << {
              title: title,
              url: url,
              snippet: snippet
            }
          end
        end

        results
      end

      def clean_duckduckgo_url(url)
        # DuckDuckGo sometimes prefixes URLs with their redirect
        if url.start_with?('/l/?')
          # Extract the actual URL from the redirect
          uri = URI.parse("https://duckduckgo.com#{url}")
          query_params = URI.decode_www_form(uri.query || '')
          actual_url = query_params.find { |k, v| k == 'uddg' }&.last
          return actual_url if actual_url
        end
        
        url
      end

      def format_results(results)
        if results.empty?
          return "No search results found."
        end

        formatted = "Search Results:\n\n"
        results.each_with_index do |result, index|
          formatted += "#{index + 1}. #{result[:title]}\n"
          formatted += "   URL: #{result[:url]}\n"
          formatted += "   #{result[:snippet]}\n\n" if result[:snippet].present?
        end

        formatted
      end

      def http_client
        @http_client ||= Faraday.new do |f|
          f.adapter Faraday.default_adapter
          f.options.timeout = @timeout
          f.options.open_timeout = 10
        end
      end

      def headers
        {
          'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.5',
          'Accept-Encoding' => 'gzip, deflate',
          'Connection' => 'keep-alive'
        }
      end
    end
  end
end

# Extension for String to check if present
class String
  def present?
    !empty?
  end
end