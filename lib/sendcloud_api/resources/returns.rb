# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class Returns < Base
      LIST_PARAMETERS = %i[cursor page_size from_date to_date parent_parcel_status].freeze

      def create(payload:)
        validate_payload!(payload)
        connection.post("returns", payload: payload)
      end

      def validate(payload:)
        validate_payload!(payload)
        connection.post("returns/validate", payload: payload, read_only: true)
      end

      def retrieve(id:)
        get("returns/#{segment(:id, id)}")
      end

      def list(**filters)
        get("returns", params: filters, allowed: LIST_PARAMETERS)
      end

      def cancel(id:)
        connection.patch("returns/#{segment(:id, id)}/cancel", payload: {})
      end
    end
  end
end
