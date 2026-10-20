# frozen_string_literal: true

require_relative "lib/sendcloud_api/version"

Gem::Specification.new do |spec|
  spec.name = "sendcloud_api"
  spec.version = SendcloudAPI::VERSION
  spec.authors = ["PostCo"]
  spec.email = ["engineering@postco.co"]

  spec.summary = "A Ruby client for the Sendcloud API v3"
  spec.description = "A small, explicit Ruby client for Sendcloud API v3 reads and writes, without automatic retries."
  spec.homepage = "https://github.com/PostCo/sendcloud_api"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md",
    "lib/**/*.rb"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 2.7", "< 3"
  spec.add_dependency "uri", ">= 0.11", "< 2"

  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", ">= 3.12", "< 4"
  spec.add_development_dependency "standard", ">= 1.35", "< 2"
end
