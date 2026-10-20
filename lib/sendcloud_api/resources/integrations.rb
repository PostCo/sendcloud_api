# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class Integrations < Base
      def retrieve(id:)
        get("integrations/#{segment(:id, id)}")
      end

      def update(id:, payload:)
        validate_payload!(payload)
        connection.patch("integrations/#{segment(:id, id)}", payload: payload)
      end
    end
  end
end
