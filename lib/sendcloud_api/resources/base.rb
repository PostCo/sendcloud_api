# frozen_string_literal: true

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

      def get(path, params: {})
        connection.get(path, params: params.reject { |_, value| value.nil? })
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
