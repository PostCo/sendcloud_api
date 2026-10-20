# frozen_string_literal: true

RSpec.describe SendcloudAPI::Client do
  %i[public_key secret_key].each do |name|
    [nil, "", " ", 123, []].each do |value|
      it "rejects #{name} #{value.inspect} without exposing credentials" do
        options = {public_key: "test-public-key", secret_key: "test-secret-key"}.merge(name => value)
        expect { described_class.new(**options) }.to raise_error(ArgumentError, "#{name} must be a non-empty String")
      end
    end
  end

  it "uses Sendcloud v3 and the default timeouts" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/user/auth/metadata") do |env|
        expect(env.url.host).to eq("panel.sendcloud.sc")
        expect(env.request.open_timeout).to eq(5)
        expect(env.request.timeout).to eq(30)
        json_response({})
      end
    end
    client = described_class.new(public_key: "test-public-key", secret_key: "test-secret-key", adapter: [:test, stubs])
    expect(client.connection.get("user/auth/metadata")).to be_success
    stubs.verify_stubbed_calls
  end

  it "accepts a base URL without a trailing slash and custom timeouts" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/custom/user/auth/metadata") do |env|
        expect(env.url.host).to eq("example.test")
        expect(env.request.open_timeout).to eq(2)
        expect(env.request.timeout).to eq(8)
        json_response({})
      end
    end
    client = described_class.new(public_key: "test-public-key", secret_key: "test-secret-key",
      base_url: "https://example.test/custom", open_timeout: 2, timeout: 8, adapter: [:test, stubs])
    expect(client.connection.get("user/auth/metadata")).to be_success
    stubs.verify_stubbed_calls
  end

  it "lets resource subclasses share the connection and retain false filters" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test?enabled=false") { json_response({"data" => []}) }
    end
    resource_class = Class.new(SendcloudAPI::Resources::Base) do
      def list(**params)
        get("test", params: params)
      end

      def create(payload:)
        validate_payload!(payload, "id")
        connection.post("test", payload: payload)
      end
    end
    resource = resource_class.new(build_client(stubs).connection)
    expect(resource.list(enabled: false, cursor: nil).body).to eq("data" => [])
    expect { resource.create(payload: {id: "1"}) }.to raise_error(ArgumentError, /String keys/)
    expect { resource.create(payload: {"id" => " "}) }.to raise_error(ArgumentError, "id is required")
    stubs.verify_stubbed_calls
  end
end
