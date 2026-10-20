# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class Contracts < Base
      LIST_PARAMETERS = %i[carrier_code is_active client_id name country_code cursor page_size].freeze

      def list(**filters)
        get("contracts", params: filters, allowed: LIST_PARAMETERS)
      end

      def create(payload:)
        validate_payload!(payload, "carrier_code")
        connection.post("contracts", payload: payload)
      end

      def retrieve(id:)
        get("contracts/#{segment(:id, id)}")
      end

      def update(id:, payload:)
        validate_payload!(payload)
        connection.patch("contracts/#{segment(:id, id)}", payload: payload)
      end

      def delete(id:)
        connection.delete("contracts/#{segment(:id, id)}")
      end

      def schemas(carrier_code: nil)
        get("contracts/schemas", params: {carrier_code: carrier_code}, allowed: %i[carrier_code])
      end
    end
  end
end
