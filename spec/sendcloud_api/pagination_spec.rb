# frozen_string_literal: true

RSpec.describe SendcloudAPI::Pagination do
  def page(headers: {}, body: {"data" => []})
    SendcloudAPI::Response.new(status: 200, headers: headers, body: body)
  end

  def link(url, rel)
    "<#{url}>; rel=#{rel}"
  end

  let(:next_url) { "https://panel.sendcloud.sc/api/v3/contracts?page_size=5&cursor=bmV4dA%3D%3D" }
  let(:prev_url) { "https://panel.sendcloud.sc/api/v3/contracts?cursor=cHJldg%3D%3D" }

  it "keeps the caller's filters and replaces the cursor" do
    header = "#{link(prev_url, '"prev"')}, #{link(next_url, '"next"')}"
    params = {:carrier_code => "dpd_gb", "is_active" => true, :cursor => "old"}

    expect(described_class.next_params(page(headers: {"link" => header}), params))
      .to eq(carrier_code: "dpd_gb", is_active: true, cursor: "bmV4dA==")
    expect(params).to eq(:carrier_code => "dpd_gb", "is_active" => true, :cursor => "old")
  end

  it "reads rel as space-separated, case-insensitive link relation types" do
    ['"prev next"', "next", '"NEXT"', 'next; title="a, b"'].each do |rel|
      expect(described_class.next_params(page(headers: {"link" => link(next_url, rel)}), {})).to eq(cursor: "bmV4dA=="), rel
    end
  end

  it "ignores relation types that only contain next" do
    ['"nextpage"', '"next-archive"', '"prev"'].each do |rel|
      expect(described_class.next_params(page(headers: {"link" => link(next_url, rel)}), {})).to be_nil, rel
    end
  end

  it "reads the body next URL that returns use" do
    body = {"data" => [], "next" => "https://panel.sendcloud.sc/api/v3/returns?cursor=cD0yNDIxNTUwNA%3D%3D&page_size=1"}

    expect(described_class.next_params(page(body: body), {parent_parcel_status: "cancelled"}))
      .to eq(parent_parcel_status: "cancelled", cursor: "cD0yNDIxNTUwNA==")
  end

  it "returns nil on the last page" do
    expect(described_class.next_params(page(headers: {"link" => link(prev_url, '"prev"')}), {})).to be_nil
    expect(described_class.next_params(page(body: {"data" => [], "next" => nil}), {})).to be_nil
    expect(described_class.next_params(page(body: "%PDF".b), {})).to be_nil
  end

  it "raises ParseError for a next URL it cannot follow" do
    [
      "https://panel.sendcloud.sc:port/api/v3/contracts?cursor=abc",
      "https://panel.sendcloud.sc/api/v3/contracts?cursor=%zz",
      "https://panel.sendcloud.sc/api/v3/contracts?page_size=5",
      "https://panel.sendcloud.sc/api/v3/contracts?cursor=",
      "https://panel.sendcloud.sc/api/v3/contracts?cursor=abc&cursor=def"
    ].each do |url|
      expect { described_class.next_params(page(headers: {"link" => link(url, '"next"')}), {}) }
        .to raise_error(SendcloudAPI::ParseError, /next page URL/) { |error| expect(error.cause).to be_nil }
    end
    expect { described_class.next_params(page(body: {"next" => 123}), {}) }.to raise_error(SendcloudAPI::ParseError)
  end
end
