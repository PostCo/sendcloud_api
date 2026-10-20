# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class ParcelDocuments < Base
      FORMATS = {pdf: "application/pdf", png: "image/png", zpl: "application/zpl"}.freeze
      PARAMETERS = %i[dpi paper_size].freeze

      def retrieve(parcel_id:, type:, format:, **options)
        accept = FORMATS.fetch(format) { raise ArgumentError, "format must be one of: #{FORMATS.keys.join(", ")}" }
        path = "parcels/#{segment(:parcel_id, parcel_id)}/documents/#{segment(:type, type)}"
        get(path, params: options, allowed: PARAMETERS, accept: accept)
      end
    end
  end
end
