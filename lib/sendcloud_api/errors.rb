# frozen_string_literal: true

module SendcloudAPI
  class Error < StandardError
    attr_reader :response, :request_method, :request_path

    def initialize(message = nil, response: nil, ambiguous: false, request_method: nil, request_path: nil)
      @response = response
      @ambiguous = ambiguous
      @request_method = request_method
      @request_path = request_path
      super(message)
    end

    def ambiguous?
      @ambiguous
    end

    def status
      response&.status
    end

    def headers
      response&.headers
    end

    def body
      response&.body
    end

    def raw_body
      response&.raw_body
    end

    def retry_after
      headers&.fetch("retry-after", nil)
    end
  end

  class BadRequestError < Error; end
  class AuthenticationError < Error; end
  class ForbiddenError < Error; end
  class NotFoundError < Error; end
  class MethodNotAllowedError < Error; end
  class ConflictError < Error; end
  class UnprocessableEntityError < Error; end
  class RateLimitError < Error; end
  class ServerError < Error; end
  class TransportError < Error; end
  class ParseError < Error; end
end
