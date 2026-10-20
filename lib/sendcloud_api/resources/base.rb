# frozen_string_literal: true

require "uri"

module SendcloudAPI
  module Resources
    class Base
      attr_reader :connection

      def initialize(connection)
        @connection = connection
      end

      def inspect
        "#<#{self.class}>"
      end

      private

      def get(path, params: {}, allowed: [], accept: Connection::JSON_MEDIA_TYPE)
        params = params.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
        unknown = params.keys - allowed
        raise ArgumentError, "Unknown parameters: #{unknown.map(&:to_s).sort.join(", ")}" unless unknown.empty?

        connection.get(path, params: params.compact, accept: accept)
      end

      def segment(name, value)
        require_parameter!(name, value)
        raise ArgumentError, "#{name} cannot be . or .." if %w[. ..].include?(value.to_s)

        URI.encode_www_form_component(value.to_s).gsub("+", "%20")
      end

      def validate_payload!(payload, *identifiers)
        unless payload.is_a?(Hash) && payload.keys.all? { |key| key.is_a?(String) }
          raise ArgumentError, "payload must be a Hash with Sendcloud JSON field names as String keys"
        end

        identifiers.each { |name| require_parameter!(name, payload[name]) }
      end

      def require_parameter!(name, value)
        missing = value.nil? || (value.is_a?(String) ? value.strip.empty? : value.respond_to?(:empty?) && value.empty?)
        return unless missing

        raise ArgumentError, "#{name} is required"
      end
    end
  end
end
