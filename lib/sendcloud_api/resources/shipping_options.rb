# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class ShippingOptions < Base
      def search(payload:)
        validate_payload!(payload)
        connection.post("shipping-options", payload: payload, read_only: true)
      end
    end
  end
end
