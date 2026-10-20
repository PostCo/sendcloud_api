# Changelog

## [0.1.0] - 2026-10-20

- Add resources for returns (create, validate, retrieve, list, cancel), shipping option search, parcel documents, parcel tracking, contracts (list, create, retrieve, update, delete, schemas), integrations (retrieve, update), account metadata, and invoice items.
- Add `SendcloudAPI::Pagination.next_cursor` for both Sendcloud cursor styles, and `SendcloudAPI::WebhookSignature.verify` for signed webhooks.
- Reject unknown list filters before sending, because Sendcloud ignores them and returns every record.
- Add the client foundation for Sendcloud API v3 with HTTP Basic authentication and configurable timeouts.
- Return JSON, or caller-requested PDF, PNG, and ZPL documents, with typed errors and uncertain write outcomes, without automatic retries.
- Remove credentials from responses and errors without changing field names, identifiers, ordinary text in successful JSON, or document bytes.
- Add RSpec, Standard, Ruby 3.3 and 3.4 CI, and RubyGems OIDC publishing from a job that runs no repository code.
