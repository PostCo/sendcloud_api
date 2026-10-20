# frozen_string_literal: true

RSpec.describe SendcloudAPI::Connection do
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
    expect(result.raw_body).to eq('{"data":{"id":637034}}')
    expect(result.content_type).to eq("application/json")
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

  {"application/pdf" => "%PDF-1.7\n\xFF\x00".b, "image/png" => "\x89PNG\r\n\x1A\n\xFF\x00".b,
   "application/octet-stream" => "\xFF\x00".b, "text/plain" => "plain text"}.each do |content_type, bytes|
    it "returns #{content_type} as raw bytes with the content type" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v3/test") { [200, {"Content-Type" => content_type}, bytes] }
      end
      response = build_client(stubs).connection.get("test")
      expect(response.body).to eq(bytes)
      expect(response.raw_body).to eq(bytes)
      expect(response.body.encoding).to eq(Encoding::BINARY)
      expect(response.content_type).to eq(content_type)
      stubs.verify_stubbed_calls
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
        expect(error.raw_body).to eq('{"errors":[]}')
        expect(error).not_to be_ambiguous
        expect(error.request_method).to eq(:get)
        expect(error.request_path).to eq("test")
      }
    end
  end

  it "combines Sendcloud field errors into the message and keeps the raw body" do
    body = '{ "errors": [{"code":"invalid","field":"weight","message":"Must be positive"},{"code":"required","field":"country","message":"Required"}] }'
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v3/test") { [422, {"Content-Type" => "application/json"}, body] }
    end
    expect { build_client(stubs).connection.post("test", payload: {}) }.to raise_error(SendcloudAPI::UnprocessableEntityError) { |error|
      expect(error.message).to eq("Sendcloud request failed with HTTP 422: invalid weight Must be positive; required country Required")
      expect(error.raw_body).to eq(body)
      expect(error.body).to eq(JSON.parse(body))
    }
  end

  it "combines JSON:API title, detail and source into the message" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/test") do
        json_response({"errors" => [{"status" => "400", "title" => "Invalid request", "detail" => "Unknown country", "source" => {"pointer" => "/country"}}]}, status: 400)
      end
    end
    expect { build_client(stubs).connection.get("test") }.to raise_error(SendcloudAPI::BadRequestError) { |error|
      expect(error.message).to include("400 Invalid request Unknown country", '{"pointer":"/country"}')
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
