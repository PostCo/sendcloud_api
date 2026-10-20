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

  it "rejects a signature that is not 64 ASCII hex characters in any encoding" do
    [
      ("a" * 63 + "\xFF").dup.force_encoding(Encoding::UTF_8),
      "\xFF".b * 64,
      "#{signature}\n",
      signature.tr("0-9a-f", "０-９ａ-ｆ"),
      signature.encode(Encoding::UTF_16LE)
    ].each do |value|
      expect(described_class.verify(raw_body, value, secret)).to be(false), "accepted #{value.inspect}"
    end
  end

  it "refuses a parsed body or a missing secret" do
    expect { described_class.verify(JSON.parse(raw_body), signature, secret) }.to raise_error(ArgumentError, /unparsed request body/)
    expect { described_class.verify(raw_body, signature, "") }.to raise_error(ArgumentError, "secret must be a non-empty String")
    expect { described_class.verify(raw_body, signature, nil) }.to raise_error(ArgumentError, "secret must be a non-empty String")
  end

  describe "with a body Sendcloud delivered" do
    let(:delivered_body) { File.binread(File.join(__dir__, "..", "fixtures", "sendcloud", "webhook_parcel_status_changed.json")) }
    let(:delivered_signature) { OpenSSL::HMAC.hexdigest("SHA256", secret, delivered_body) }

    it "keeps the recorded delivery byte for byte" do
      expect(delivered_body.bytesize).to eq(4105)
      expect(OpenSSL::Digest.hexdigest("SHA256", delivered_body)).to eq("4f7b480905e803f7ec1b6ec6b98ca558486e32be9d1fcdd9871f5a0c345e8166")
    end

    it "accepts its signature" do
      expect(described_class.verify(delivered_body, delivered_signature, secret)).to be(true)
    end

    it "rejects it after any one byte changes" do
      [0, delivered_body.bytesize / 2, delivered_body.bytesize - 1].each do |index|
        changed = delivered_body.dup
        changed.setbyte(index, changed.getbyte(index) ^ 0x01)
        expect(described_class.verify(changed, delivered_signature, secret)).to be(false), "accepted a change at byte #{index}"
      end
    end

    it "rejects it without a signature" do
      expect(described_class.verify(delivered_body, nil, secret)).to be(false)
      expect(described_class.verify(delivered_body, "", secret)).to be(false)
    end
  end
end
