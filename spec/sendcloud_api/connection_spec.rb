# frozen_string_literal: true

RSpec.describe SendcloudAPI::Connection do
  def fixture(name)
    File.read(File.expand_path("../fixtures/sendcloud/#{name}", __dir__))
  end

  it "accepts an empty path at the configured base URL" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/") { json_response({"data" => []}) }
    end
    expect(build_client(stubs).connection.get("").status).to eq(200)
    stubs.verify_stubbed_calls
  end

  it "sends basic authentication and JSON headers" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/user/auth/metadata?active=false&limit=10") do |env|
        expect(env.request_headers["Authorization"]).to eq("Basic dGVzdC1wdWJsaWMta2V5OnRlc3Qtc2VjcmV0LWtleQ==")
        expect(env.request_headers["Accept"]).to eq("application/json")
        expect(env.request_headers["Content-Type"]).to eq("application/json")
        expect(env.request_headers["User-Agent"]).to eq("sendcloud_api/#{SendcloudAPI::VERSION}")
        json_response({"data" => {"id" => 637034}}, headers: {"X-Request-ID" => "request-1"})
      end
    end
    result = build_client(stubs).connection.get("user/auth/metadata", params: {"active" => false, "limit" => 10})
    expect(result).to be_success
    expect(result).not_to be_no_content
    expect(result.status).to eq(200)
    expect(result.body).to eq("data" => {"id" => 637034})
    expect(result.headers["x-request-id"]).to eq("request-1")
    expect(result.content_type).to eq("application/json")
    expect(result).not_to respond_to(:raw_body)
    stubs.verify_stubbed_calls
  end

  %i[post put patch].each do |method|
    it "sends #{method} JSON without changing the caller's payload" do
      payload = {"enabled" => false, "amount" => "3.13", "nested" => [{"id" => 12}]}
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.public_send(method, "/api/v3/test") do |env|
          expect(JSON.parse(env.body)).to eq(payload)
          json_response({"data" => {"id" => 1}}, status: 201)
        end
      end
      expect(build_client(stubs).connection.public_send(method, "test", payload: payload).status).to eq(201)
      expect(payload).to eq("enabled" => false, "amount" => "3.13", "nested" => [{"id" => 12}])
      stubs.verify_stubbed_calls
    end
  end

  {"application/pdf" => "%PDF-1.7\n(Basic Service) Tj\n\xFF\x00".b, "image/png" => "\x89PNG\r\n\x1A\n\xFF\x00".b,
   "application/zpl" => "^XA^FDBasic Letter^FS^XZ".b}.each do |content_type, bytes|
    it "returns #{content_type} documents unchanged when the caller accepts them" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/parcels/1/documents/label") do |env|
          expect(env.request_headers["Accept"]).to eq(content_type)
          [200, {"Content-Type" => content_type}, bytes]
        end
      end
      response = build_client(stubs).connection.get("parcels/1/documents/label", accept: content_type)
      expect(response.body).to eq(bytes)
      expect(response.body.encoding).to eq(Encoding::BINARY)
      expect(response.content_type).to eq(content_type)
      stubs.verify_stubbed_calls
    end
  end

  {
    ["image/png", "application/pdf"] => "Sendcloud returned application/pdf instead of image/png",
    ["image/png", "application/json"] => "Sendcloud returned application/json instead of image/png",
    ["application/json", "image/png"] => "Sendcloud returned image/png instead of JSON",
    ["application/json", "text/plain"] => "Sendcloud returned text/plain instead of JSON"
  }.each do |(accept, content_type), message|
    it "rejects a #{content_type} read when the caller accepts #{accept}" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/test") { [200, {"Content-Type" => content_type}, "{}"] }
      end
      expect { build_client(stubs).connection.get("test", accept: accept) }.to raise_error(SendcloudAPI::ParseError, message) { |error|
        expect(error).not_to be_ambiguous
        expect(error.response.content_type).to eq(content_type)
      }
    end
  end

  it "raises the typed HTTP error with its JSON body for a rejected document request" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/parcels/1/documents/label") { [404, {"Content-Type" => "application/json"}, fixture("contract_not_found.json")] }
    end
    expect { build_client(stubs).connection.get("parcels/1/documents/label", accept: "application/pdf") }.to raise_error(SendcloudAPI::NotFoundError) { |error|
      expect(error.body).to eq(JSON.parse(fixture("contract_not_found.json")))
    }
  end

  [200, 204].each do |status|
    it "rejects an empty HTTP #{status} body when the caller accepts a document" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/parcels/1/documents/label") { [status, {"Content-Type" => "image/png"}, ""] }
      end
      expect { build_client(stubs).connection.get("parcels/1/documents/label", accept: "image/png") }.to raise_error(
        SendcloudAPI::ParseError, "Sendcloud returned an empty body instead of image/png"
      ) { |error|
        expect(error).not_to be_ambiguous
        expect(error.status).to eq(status)
      }
    end
  end

  ["application/json; charset=utf-8", "application/vnd.api+json", nil].each do |content_type|
    it "parses JSON for #{content_type.inspect}" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/test") { [200, {"Content-Type" => content_type}, '{"name":"Café"}'.b] }
      end
      expect(build_client(stubs).connection.get("test").body).to eq("name" => "Café")
    end
  end

  it "retains valid JSON scalars" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test") { json_response("valid string") }
    end
    expect(build_client(stubs).connection.get("test").body).to eq("valid string")
  end

  it "accepts a deletion without content" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/api/v3/test?id=1") { [204, {}, ""] }
    end
    result = build_client(stubs).connection.delete("test", params: {id: 1})
    expect(result).to be_success
    expect(result).to be_no_content
    expect(result.body).to be_nil
  end

  {
    400 => SendcloudAPI::BadRequestError, 401 => SendcloudAPI::AuthenticationError,
    403 => SendcloudAPI::ForbiddenError, 404 => SendcloudAPI::NotFoundError,
    405 => SendcloudAPI::MethodNotAllowedError, 409 => SendcloudAPI::ConflictError,
    422 => SendcloudAPI::UnprocessableEntityError, 429 => SendcloudAPI::RateLimitError,
    500 => SendcloudAPI::ServerError, 503 => SendcloudAPI::ServerError, 599 => SendcloudAPI::ServerError,
    302 => SendcloudAPI::Error, 418 => SendcloudAPI::Error
  }.each do |status, error_class|
    it "maps HTTP #{status} to #{error_class}" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/test") { json_response({"errors" => []}, status: status, headers: {"Retry-After" => "30"}) }
      end
      expect { build_client(stubs).connection.get("test") }.to raise_error(error_class) { |error|
        expect(error.status).to eq(status)
        expect(error.headers["retry-after"]).to eq("30")
        expect(error.retry_after).to eq("30")
        expect(error.body).to eq("errors" => [])
        expect(error).not_to respond_to(:raw_body)
        expect(error).not_to be_ambiguous
        expect(error.request_method).to eq(:get)
        expect(error.request_path).to eq("test")
      }
    end
  end

  {
    "HTTP 404 from GET /returns/999999999, captured 2026-10-20 (guide live-lanes-5e56146.txt, lane 4)" =>
      ["return_not_found.json", 404, SendcloudAPI::NotFoundError, "No Return matches the given query."],
    "HTTP 400 from POST /shipping-options with country XX, captured 2026-10-18T17:03:57Z (run 20261019-routes)" =>
      ["shipping_options_invalid_country.json", 400, SendcloudAPI::BadRequestError,
        'validation_error Value error, Country XX does not exist. {"pointer":"/from_address/country_code"}'],
    "HTTP 404 from GET /contracts/355760 after deletion, captured 2026-10-18T17:12:41Z (run 20261019-contracts)" =>
      ["contract_not_found.json", 404, SendcloudAPI::NotFoundError, "not_found Not found"],
    "HTTP 409 from POST /returns with a used reference, captured 2026-10-18T17:07:55Z (run 20261019-returns)" =>
      ["return_duplicate_reference.json", 409, SendcloudAPI::ConflictError,
        "returns External reference has already been used in another return."],
    "HTTP 400 from POST /returns/validate without parcel_items, captured 2026-10-18T17:11:10Z (run 20261019-customs)" =>
      ["return_validation_missing_parcel_items.json", 400, SendcloudAPI::BadRequestError,
        "parcel_items It's required to inform parcel_items for international returns"]
  }.each do |source, (name, status, error_class, details)|
    it "summarizes the Sendcloud #{source}" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/api/v3/test") { [status, {"Content-Type" => "application/json"}, fixture(name)] }
      end
      expect { build_client(stubs).connection.post("test", payload: {}) }.to raise_error(error_class) { |error|
        expect(error.message).to eq("Sendcloud request failed with HTTP #{status}: #{details}")
        expect(error.body).to eq(JSON.parse(fixture(name)))
      }
    end
  end

  it "caps the error details in the message and keeps every error in the body" do
    errors = Array.new(300) { |index| {"code" => "invalid", "field" => "parcels[#{index}].weight", "message" => "Must be positive"} }
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v3/test") { json_response({"errors" => errors}, status: 422) }
    end
    expect { build_client(stubs).connection.post("test", payload: {}) }.to raise_error(SendcloudAPI::UnprocessableEntityError) { |error|
      prefix = "Sendcloud request failed with HTTP 422: "
      expect(error.message).to start_with("#{prefix}invalid parcels[0].weight Must be positive; ")
      expect(error.message).to end_with("...")
      expect(error.message.length).to eq(prefix.length + SendcloudAPI::Connection::ERROR_DETAILS_LIMIT + 3)
      expect(error.body["errors"].length).to eq(300)
    }
  end

  it "handles unexpected error envelopes without hiding the HTTP failure" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test") { json_response({"errors" => [nil, "bad", {}, {"detail" => "Failure"}]}, status: 400) }
    end
    expect { build_client(stubs).connection.get("test") }.to raise_error(SendcloudAPI::BadRequestError, "Sendcloud request failed with HTTP 400: Failure")
  end

  it "preserves a non-JSON rejection" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test") { [503, {"Content-Type" => "text/html"}, "Service unavailable"] }
    end
    expect { build_client(stubs).connection.get("test") }.to raise_error(SendcloudAPI::ServerError) { |error|
      expect(error.body).to eq("Service unavailable")
    }
  end
end
