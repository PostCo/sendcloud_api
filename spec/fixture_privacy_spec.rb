# frozen_string_literal: true

RSpec.describe "Spec fixtures" do
  def leaks(text)
    unlabelled = text.gsub(/"\w+_uuid":\s*"\h{8}-\h{4}-\h{4}-\h{4}-\h{12}"/, "")
    keys = text.scan(/(?<!\h)\h{32,64}(?!\h)/) +
      unlabelled.scan(/\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/) +
      text.scan(/Basic\s+[A-Za-z0-9+\/]{16,}={0,2}/)
    emails = text.gsub(/%40/i, "@").scan(/[\w.%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/)
    keys + emails.reject { |address| address.split("@").last.casecmp?("example.com") }
  end

  let(:fixtures) { Dir.glob(File.join(__dir__, "fixtures", "**", "*")).select { File.file?(_1) } }

  it "flags hex keys, UUIDs, Basic credentials and addresses outside example.com" do
    sample = "#{"a1" * 16} 0123abcd-0123-4abc-8def-0123456789ab Basic dGVzdC1wdWJsaWMta2V5OnRlc3Q= jo@postco.co jo%40gmail.com"

    expect(leaks(sample)).to eq(["a1" * 16, "0123abcd-0123-4abc-8def-0123456789ab", "Basic dGVzdC1wdWJsaWMta2V5OnRlc3Q=", "jo@postco.co", "jo@gmail.com"])
    expect(leaks('"colli_uuid": "0123abcd-0123-4abc-8def-0123456789ab", "email": "person@example.com"')).to be_empty
  end

  it "hold no key-shaped strings and no email addresses, allowing only RFC 2606 placeholders at example.com and Sendcloud *_uuid identifiers" do
    expect(fixtures).not_to be_empty

    found = fixtures.to_h { |path| [path.delete_prefix("#{__dir__}/"), leaks(File.binread(path).force_encoding(Encoding::UTF_8).scrub)] }
    expect(found.reject { |_path, matches| matches.empty? }).to eq({})
  end
end
