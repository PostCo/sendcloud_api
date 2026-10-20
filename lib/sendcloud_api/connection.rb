# frozen_string_literal: true

require "faraday"
require "json"
require "zlib"

module SendcloudAPI
  class Connection
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
        connection.headers["Accept"] = "application/json"
        connection.headers["Content-Type"] = "application/json"
        connection.headers["User-Agent"] = "sendcloud_api/#{VERSION}"
        connection.headers["Authorization"] = authorization
        connection.options.open_timeout = open_timeout
        connection.options.timeout = timeout
        connection.adapter(*Array(adapter))
      end
    end

    def get(path, params: {})
      request(:get, path, params: params)
    end

    def post(path, payload:)
      request(:post, path, payload: payload)
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

    def request(method, path, params: {}, payload: nil)
      body = serialize(payload) unless payload.nil?
      redactor = @redactor.with_sensitive_values([payload, params])
      context = {request_method: method, request_path: redactor.filter(path.split("?").first)}
      write = method != :get

      raw_response = dispatch(method, path, body, params, context, write: write)
      headers = raw_response.headers.to_h.transform_keys { |key| key.to_s.downcase }
      parsed_body, valid_json = parse_body(raw_response.body, headers)
      values = {"headers" => headers, "body" => parsed_body}
      redactor = redactor.with_sensitive_values(values)
      sanitized = redactor.filter(values)
      response = Response.new(status: raw_response.status, headers: sanitized.fetch("headers"),
        body: sanitized.fetch("body"), raw_body: redactor.filter(raw_response.body))

      raise_for_status!(response, context, write: write)
      if response.status != 204 && (!valid_json || (write && parsed_body.nil?))
        raise ParseError.new("Sendcloud returned invalid or empty JSON", response: response, ambiguous: write, **context), cause: nil
      end

      response
    end

    def serialize(payload)
      JSON.generate(payload)
    rescue JSON::GeneratorError => error
      raise error.class, @redactor.with_sensitive_values(payload).filter(error.message), cause: nil
    end

    def dispatch(method, path, body, params, context, write:)
      @http.run_request(method, path, body, nil) do |request|
        request.params.update(params)
      end
    rescue Faraday::Error, Zlib::Error => error
      raise TransportError.new("Sendcloud transport failed (#{error.class})", ambiguous: write, **context), cause: nil
    end

    def parse_body(body, headers)
      return [nil, true] if body.nil? || body.empty?

      content_type = headers["content-type"].to_s.split(";").first.to_s.downcase
      return [body.b, true] unless content_type.empty? || content_type == "application/json" || content_type.end_with?("+json")

      body = body.dup.force_encoding(Encoding::UTF_8)
      return [body.scrub, false] unless body.valid_encoding?

      parsed = JSON.parse(body)
      valid_utf8?(parsed) ? [parsed, true] : [Redactor::FILTERED, false]
    rescue JSON::ParserError
      [body, false]
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

    def raise_for_status!(response, context, write:)
      return if response.success?

      error_class = ERROR_CLASSES.fetch(response.status) { (500..599).cover?(response.status) ? ServerError : Error }
      message = ["Sendcloud request failed with HTTP #{response.status}", error_details(response.body)].compact.join(": ")
      raise error_class.new(message, response: response,
        ambiguous: write && (500..599).cover?(response.status), **context), cause: nil
    end

    def error_details(body)
      return unless body.is_a?(Hash) && body["errors"].is_a?(Array)

      details = body["errors"].filter_map do |error|
        next unless error.is_a?(Hash)

        error.values_at("code", "field", "message", "status", "title", "detail", "source")
          .compact.map { |value| value.is_a?(String) ? value : JSON.generate(value) }.join(" ")
      end.reject(&:empty?)
      details.join("; ") unless details.empty?
    end
  end
end
