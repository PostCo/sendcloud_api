# frozen_string_literal: true

RSpec.describe "Sendcloud credential redaction" do
  let(:public_key) { "test-public-key" }
  let(:secret_key) { "test-secret-key" }
  let(:authorization) { "Basic dGVzdC1wdWJsaWMta2V5OnRlc3Qtc2VjcmV0LWtleQ==" }

  def expect_redacted(*values)
    values.each do |value|
      [public_key, secret_key, authorization, authorization.delete_prefix("Basic ")].each do |credential|
        expect(value.to_s).not_to include(credential)
        expect(value.inspect).not_to include(credential)
      end
    end
  end

  [200, 400, 401, 403, 404, 405, 409, 422, 429, 500, 503].each do |status|
    it "removes credentials from HTTP #{status} JSON, headers, messages and inspection" do
      body = {"echo" => "#{public_key} #{secret_key} #{authorization}", "errors" => [{"message" => "#{secret_key} rejected"}],
              "public_key" => public_key, "secret_key" => secret_key, "Authorization" => authorization,
              "nested" => [{"password" => "another-password", "echo" => "another-password"}], secret_key => secret_key}
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/test") do
          json_response(body, status: status, headers: {"Authorization" => authorization, "X-Echo" => "#{public_key} #{secret_key}"})
        end
      end
      client = build_client(stubs)
      begin
        response = client.connection.get("test?token=private-query")
      rescue SendcloudAPI::Error => error
        expect_redacted(error, error.message, error.full_message, error.body, error.headers, error.raw_body)
        expect(error.cause).to be_nil
        response = error.response
      end
      expect_redacted(client, client.connection, SendcloudAPI::Resources::Base.new(client.connection), response, response.body, response.headers, response.raw_body)
      expect(response.body["nested"].first).to eq("password" => "[FILTERED]", "echo" => "[FILTERED]")
      expect(body["secret_key"]).to eq(secret_key)
    end
  end

  [200, 401, 503].each do |status|
    it "filters malformed JSON at HTTP #{status}" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/api/v3/test") { [status, {"Content-Type" => "application/json"}, "#{public_key} #{secret_key} #{authorization}\xFF".b] }
      end
      expect { build_client(stubs).connection.post("test", payload: {}) }.to raise_error(SendcloudAPI::Error) { |error|
        expect_redacted(error, error.message, error.body, error.raw_body, error.response)
      }
    end
  end

  it "redacts credentials from binary responses without decoding the bytes" do
    bytes = "\x89PNG\xFF#{secret_key}\x00#{public_key}".b
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test") { [200, {"Content-Type" => "image/png"}, bytes] }
    end
    response = build_client(stubs).connection.get("test")
    expect(response.body).to eq("\x89PNG\xFF[FILTERED]\x00[FILTERED]".b)
    expect_redacted(response.body, response.raw_body, response)
    expect(bytes).to include(secret_key)
  end

  it "learns submitted credentials without changing the outbound payload" do
    payload = {"password" => "carrier-private-password", "public_key" => "carrier-public-key", "enabled" => false}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v3/test") do |env|
        expect(JSON.parse(env.body)).to eq(payload)
        json_response({"errors" => [{"message" => "carrier-private-password carrier-public-key"}]}, status: 422)
      end
    end
    expect { build_client(stubs).connection.post("test", payload: payload) }.to raise_error(SendcloudAPI::UnprocessableEntityError) { |error|
      expect([error.message, error.body, error.raw_body].inspect).not_to include("carrier-private-password", "carrier-public-key")
    }
    expect(payload["password"]).to eq("carrier-private-password")
  end

  it "suppresses the authenticated transport exception and query parameters" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test-public-key/test-secret-key") do
        raise Faraday::TimeoutError, "#{authorization} #{secret_key}"
      end
    end
    expect { build_client(stubs).connection.get("#{public_key}/#{secret_key}?token=private-query") }.to raise_error(SendcloudAPI::TransportError) { |error|
      expect_redacted(error, error.message, error.full_message, error.request_path)
      expect(error.request_path).to eq("[FILTERED]/[FILTERED]")
      expect(error.request_path).not_to include("private-query")
      expect(error.cause).to be_nil
    }
  end

  it "filters encoded credentials and arbitrary authorization text" do
    redactor = SendcloudAPI::Redactor.new(["private/key+value"])
    value = {"echo" => "private%2Fkey%2Bvalue Basic unknown-token", "aUtHoRiZaTiOn" => "Basic other-token"}
    expect(redactor.filter(value)).to eq("echo" => "[FILTERED] Basic [FILTERED]", "aUtHoRiZaTiOn" => "[FILTERED]")
    expect(redactor.inspect).to eq("#<SendcloudAPI::Redactor>")
  end
end
