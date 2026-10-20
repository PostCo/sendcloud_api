# frozen_string_literal: true

require "uri"

module SendcloudAPI
  module Pagination
    NEXT_LINK = /<([^>]+)>\s*;\s*rel="?next"?/

    def self.next_cursor(response)
      url = response.headers["link"].to_s[NEXT_LINK, 1]
      url ||= response.body["next"] if response.body.is_a?(Hash)
      return unless url

      URI.decode_www_form(URI(url).query.to_s).to_h["cursor"]
    end
  end
end
