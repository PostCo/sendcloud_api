# frozen_string_literal: true

require "openssl"

module SendcloudAPI
  module WebhookSignature
    HEADER = "Sendcloud-Signature"
    HEX_SHA256 = /\A\h{64}\z/

    def self.verify(raw_body, signature, secret)
      raise ArgumentError, "raw_body must be the unparsed request body String" unless raw_body.is_a?(String)
      raise ArgumentError, "secret must be a non-empty String" unless secret.is_a?(String) && !secret.empty?
      hex = signature.b if signature.is_a?(String)
      return false unless hex&.match?(HEX_SHA256)

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body)
      OpenSSL.fixed_length_secure_compare(expected, hex.downcase)
    end
  end
end
