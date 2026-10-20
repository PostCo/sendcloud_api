# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class ParcelTracking < Base
      def retrieve(tracking_number:)
        get("parcels/tracking/#{segment(:tracking_number, tracking_number)}")
      end
    end
  end
end
