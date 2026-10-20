# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class InvoiceItems < Base
      LIST_PARAMETERS = %i[created_after created_before parcel_id invoice_id type cursor page_size].freeze

      def list(**filters)
        get("invoice-items", params: filters, allowed: LIST_PARAMETERS)
      end
    end
  end
end
