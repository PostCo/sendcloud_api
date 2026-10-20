# frozen_string_literal: true

require "uri"

module SendcloudAPI
  module Pagination
    LINK_VALUE = /<([^>]*)>([^<]*)/
    REL = /;\s*rel\s*=\s*(?:"([^"]*)"|([^\s;,]+))/i

    def self.next_params(response, params)
      url = next_link(response.headers["link"])
      url ||= response.body["next"] if response.body.is_a?(Hash)
      return unless url

      params.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }.merge(cursor: cursor(url, response))
    end

    def self.next_link(header)
      header.to_s.scan(LINK_VALUE).find do |_url, attributes|
        rel = attributes.match(REL)
        rel && (rel[1] || rel[2]).split.any? { |type| type.casecmp?("next") }
      end&.first
    end

    def self.cursor(url, response)
      cursors = URI.decode_www_form(URI(url).query.to_s).filter_map { |name, value| value if name == "cursor" }
      return cursors.first if cursors.size == 1 && !cursors.first.empty?

      raise ParseError.new("Sendcloud returned a next page URL without one cursor", response: response)
    rescue URI::InvalidURIError, ArgumentError
      raise ParseError.new("Sendcloud returned an invalid next page URL", response: response), cause: nil
    end
    private_class_method :next_link, :cursor
  end
end
