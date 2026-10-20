# frozen_string_literal: true

require "socket"

RSpec.describe "Sendcloud write ambiguity" do
  %i[get post put patch delete].each do |method|
    {
      timeout: [nil, nil, SendcloudAPI::TransportError],
      connection: [nil, nil, SendcloudAPI::TransportError],
      gzip: [nil, nil, SendcloudAPI::TransportError],
      server: [503, '{"errors":[]}', SendcloudAPI::ServerError],
      invalid_json: [200, "not-json", SendcloudAPI::ParseError],
      invalid_utf8: [200, "{\"echo\":\"test-secret-key\xFF\"}", SendcloudAPI::ParseError],
      invalid_surrogate: [200, '{"echo":"test-secret-key\udc00"}', SendcloudAPI::ParseError],
      invalid_key: [200, '{"test-secret-key\udc00":"value"}', SendcloudAPI::ParseError]
    }.each do |failure, (status, body, error_class)|
      it "classifies #{method} #{failure} and dispatches once" do
        calls = 0
        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.public_send(method, "/api/v3/test") do
            calls += 1
            raise Faraday::TimeoutError, "test-secret-key" if failure == :timeout
            raise Faraday::ConnectionFailed, "test-secret-key" if failure == :connection
            raise Zlib::DataError, "test-secret-key" if failure == :gzip

            [status, {"Content-Type" => "application/json"}, body]
          end
        end
        options = %i[get delete].include?(method) ? {params: {}} : {payload: {}}
        expect { build_client(stubs).connection.public_send(method, "test", **options) }.to raise_error(error_class) { |error|
          expect(error.ambiguous?).to eq(method != :get)
          expect(error.request_method).to eq(method)
          expect(error.request_path).to eq("test")
          expect(error.message).not_to include("test-secret-key")
          expect(error.inspect).not_to include("test-secret-key")
          expect(error.cause).to be_nil
        }
        expect(calls).to eq(1)
        stubs.verify_stubbed_calls
      end
    end
  end

  %i[post put patch delete].each do |method|
    ["", "null"].each do |body|
      it "marks empty #{method} JSON success ambiguous" do
        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.public_send(method, "/api/v3/test") { [200, {"Content-Type" => "application/json"}, body] }
        end
        options = (method == :delete) ? {params: {}} : {payload: {}}
        expect { build_client(stubs).connection.public_send(method, "test", **options) }.to raise_error(SendcloudAPI::ParseError) { |error| expect(error).to be_ambiguous }
      end
    end
  end

  [400, 401, 403, 404, 405, 409, 422, 429].each do |status|
    it "treats HTTP #{status} as a rejected write without retrying" do
      calls = 0
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/api/v3/test") do
          calls += 1
          json_response({"errors" => []}, status: status)
        end
      end
      expect { build_client(stubs).connection.post("test", payload: {}) }.to raise_error(SendcloudAPI::Error) { |error| expect(error).not_to be_ambiguous }
      expect(calls).to eq(1)
    end
  end

  %i[get post put patch delete].each do |method|
    it "treats a 200 text/html answer to #{method} as unreadable" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.public_send(method, "/api/v3/test") { [200, {"Content-Type" => "text/html"}, "<html>Maintenance</html>"] }
      end
      options = %i[get delete].include?(method) ? {params: {}} : {payload: {}}
      expect { build_client(stubs).connection.public_send(method, "test", **options) }.to raise_error(SendcloudAPI::ParseError, "Sendcloud returned text/html instead of JSON") { |error|
        expect(error.ambiguous?).to eq(method != :get)
        expect(error.body).to eq("<html>Maintenance</html>")
      }
    end

    it "rejects an invalid #{method} path before dispatch without exposing it" do
      calls = 0
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.public_send(method, "/api/v3/test") { calls += 1 }
      end
      options = %i[get delete].include?(method) ? {params: {}} : {payload: {}}
      expect { build_client(stubs).connection.public_send(method, "x y?token=abc def", **options) }.to raise_error(ArgumentError) { |error|
        expect(error).not_to be_a(SendcloudAPI::Error)
        expect(error.message).not_to include("x y", "token", "abc")
        expect(error.full_message).not_to include("abc")
        expect(error.cause).to be_nil
      }
      expect(calls).to eq(0)
    end

    [".", "..", "./test", "../test", "returns/./1", "returns/../1", "returns/.", "returns/..", "returns/../../user", "returns/..?limit=1"].each do |path|
      it "rejects #{method} dot segment #{path} before dispatch" do
        calls = 0
        stubs = Faraday::Adapter::Test::Stubs.new { |stub|
          stub.public_send(method, /.*/) {
            calls += 1
            json_response({})
          }
        }
        options = %i[get delete].include?(method) ? {params: {}} : {payload: {}}
        expect { build_client(stubs).connection.public_send(method, path, **options) }.to raise_error(ArgumentError, "path must not contain . or .. segments")
        expect(calls).to eq(0)
      end
    end

    ["/test", "//evil.example/x", "https://evil.example/x", "HTTPS://evil.example/x", "mailto:a@evil.example"].each do |path|
      it "rejects #{method} #{path} before dispatch" do
        calls = 0
        stubs = Faraday::Adapter::Test::Stubs.new { |stub| stub.public_send(method, /.*/) { calls += 1 } }
        options = %i[get delete].include?(method) ? {params: {}} : {payload: {}}
        expect { build_client(stubs).connection.public_send(method, path, **options) }.to raise_error(
          ArgumentError, "path must be relative to the base URL, without a scheme or leading slash"
        )
        expect(calls).to eq(0)
      end
    end
  end

  it "returns a read-only POST result" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v3/shipping-options") { json_response({"data" => []}) }
    end
    expect(build_client(stubs).connection.post("shipping-options", payload: {}, read_only: true).body).to eq("data" => [])
  end

  {
    timeout: SendcloudAPI::TransportError,
    server: SendcloudAPI::ServerError,
    invalid_json: SendcloudAPI::ParseError,
    html: SendcloudAPI::ParseError
  }.each do |failure, error_class|
    it "never marks a read-only POST #{failure} ambiguous" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/api/v3/returns/validate") do
          raise Faraday::TimeoutError if failure == :timeout
          next [503, {"Content-Type" => "application/json"}, '{"errors":[]}'] if failure == :server
          next [200, {"Content-Type" => "application/json"}, "not-json"] if failure == :invalid_json

          [200, {"Content-Type" => "text/html"}, "<html></html>"]
        end
      end
      expect { build_client(stubs).connection.post("returns/validate", payload: {}, read_only: true) }.to raise_error(error_class) { |error|
        expect(error).not_to be_ambiguous
        expect(error.request_method).to eq(:post)
      }
    end
  end

  it "rejects invalid JSON payloads before dispatch" do
    calls = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v3/test") { calls += 1 }
    end
    expect { build_client(stubs).connection.post("test", payload: {"value" => Float::NAN}) }.to raise_error(JSON::GeneratorError)
    expect(calls).to eq(0)
  end

  it "wraps corrupt gzip through the default HTTP adapter without a retry" do
    server = TCPServer.new("127.0.0.1", 0)
    calls = 0
    worker = Thread.new do
      socket = server.accept
      calls += 1
      headers = []
      headers << socket.gets until headers.last == "\r\n"
      length = headers.grep(/\AContent-Length:/i).first.split(":", 2).last.to_i
      socket.read(length)
      socket.write("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 11\r\nConnection: close\r\n\r\ninvalidgzip")
    ensure
      socket&.close
    end
    client = SendcloudAPI::Client.new(public_key: "test-public-key", secret_key: "test-secret-key",
      base_url: "http://127.0.0.1:#{server.addr[1]}/api/v3/", timeout: 2, open_timeout: 2)
    expect { client.connection.post("test", payload: {}) }.to raise_error(SendcloudAPI::TransportError) { |error|
      expect(error).to be_ambiguous
      expect(error.cause).to be_nil
    }
    worker.value
    expect(calls).to eq(1)
  ensure
    server&.close
    worker&.kill
    worker&.join
  end
end
