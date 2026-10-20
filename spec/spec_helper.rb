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

module ResourceHelpers
  attr_reader :request

  def fixture(name)
    JSON.parse(File.read(File.join(__dir__, "fixtures", "sendcloud", name)))
  end

  def serve(method, path, status: 200, body: nil, headers: {}, content_type: "application/json")
    @stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.public_send(method, "/api/v3/#{path}") do |env|
        @request = env
        @sent_body = env.body
        [status, {"Content-Type" => content_type}.merge(headers), body.is_a?(String) ? body : body&.then { JSON.generate(_1) }]
      end
    end
    build_client(@stubs)
  end

  def offline_client
    build_client(Faraday::Adapter::Test::Stubs.new)
  end

  def sent_json
    JSON.parse(@sent_body)
  end
end

RSpec.configure do |config|
  config.include ClientHelpers
  config.include ResourceHelpers
  config.after { @stubs&.verify_stubbed_calls }
end
