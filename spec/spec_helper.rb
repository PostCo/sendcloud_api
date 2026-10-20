# frozen_string_literal: true

require "sendcloud_api"
require "faraday/adapter/test"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

module ClientHelpers
  TEST_BASE_URL = "https://example.test/api/v3/"

  def build_client(stubs)
    SendcloudAPI::Client.new(
      public_key: "test-public-key",
      secret_key: "test-secret-key",
      base_url: TEST_BASE_URL,
      adapter: [:test, stubs]
    )
  end

  def json_response(body, status: 200, headers: {})
    [status, {"Content-Type" => "application/json"}.merge(headers), JSON.generate(body)]
  end
end

RSpec.configure do |config|
  config.include ClientHelpers
end
