# frozen_string_literal: true

module SendcloudAPI
  class Response
    attr_reader :status, :headers, :body, :raw_body

    def initialize(status:, headers:, body:, raw_body:)
      @status = status
      @headers = headers.freeze
      @body = body
      @raw_body = raw_body
      freeze
    end

    def content_type
      headers["content-type"]
    end

    def success?
      (200..299).cover?(status)
    end

    def no_content?
      status == 204 || body.nil?
    end

    def inspect
      "#<#{self.class} status=#{status}>"
    end
  end
end
