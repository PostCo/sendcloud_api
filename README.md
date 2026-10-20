# Sendcloud API

`sendcloud_api` is a Ruby client for the [Sendcloud API v3](https://sendcloud.dev/api/v3).
Each call sends one HTTP request without automatic retries. The caller owns idempotency, recovery, and business policy.

Version `0.0.0` provides the client and connection. Endpoint resources arrive in the next PR and version `0.1.0`.
This scaffold has no published release. Ruby 3.3 or newer is required.

## Authentication

Sendcloud uses the public key as the HTTP Basic username and the secret key as the password.
See [Sendcloud authentication](https://sendcloud.dev/docs/getting-started/authentication/).

```ruby
client = SendcloudAPI::Client.new(
  public_key: ENV.fetch("SENDCLOUD_PUBLIC_KEY"),
  secret_key: ENV.fetch("SENDCLOUD_SECRET_KEY")
)
response = client.connection.get("user/auth/metadata")
```

Both credentials must be non-empty Strings. Configuration belongs to each client instance.
The default base URL is `https://panel.sendcloud.sc/api/v3/`, the open timeout is 5 seconds, and the request timeout is 30 seconds.

You can override the URL and timeouts or inject a Faraday adapter for tests.

```ruby
client = SendcloudAPI::Client.new(
  public_key: "test-public-key",
  secret_key: "test-secret-key",
  base_url: "https://example.test/api/v3/",
  open_timeout: 2,
  timeout: 10,
  adapter: [:test, stubs]
)
```

## Requests and responses

`client.connection` exposes `get(path, params: {})`, `post(path, payload:)`, `put(path, payload:)`, `patch(path, payload:)`, and `delete(path, params: {})`.
Use endpoint paths relative to the configured base URL. Payloads are encoded as JSON without changing field names or amounts.
HTTP redirects are returned as errors, without another request.

Each successful call returns a `SendcloudAPI::Response` with `status`, normalized lowercase `headers`, `body`, and `raw_body`.
`success?` identifies HTTP 200 through 299. `no_content?` identifies HTTP 204 or a nil body.

JSON responses retain the provider's String keys. Content types ending in `+json` are JSON, too.
A missing content type is treated as JSON. Other content types return the body as binary bytes, including PDF and PNG label documents.
`response.content_type` retains the full Content-Type header, including parameters.
`raw_body` retains the response bytes with credentials removed. Redaction can change bytes that contain credentials.

```ruby
response.status
response.headers
response.body
response.raw_body
response.content_type
```

## Errors and recovery

All errors below inherit from `SendcloudAPI::Error`.

| HTTP status | Error class |
| --- | --- |
| 400 | `BadRequestError` |
| 401 | `AuthenticationError` |
| 403 | `ForbiddenError` |
| 404 | `NotFoundError` |
| 405 | `MethodNotAllowedError` |
| 409 | `ConflictError` |
| 422 | `UnprocessableEntityError` |
| 429 | `RateLimitError` |
| 500 through 599 | `ServerError` |
| Other unsuccessful statuses | `Error` |

`TransportError` wraps Faraday and decompression failures. `ParseError` reports unreadable JSON.
A non-204 write response with empty or null JSON also raises `ParseError`.
HTTP errors take precedence over JSON parsing errors, so an unreadable HTTP 503 response raises `ServerError`.

```ruby
begin
  client.connection.get("user/auth/metadata")
rescue SendcloudAPI::RateLimitError => error
  retry_after = error.retry_after
rescue SendcloudAPI::Error => error
  status = error.status
  details = error.body
end
```

HTTP errors expose `response`, `status`, `headers`, `body`, `raw_body`, and `retry_after`.
Their messages combine Sendcloud's field-error `code`, `field`, and `message` values or JSON:API `status`, `title`, `detail`, and `source` values.
The response and the message are sanitized before leaving the connection.

`error.ambiguous?` is true for a POST, PUT, PATCH, or DELETE that fails in transport, receives HTTP 5xx, or returns unreadable JSON.
A write may already have applied. Read the provider's current state and reconcile the result before deciding whether to retry.
Reads and HTTP 4xx rejections have `ambiguous? == false`. This flag describes mutation uncertainty, not retryability.
`request_method` is a Symbol. `request_path` omits query parameters.
Invalid JSON input fails before dispatch and raises `JSON::GeneratorError`.

The transport filters the configured keys, their Basic authorization value, credential-bearing fields, and echoed credentials from response bodies and headers.
It learns additional credential values from submitted payloads and response fields before redacting echoes.
Redaction does not change caller-owned inputs or outbound payloads.
Client, connection, resource, redactor, and response inspection omit authentication state and payloads.
Transport errors omit the upstream message and cause because those can retain the authenticated request.
Ordinary business data remains in responses and can appear in provider error messages.

## Development

```console
mise exec -- bundle install
mise exec -- bundle exec rake
mise exec -- bundle exec rake build
```

The default Rake task runs RSpec and Standard. CI tests Ruby 3.3 and 3.4.
Specs use Faraday's test adapter and a loopback HTTP server. They do not call Sendcloud.
The gemspec packages only the library, README, changelog, and license. The lockfile is not committed.

Add endpoint classes under `SendcloudAPI::Resources` as subclasses of `Base`.
They receive a connection in their constructor. Use `get` for nil-filter omission and `connection.post`, `connection.put`, `connection.patch`, or `connection.delete` for writes.
`validate_payload!` checks String keys and required fields. `require_parameter!` checks required method arguments.
Add explicit requires in `lib/sendcloud_api.rb` and memoized resource accessors in `Client`.

## Releases

Publishing a GitHub release triggers `release.yml` only in `PostCo/sendcloud_api`.
The workflow requires the source commit to be merged into `main`, checks that the tag matches `v<VERSION>`, runs tests and lint, and builds the gem.
It publishes that artifact through RubyGems OIDC with the GitHub `release` environment.

Before the first release, register the RubyGems trusted publisher for owner `PostCo`, repository `sendcloud_api`, workflow `release.yml`, and environment `release`.
See [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/).
The local Bundler release task runs tests and lint before its tag and publication tasks, but does not enforce main ancestry.
Version `0.0.0` is a scaffold. Do not tag or publish it.
