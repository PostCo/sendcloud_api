# frozen_string_literal: true

require "uri"

module SendcloudAPI
  class Redactor
    FILTERED = "[FILTERED]"
    SENSITIVE_KEY = /authorization|authentication|password|passwd|secret|token|cookie|apikey|publickey/i

    def initialize(secrets = [])
      @secrets = secrets.grep(String).reject(&:empty?).flat_map { |value| [value, URI.encode_www_form_component(value)] }
        .uniq.sort_by { |value| -value.bytesize }.map { |value| value.b.freeze }.freeze
    end

    def with_sensitive_values(value)
      self.class.new(@secrets + sensitive_values(value))
    end

    def filter(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), result|
          result[filter_string(key.to_s)] = sensitive_key?(key) ? FILTERED : filter(entry)
        end
      when Array
        value.map { |entry| filter(entry) }
      when String
        filter_string(value)
      else
        value
      end
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def sensitive_key?(key)
      key.to_s.gsub(/[^a-z0-9]/i, "").match?(SENSITIVE_KEY)
    end

    def sensitive_values(value)
      case value
      when Hash
        value.flat_map { |key, entry| sensitive_key?(key) ? strings_in(entry) : sensitive_values(entry) }
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

    def filter_string(value)
      filtered = @secrets.reduce(value.b) { |text, secret| text.gsub(secret, FILTERED) }
      filtered = filtered.gsub(%r{(https?://)[^\s/@]+:[^\s/@]+@}i, "\\1#{FILTERED}@")
      filtered = filtered.gsub(/\b(Bearer|Basic)\s+[^\s,"'<>]+/i, "\\1 #{FILTERED}")
      filtered = filtered.gsub(/([\w-]*(?:password|passwd|secret|token|authorization|api[-_]?key|public[-_]?key)[\w-]*["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&<>]+)/i, "\\1#{FILTERED}")
      filtered.force_encoding(value.encoding)
    end
  end
end
