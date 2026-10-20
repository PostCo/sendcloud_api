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

`client.connection` exposes these methods:

```ruby
get(path, params: {}, accept: "application/json")
post(path, payload:, read_only: false)
put(path, payload:)
patch(path, payload:)
delete(path, params: {})
```

Use endpoint paths relative to the configured base URL. Payloads are encoded as JSON without changing field names or amounts.
HTTP redirects are returned as errors, without another request.
A path or base URL that is not a valid URL raises `ArgumentError` before any request is sent. The message omits the value.
A path that starts with `/` or a scheme such as `https:` also raises `ArgumentError` before sending. A leading `/` would replace the base URL's `/api/v3/`, and an absolute URL would send the Authorization header to another host.

Each successful call returns a `SendcloudAPI::Response` with `status`, normalized lowercase `headers`, `body`, and `content_type`.
`success?` identifies HTTP 200 through 299. `no_content?` identifies HTTP 204 or a nil body.

Every request sends the `accept` value as its Accept header. By default the connection expects JSON.
A JSON response keeps the provider's String keys. Content types ending in `+json` are JSON, and a missing content type is read as JSON.
To fetch a document, pass its media type. Sendcloud's parcel documents endpoint returns `application/pdf`, `image/png`, or `application/zpl` depending on Accept.
The body is then the unchanged response bytes in binary encoding.

```ruby
label = client.connection.get("parcels/#{parcel_id}/documents/label", accept: "image/png")
label.body         # PNG bytes
label.content_type # "image/png"
```

A successful response in a different format than the caller expected raises `ParseError`.
That includes HTML answering a JSON request and ZPL answering a PNG request. Sendcloud returns native ZPL labels as ZPL whatever the Accept header says.
An empty successful response to a document request also raises `ParseError`.

Some Sendcloud POST endpoints only read, such as shipping option searches and return validation.
Pass `read_only: true` for those so their failures are never reported as ambiguous writes.

```ruby
client.connection.post("shipping-options", payload: query, read_only: true)
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

`TransportError` wraps Faraday and decompression failures. `ParseError` reports unreadable JSON or a response in an unexpected format.
A non-204 write response with empty or null JSON also raises `ParseError`.
HTTP errors take precedence over parsing errors, so an unreadable HTTP 503 response raises `ServerError`.

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

HTTP errors expose `response`, `status`, `headers`, `body`, and `retry_after`.
Their messages join each error's `code`, `field`, `message`, `title`, `detail`, and `source` values.
That covers both Sendcloud error shapes: `{code, detail, source, status}` from validation and lookups, and `{code, field, message}` from returns.
A `code` equal to the HTTP status is left out, so a returns 409 reads "HTTP 409: returns External reference has already been used in another return."
The joined details are capped at 1,000 characters. The body keeps every error.

`error.ambiguous?` is true for a POST, PUT, PATCH, or DELETE that fails in transport, receives HTTP 5xx, or returns an unreadable or unexpected response.
A write may already have applied. Read the provider's current state and reconcile the result before deciding whether to retry.
Reads, `read_only: true` POSTs, and HTTP 4xx rejections have `ambiguous? == false`. This flag describes mutation uncertainty, not retryability.
`request_method` is a Symbol. `request_path` omits query parameters.
Invalid JSON input fails before dispatch and raises `JSON::GeneratorError`.

The connection removes credentials before a response or error leaves it.
It knows the configured keys and their Basic authorization value, and it learns more from submitted and returned fields whose names look like credentials.
In a successful response, a known value of 8 or more bytes is removed wherever it appears. A shorter value is removed only where it is the whole string, so it cannot alter identifiers such as tracking numbers.
An error's message, body, headers, and request path lose every known value wherever it appears, whatever its length.
Fields named like credentials are replaced with `[FILTERED]`. Field names are never changed.
Successful JSON gets only those two rules, so ordinary text such as "Basic Letter" or a signed URL stays intact.
Error messages and non-JSON error bodies also lose `Basic` and `Bearer` values, `name=value` or `name: value` credentials, and URL user information.
Accepted documents are returned byte for byte.
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
Its build job requires the source commit to be merged into `main`, checks that the tag matches `v<VERSION>`, refuses version `0.0.0`, runs tests and lint, builds the gem, and uploads it as an artifact.
A second job in the GitHub `release` environment downloads that gem and pushes it through RubyGems OIDC.
Only that job can request an OIDC token, and it runs no repository code or dependencies.

Before the first release, register the RubyGems trusted publisher for owner `PostCo`, repository `sendcloud_api`, workflow `release.yml`, and environment `release`.
See [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/).
The local Bundler release task runs tests and lint before its tag and publication tasks, but does not enforce main ancestry.
Version `0.0.0` is a scaffold. Do not tag or publish it.
