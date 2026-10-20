# Sendcloud API

`sendcloud_api` is a Ruby client for the [Sendcloud API v3](https://sendcloud.dev/api/v3).
Each call sends one HTTP request without automatic retries. The caller owns idempotency, recovery, and business policy.

Version `0.1.0` adds resources for returns, shipping options, parcel documents and tracking, contracts, integrations, account metadata, invoice items, and webhook signatures.
Ruby 3.3 or newer is required.

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

## Resources

Each resource method sends one request and returns a `SendcloudAPI::Response` with Sendcloud's body unchanged.
Payloads are Hashes with Sendcloud's JSON field names as String keys. List filters are keyword arguments with Sendcloud's query parameter names, as Symbol or String keys.
An unknown filter raises `ArgumentError` before any request is sent, because Sendcloud ignores unknown filters and returns every record.
Ids and tracking numbers are required and are escaped into one path segment. A value of `.` or `..` raises `ArgumentError` before sending, because it would change the path.

### Returns

```ruby
created = client.returns.create(payload: {
  "from_address" => from_address,
  "to_address" => to_address,
  "ship_with" => {"type" => "shipping_option_code", "shipping_option_code" => "sendcloud:letterreturn"},
  "weight" => {"value" => 0.5, "unit" => "kg"},
  "external_reference" => "postco-123"
})
return_id = created.body["return_id"]
parcel_id = created.body["parcel_id"]

client.returns.validate(payload: return_payload)
client.returns.retrieve(id: return_id)
client.returns.list(page_size: 40, from_date: "2026-10-01 00:00:00", to_date: "2026-10-31 00:00:00")
client.returns.cancel(id: return_id)
```

Keep the `parcel_id` from the create response. `retrieve` returns the return without a `data` wrapper and without `parcel_id` or `external_reference`.
The return's `status` stays `open`. The parcel's progress is the last `parent_status` in `status_history`, such as `ready-to-send` or `cancelled`.
A second return with a used `external_reference` raises `ConflictError`, which is not ambiguous and carries no return id.
`cancel` answers HTTP 202. Read the return to see the parcel reach `cancelled`.
`validate` only checks a return, so its failures are never ambiguous.

### Shipping options

```ruby
client.shipping_options.search(payload: {
  "from_country_code" => "GB",
  "to_country_code" => "GB",
  "functionalities" => {"returns" => true},
  "parcels" => [{"weight" => {"value" => 1, "unit" => "kg"}}],
  "calculate_quotes" => true
})
```

The search only reads, so its failures are never ambiguous.

### Parcel documents

```ruby
label = client.parcel_documents.retrieve(parcel_id: parcel_id, type: "label", format: :png, dpi: 300)
label.body         # PNG bytes
label.content_type # "image/png"
```

`format` is `:pdf`, `:png`, or `:zpl` and sets the Accept header. The optional filters are `dpi` and `paper_size`.
Label documents can take a few seconds to appear after a return is created. Until then Sendcloud answers HTTP 404, which raises `NotFoundError`.
A carrier-native ZPL label is always returned as ZPL. A `:pdf` or `:png` request for one raises `ParseError` with `ambiguous? == false` and `error.response.content_type == "application/zpl"`.
Request it again with `format: :zpl`.

### Parcel tracking

```ruby
client.parcel_tracking.retrieve(tracking_number: tracking_number)
```

Sendcloud answers HTTP 404 for a parcel its tracking service has not registered yet.

### Contracts

```ruby
client.contracts.schemas(carrier_code: "dpd_gb")
client.contracts.list(carrier_code: "dpd_gb", is_active: true, page_size: 100)
contract = client.contracts.create(payload: {"carrier_code" => "dpd_gb", "is_active" => false, "contract_data" => contract_data})
client.contracts.retrieve(id: contract_id)
client.contracts.update(id: contract_id, payload: {"is_active" => true})
client.contracts.delete(id: contract_id)
```

A new contract starts in the `validating` state. Read it again to see `active` or `validation_failed`.

### Integrations, account metadata, and invoice items

```ruby
client.integrations.retrieve(id: integration_id)
client.integrations.update(id: integration_id, payload: {"webhook_active" => true, "webhook_url" => url})
client.user.auth_metadata
client.invoice_items.list(parcel_id: parcel_id, type: "shipment", created_after: "2026-10-01T00:00:00Z")
```

An integration update answers HTTP 204 with no body.

### Pagination

List methods return one page. `SendcloudAPI::Pagination.next_params(page, params)` returns the params for the next page, or `nil` on the last page.
It keeps every filter in `params` and sets `cursor`. A Sendcloud cursor holds only a position, so a request with the cursor alone returns records the filters would exclude.
It reads the `Link` header that contracts and invoice items use, and the body `next` URL that returns use. A next URL without exactly one cursor, or one that does not parse, raises `ParseError`.

```ruby
contracts = []
params = {carrier_code: "dpd_gb", page_size: 100}
while params
  page = client.contracts.list(**params)
  contracts.concat(page.body["data"])
  params = SendcloudAPI::Pagination.next_params(page, params)
end
```

### Webhook signatures

Sendcloud signs each webhook with the hex HMAC-SHA256 of the raw request body, keyed with the integration's secret key, in the `Sendcloud-Signature` header.

```ruby
valid = SendcloudAPI::WebhookSignature.verify(
  request.raw_post,
  request.headers[SendcloudAPI::WebhookSignature::HEADER],
  secret_key
)
```

Pass the unparsed body, because a parsed and encoded body has different bytes. The comparison runs in constant time.
A missing or wrong signature returns `false`, as does any value that is not 64 ASCII hex characters, whatever its encoding. A body that is not a String or an empty secret raises `ArgumentError`.

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
A path that starts with `/` or a scheme such as `https:`, or contains a `.` or `..` segment, also raises `ArgumentError` before sending. A leading `/` would replace the base URL's `/api/v3/`, and an absolute URL would send the Authorization header to another host.

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
That covers Sendcloud's two error list shapes, `{code, detail, source, status}` and `{code, field, message}`, and a string `errors` value from return lookups.
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
They receive a connection in their constructor. Use `get(path, params:, allowed:, accept:)` for reads. It rejects filters missing from `allowed` and omits nil filters.
Use `connection.post`, `connection.put`, `connection.patch`, or `connection.delete` for writes, and `read_only: true` for a POST that only reads.
`validate_payload!` checks String keys and required fields. `segment` requires a path value and escapes it.
Add explicit requires in `lib/sendcloud_api.rb` and memoized resource accessors in `Client`.

## Releases

Publishing a GitHub release triggers `release.yml` only in `PostCo/sendcloud_api`.
Its `test` job runs tests and lint without publishing rights.
The `publish` job then requires the tagged commit to be part of `main`, checks that the tag matches `v<VERSION>`, refuses version `0.0.0`, builds the gem with plain `gem build`, and pushes that exact version through RubyGems OIDC.
Only `publish` can request an OIDC token, so it never installs gems or runs Bundler; keep it that way.
It waits for `nickfarm27` to approve the GitHub `release` environment, which accepts only `v*` tags.

The RubyGems trusted publisher is registered for owner `PostCo`, repository `sendcloud_api`, workflow `release.yml`, and environment `release`.
See [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/).
The local Bundler release task runs tests and lint before its tag and publication tasks, but does not enforce main ancestry.
