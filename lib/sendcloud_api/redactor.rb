# frozen_string_literal: true

require "uri"

module SendcloudAPI
  class Redactor
    FILTERED = "[FILTERED]"
    CREDENTIAL_NAME = /authorization|authentication|password|passwd|secret|token|cookie|api[-_]?key|public[-_]?key/i
    CREDENTIAL_ASSIGNMENT = /([\w-]*(?:#{CREDENTIAL_NAME.source})[\w-]*["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&<>]+)/i
    MINIMUM_EMBEDDED_BYTES = 8

    def initialize(secrets = [])
      @secrets = secrets.grep(String).reject(&:empty?).uniq.freeze
      variants = @secrets.flat_map { |value| [value, URI.encode_www_form_component(value)] }.uniq.map { |value| value.b.freeze }
      embedded, whole = variants.partition { |value| value.bytesize >= MINIMUM_EMBEDDED_BYTES }
      @embedded = embedded.sort_by { |value| -value.bytesize }.freeze
      @whole = whole.freeze
    end

    def with_sensitive_values(value)
      self.class.new(@secrets + sensitive_values(value))
    end

    def filter(value)
      case value
      when Hash
        value.to_h { |key, entry| [key, credential_name?(key) ? FILTERED : filter(entry)] }
      when Array
        value.map { |entry| filter(entry) }
      when String
        filter_secrets(value)
      else
        value
      end
    end

    def filter_text(value)
      filtered = filter_secrets(value).b
      filtered = filtered.gsub(%r{(https?://)[^\s/@]+:[^\s/@]+@}i, "\\1#{FILTERED}@")
      filtered = filtered.gsub(/\b(Bearer|Basic)\s+[^\s,"'<>]+/i, "\\1 #{FILTERED}")
      filtered.gsub(CREDENTIAL_ASSIGNMENT, "\\1#{FILTERED}").force_encoding(value.encoding)
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def credential_name?(key)
      key.to_s.gsub(/[^a-z0-9]/i, "").match?(CREDENTIAL_NAME)
    end

    def filter_secrets(value)
      bytes = value.b
      return FILTERED.dup.force_encoding(value.encoding) if @whole.include?(bytes)

      @embedded.reduce(bytes) { |text, secret| text.gsub(secret, FILTERED) }.force_encoding(value.encoding)
    end

    def sensitive_values(value)
      case value
      when Hash
        value.flat_map { |key, entry| credential_name?(key) ? strings_in(entry) : sensitive_values(entry) }
      when Array
        value.flat_map { |entry| sensitive_values(entry) }
      else
        []
      end
    end

    def strings_in(value)
      case value
      when Hash then value.values.flat_map { |entry| strings_in(entry) }
      when Array then value.flat_map { |entry| strings_in(entry) }
      when String then [value, value.sub(/\A(?:Bearer|Basic)\s+/i, "")]
      else []
      end
    end
  end
end
