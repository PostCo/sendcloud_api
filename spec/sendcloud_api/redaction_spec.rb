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

  def stub_response(method, *response)
    Faraday::Adapter::Test::Stubs.new do |stub|
      stub.public_send(method, "/api/v3/test") { response }
    end
  end

  [200, 400, 401, 403, 404, 405, 409, 422, 429, 500, 503].each do |status|
    it "removes credentials from HTTP #{status} JSON, headers, messages and inspection" do
      body = {"echo" => "#{public_key} #{secret_key} #{authorization}", "errors" => [{"message" => "#{secret_key} rejected"}],
              "public_key" => public_key, "secret_key" => secret_key, "Authorization" => authorization,
              "nested" => [{"password" => "another-password", "echo" => "another-password"}]}
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/test") do
          json_response(body, status: status, headers: {"Authorization" => authorization, "X-Echo" => "#{public_key} #{secret_key}"})
        end
      end
      client = build_client(stubs)
      begin
        response = client.connection.get("test?token=private-query")
      rescue SendcloudAPI::Error => error
        expect_redacted(error, error.message, error.full_message, error.body, error.headers)
        expect(error.cause).to be_nil
        response = error.response
      end
      expect_redacted(client, client.connection, SendcloudAPI::Resources::Base.new(client.connection), response, response.body, response.headers)
      expect(response.body["nested"].first).to eq("password" => "[FILTERED]", "echo" => "[FILTERED]")
      expect(body["secret_key"]).to eq(secret_key)
    end
  end

  [200, 401, 503].each do |status|
    it "filters malformed JSON at HTTP #{status}" do
      stubs = stub_response(:post, status, {"Content-Type" => "application/json"}, "#{public_key} #{secret_key} #{authorization}\xFF".b)
      expect { build_client(stubs).connection.post("test", payload: {}) }.to raise_error(SendcloudAPI::Error) { |error|
        expect_redacted(error, error.message, error.body, error.response)
      }
    end
  end

  it "keeps an escaped echo of a submitted credential out of the error" do
    stubs = stub_response(:post, 422, {"Content-Type" => "application/json"}, '{"errors":[{"message":"bad value p\\u00e4ss\\"w0rd"}]}')
    expect { build_client(stubs).connection.post("test", payload: {"password" => "päss\"w0rd"}) }.to raise_error(SendcloudAPI::UnprocessableEntityError) { |error|
      expect(error.message).to eq("Sendcloud request failed with HTTP 422: bad value [FILTERED]")
      expect(error.body).to eq("errors" => [{"message" => "bad value [FILTERED]"}])
      expect(error).not_to respond_to(:raw_body)
      expect(error.response).not_to respond_to(:raw_body)
    }
  end

  it "returns accepted document bytes unchanged" do
    bytes = "\x89PNG\xFF Basic Service token=label #{secret_key}\x00".b
    response = build_client(stub_response(:get, 200, {"Content-Type" => "image/png"}, bytes)).connection.get("test", accept: "image/png")
    expect(response.body).to eq(bytes)
    expect(response.inspect).not_to include(secret_key)
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
      expect([error.message, error.body].inspect).not_to include("carrier-private-password", "carrier-public-key")
    }
    expect(payload["password"]).to eq("carrier-private-password")
  end

  %w[body headers].each do |credential|
    it "keeps a 503 write ambiguous when a credential equals #{credential.inspect}" do
      stubs = stub_response(:post, 503, {"Content-Type" => "application/json"}, JSON.generate({"errors" => [], credential => credential}))
      expect { build_client(stubs).connection.post("test", payload: {"secret" => credential}) }.to raise_error(SendcloudAPI::ServerError) { |error|
        expect(error).to be_ambiguous
        expect(error.body).to eq("errors" => [], credential => "[FILTERED]")
      }
    end
  end

  it "keeps field names and identifiers that contain short learned credentials" do
    body = {"ab" => "AB", "data" => {"ab_id" => 3, "tracking_number" => "3SABCD1234", "name" => "Jo", "reference" => "1234"},
            "echo" => "rejected carrier-long-secret"}
    stubs = stub_response(:post, 201, {"Content-Type" => "application/json"}, JSON.generate(body))
    payload = {"carrier" => {"api_key" => "1234", "password" => "AB", "secret" => "carrier-long-secret"}}
    expect(build_client(stubs).connection.post("test", payload: payload).body).to eq(
      "ab" => "[FILTERED]", "data" => {"ab_id" => 3, "tracking_number" => "3SABCD1234", "name" => "Jo", "reference" => "[FILTERED]"},
      "echo" => "rejected [FILTERED]"
    )
  end

  {
    "a JSON rejection" => [400, "application/json", SendcloudAPI::BadRequestError],
    "a text rejection" => [503, "text/plain", SendcloudAPI::ServerError],
    "an unexpected success format" => [200, "text/html", SendcloudAPI::ParseError]
  }.each do |source, (status, content_type, error_class)|
    it "removes a short learned credential anywhere in #{source}" do
      text = "Login with hunter2 was refused"
      body = (content_type == "application/json") ? JSON.generate({"errors" => [{"code" => "invalid", "field" => "contract_data", "message" => text}]}) : text
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/api/v3/hunter2/contracts") { [status, {"Content-Type" => content_type, "X-Echo" => text}, body] }
      end
      expect { build_client(stubs).connection.post("hunter2/contracts", payload: {"contract_data" => {"password" => "hunter2"}}) }.to raise_error(error_class) { |error|
        expect([error.message, error.body, error.headers, error.request_path].inspect).not_to include("hunter2")
        expect(error.headers["x-echo"]).to eq("Login with [FILTERED] was refused")
      }
    end
  end

  it "keeps the error text around a removed short credential" do
    stubs = stub_response(:post, 400, {"Content-Type" => "application/json"},
      JSON.generate({"errors" => [{"code" => "invalid", "field" => "contract_data", "message" => "Login with hunter2 was refused"}]}))
    expect { build_client(stubs).connection.post("test", payload: {"password" => "hunter2"}) }.to raise_error(
      SendcloudAPI::BadRequestError, "Sendcloud request failed with HTTP 400: invalid contract_data Login with [FILTERED] was refused"
    ) { |error|
      expect(error.body).to eq("errors" => [{"code" => "invalid", "field" => "contract_data", "message" => "Login with [FILTERED] was refused"}])
    }
  end

  it "leaves free text in successful JSON alone" do
    body = {"name" => "Basic Letter", "address_2" => "Bearer Lane 4", "note" => "secret: none, door code 1",
            "tracking_url" => "https://t.example/track?id=1&X-Amz-Security-Token=abc&sig=2", "link" => "https://user:pass@t.example/"}
    response = build_client(stub_response(:get, 200, {"Content-Type" => "application/json"}, JSON.generate(body))).connection.get("test")
    expect(response.body).to eq(body)
  end

  it "filters credential text in non-JSON error bodies and messages" do
    text = "Bearer abc token=def https://user:pass@t.example/ Authentication: ghi Cookie=jkl api-key: mno"
    stubs = stub_response(:get, 503, {"Content-Type" => "text/plain"}, text)
    expect { build_client(stubs).connection.get("test") }.to raise_error(SendcloudAPI::ServerError) { |error|
      expect(error.body).to eq("Bearer [FILTERED] token=[FILTERED] https://[FILTERED]@t.example/ Authentication: [FILTERED] Cookie=[FILTERED] api-key: [FILTERED]")
    }
  end

  it "filters credential text in error messages built from JSON" do
    stubs = stub_response(:get, 400, {"Content-Type" => "application/json"}, JSON.generate({"errors" => [{"detail" => "Basic abc rejected, cookie: def"}]}))
    expect { build_client(stubs).connection.get("test") }.to raise_error(SendcloudAPI::BadRequestError, "Sendcloud request failed with HTTP 400: Basic [FILTERED] rejected, cookie: [FILTERED]")
  end

  it "uses one credential-name pattern for JSON fields and free text" do
    names = %w[Authorization authentication password passwd client_secret access_token Set-Cookie api_key public-key]
    redactor = SendcloudAPI::Redactor.new
    expect(redactor.filter(names.to_h { |name| [name, "value"] }).values.uniq).to eq(["[FILTERED]"])
    names.each { |name| expect(redactor.filter_text("#{name}: value")).to eq("#{name}: [FILTERED]") }
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

  it "filters encoded credentials" do
    redactor = SendcloudAPI::Redactor.new(["private/key+value"])
    expect(redactor.filter("echo" => "echo private%2Fkey%2Bvalue")).to eq("echo" => "echo [FILTERED]")
    expect(redactor.inspect).to eq("#<SendcloudAPI::Redactor>")
  end
end
