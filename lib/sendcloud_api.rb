# frozen_string_literal: true

require_relative "sendcloud_api/version"
require_relative "sendcloud_api/errors"
require_relative "sendcloud_api/response"
require_relative "sendcloud_api/redactor"
require_relative "sendcloud_api/connection"
require_relative "sendcloud_api/pagination"
require_relative "sendcloud_api/webhook_signature"
require_relative "sendcloud_api/resources/base"
require_relative "sendcloud_api/resources/returns"
require_relative "sendcloud_api/resources/shipping_options"
require_relative "sendcloud_api/resources/parcel_documents"
require_relative "sendcloud_api/resources/parcel_tracking"
require_relative "sendcloud_api/resources/contracts"
require_relative "sendcloud_api/resources/integrations"
require_relative "sendcloud_api/resources/user"
require_relative "sendcloud_api/resources/invoice_items"
require_relative "sendcloud_api/client"

module SendcloudAPI
end
