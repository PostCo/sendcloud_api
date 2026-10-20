# frozen_string_literal: true

module SendcloudAPI
  module Resources
    class User < Base
      def auth_metadata
        get("user/auth/metadata")
      end
    end
  end
end
