# frozen_string_literal: true

RSpec.describe SendcloudAPI::WebhookSignature do
  let(:secret) { "test-webhook-secret" }
  let(:raw_body) { '{"action": "parcel_status_changed", "timestamp": 1760000000000}' }
  let(:signature) { "7ee4f8681fbb9293bca2fffd22a1a3b0e91fefd452b325efdd5cd266937df943" }

  it "accepts the hex HMAC-SHA256 of the raw body in either case" do
    expect(described_class.verify(raw_body, signature, secret)).to be(true)
    expect(described_class.verify(raw_body, signature.upcase, secret)).to be(true)
    expect(described_class.verify(raw_body.b, signature, secret)).to be(true)
  end

  it "rejects a changed body or another secret" do
    expect(described_class.verify(raw_body.sub("1760000000000", "1760000000001"), signature, secret)).to be(false)
    expect(described_class.verify(JSON.generate(JSON.parse(raw_body)), signature, secret)).to be(false)
    expect(described_class.verify(raw_body, signature, "other-secret")).to be(false)
  end

  it "rejects missing or malformed signatures" do
    [nil, "", " #{signature}", signature[0, 63], "#{signature}0", "g" * 64, "sha256=#{signature}", 123].each do |value|
      expect(described_class.verify(raw_body, value, secret)).to be(false), "accepted #{value.inspect}"
    end
  end

  it "refuses a parsed body or a missing secret" do
    expect { described_class.verify(JSON.parse(raw_body), signature, secret) }.to raise_error(ArgumentError, /unparsed request body/)
    expect { described_class.verify(raw_body, signature, "") }.to raise_error(ArgumentError, "secret must be a non-empty String")
    expect { described_class.verify(raw_body, signature, nil) }.to raise_error(ArgumentError, "secret must be a non-empty String")
  end
end
