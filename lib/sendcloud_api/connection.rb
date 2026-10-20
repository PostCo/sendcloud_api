# frozen_string_literal: true

require "faraday"
require "json"
require "zlib"

module SendcloudAPI
  class Connection
    JSON_MEDIA_TYPE = "application/json"
    ERROR_DETAILS_LIMIT = 1_000
    NOT_RELATIVE_PATH = %r{\A(?:/|[a-z][a-z0-9+.-]*:)}i
    ERROR_CLASSES = {
      400 => BadRequestError,
      401 => AuthenticationError,
      403 => ForbiddenError,
      404 => NotFoundError,
      405 => MethodNotAllowedError,
      409 => ConflictError,
      422 => UnprocessableEntityError,
      429 => RateLimitError
    }.freeze

    def initialize(public_key:, secret_key:, base_url:, open_timeout:, timeout:, adapter:)
      authorization = Faraday::Utils.basic_header_from(public_key, secret_key)
      @redactor = Redactor.new([public_key, secret_key, authorization, authorization.delete_prefix("Basic ")])
      @http = Faraday.new(url: normalize_base_url(base_url)) do |connection|
        connection.headers["Content-Type"] = JSON_MEDIA_TYPE
        connection.headers["User-Agent"] = "sendcloud_api/#{VERSION}"
        connection.headers["Authorization"] = authorization
        connection.options.open_timeout = open_timeout
        connection.options.timeout = timeout
        connection.adapter(*Array(adapter))
      end
    rescue URI::InvalidURIError
      raise ArgumentError, "base_url is not a valid URL", cause: nil
    end

    def get(path, params: {}, accept: JSON_MEDIA_TYPE)
      request(:get, path, params: params, accept: accept)
    end

    def post(path, payload:, read_only: false)
      request(:post, path, payload: payload, write: !read_only)
    end

    def put(path, payload:)
      request(:put, path, payload: payload)
    end

    def patch(path, payload:)
      request(:patch, path, payload: payload)
    end

    def delete(path, params: {})
      request(:delete, path, params: params)
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def normalize_base_url(base_url)
      base_url.end_with?("/") ? base_url : "#{base_url}/"
    end

    def request(method, path, params: {}, payload: nil, accept: JSON_MEDIA_TYPE, write: method != :get)
      raise ArgumentError, "path must be relative to the base URL, without a scheme or leading slash" if path.match?(NOT_RELATIVE_PATH)

      body = serialize(payload) unless payload.nil?
      redactor = @redactor.with_sensitive_values([payload, params])
      context = {request_method: method, request_path: redactor.filter_text(path.split("?").first)}

      raw_response = dispatch(method, path, body, params, accept, context, write: write)
      status = raw_response.status
      success = (200..299).cover?(status)
      headers = raw_response.headers.to_h.transform_keys { |key| key.to_s.downcase }
      kind, body, problem = decode(success, raw_response.body, media_type(headers["content-type"]), accept.downcase)
      problem ||= "Sendcloud returned empty JSON" if write && body.nil? && status != 204
      redactor = redactor.with_sensitive_values([headers, body])
      redactor = redactor.anywhere if problem || !success
      body = redactor.filter(body) if kind == :json
      body = redactor.filter_text(body) if kind == :text
      response = Response.new(status: status, headers: redactor.filter(headers), body: body)

      raise_for_status!(response, redactor, context, write: write)
      raise ParseError.new(redactor.filter_text(problem), response: response, ambiguous: write, **context), cause: nil if problem

      response
    end

    def serialize(payload)
      JSON.generate(payload)
    rescue JSON::GeneratorError => error
      raise error.class, @redactor.with_sensitive_values(payload).filter_text(error.message), cause: nil
    end

    def dispatch(method, path, body, params, accept, context, write:)
      @http.run_request(method, path, body, {"Accept" => accept}) do |request|
        request.params.update(params)
      end
    rescue URI::InvalidURIError
      raise ArgumentError, "path is not a valid URL path", cause: nil
    rescue Faraday::Error, Zlib::Error => error
      raise TransportError.new("Sendcloud transport failed (#{error.class})", ambiguous: write, **context), cause: nil
    end

    def media_type(content_type)
      content_type.to_s.split(";").first.to_s.strip.downcase
    end

    def json_type?(media_type)
      media_type == JSON_MEDIA_TYPE || media_type.end_with?("+json")
    end

    def decode(success, body, media_type, accept)
      return decode_document(body, media_type, accept) if success && !json_type?(accept)
      return [:json, nil, nil] if body.nil? || body.empty?
      return parse_json(body) if media_type.empty? || json_type?(media_type)

      [:text, body.b, ("Sendcloud returned #{media_type_name(media_type)} instead of JSON" if success)]
    end

    def decode_document(body, media_type, accept)
      return [:document, nil, "Sendcloud returned an empty body instead of #{accept}"] if body.nil? || body.empty?
      return [:document, body.b, nil] if media_type == accept

      [:text, body.b, "Sendcloud returned #{media_type_name(media_type)} instead of #{accept}"]
    end

    def media_type_name(media_type)
      media_type.empty? ? "no content type" : media_type
    end

    def parse_json(body)
      text = body.dup.force_encoding(Encoding::UTF_8)
      return [:text, text.scrub, "Sendcloud returned invalid JSON"] unless text.valid_encoding?

      parsed = JSON.parse(text)
      valid_utf8?(parsed) ? [:json, parsed, nil] : [:text, Redactor::FILTERED, "Sendcloud returned invalid JSON"]
    rescue JSON::ParserError
      [:text, text, "Sendcloud returned invalid JSON"]
    end

    def valid_utf8?(value)
      case value
      when Hash
        value.all? { |key, entry| valid_utf8?(key) && valid_utf8?(entry) }
      when Array
        value.all? { |entry| valid_utf8?(entry) }
      when String
        value.valid_encoding?
      else
        true
      end
    end

    def raise_for_status!(response, redactor, context, write:)
      return if response.success?

      error_class = ERROR_CLASSES.fetch(response.status) { (500..599).cover?(response.status) ? ServerError : Error }
      message = "Sendcloud request failed with HTTP #{response.status}"
      details = error_details(response.body, response.status)
      message += ": #{truncate(redactor.filter_text(details))}" if details
      raise error_class.new(message, response: response,
        ambiguous: write && (500..599).cover?(response.status), **context), cause: nil
    end

    def error_details(body, status)
      return unless body.is_a?(Hash) && body["errors"].is_a?(Array)

      details = body["errors"].filter_map do |error|
        next unless error.is_a?(Hash)

        error = error.except("code") if error["code"].to_s == status.to_s
        error.values_at("code", "field", "message", "title", "detail", "source")
          .compact.map { |value| value.is_a?(String) ? value : JSON.generate(value) }.join(" ")
      end.reject(&:empty?)
      details.join("; ") unless details.empty?
    end

    def truncate(details)
      (details.length > ERROR_DETAILS_LIMIT) ? "#{details[0, ERROR_DETAILS_LIMIT]}..." : details
    end
  end
end
