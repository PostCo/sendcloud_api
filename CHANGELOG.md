# Changelog

## [Unreleased]

- Add the version 0.0.0 client foundation for Sendcloud API v3 with HTTP Basic authentication and configurable timeouts.
- Return JSON, or caller-requested PDF, PNG, and ZPL documents, with typed errors and uncertain write outcomes, without automatic retries.
- Remove credentials from responses and errors without changing field names, identifiers, ordinary text in successful JSON, or document bytes.
- Add RSpec, Standard, Ruby 3.3 and 3.4 CI, and guarded RubyGems OIDC publishing. Endpoint resources and the first release follow separately.
