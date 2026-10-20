# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::InvoiceItems do
  it "follows next_params with exactly one request per page and the same filters on every page" do
    following = {nil => "bz0xJnI9MCZwPTUyNzE3NzIxNQ==", "bz0xJnI9MCZwPTUyNzE3NzIxNQ==" => "bz0yJnI9MCZwPTUyNzE3NzIwMA==", "bz0yJnI9MCZwPTUyNzE3NzIwMA==" => nil}
    sent = []
    @stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/api/v3/invoice-items") do |env|
        sent << env.params.dup
        cursor = following.fetch(env.params["cursor"])
        link = cursor && %(<https://panel.sendcloud.sc/api/v3/invoice-items?cursor=#{URI.encode_www_form_component(cursor)}&page_size=1>; rel="next")
        json_response(fixture("invoice_items.json"), headers: link ? {"Link" => link} : {})
      end
    end
    client = build_client(@stubs)

    pages = []
    params = {parcel_id: 729018065, type: "shipment", page_size: 1}
    while params && pages.size <= following.size
      pages << client.invoice_items.list(**params)
      params = SendcloudAPI::Pagination.next_params(pages.last, params)
    end

    expect(pages.size).to eq(3)
    expect(sent.size).to eq(pages.size)
    expect(sent.map { _1.except("cursor") }).to all(eq("parcel_id" => "729018065", "type" => "shipment", "page_size" => "1"))
    expect(sent.map { _1["cursor"] }).to eq([nil, "bz0xJnI9MCZwPTUyNzE3NzIxNQ==", "bz0yJnI9MCZwPTUyNzE3NzIwMA=="])
    expect(pages.first.body["data"].map { _1["type"] }).to eq(%w[parcel_cancelled shipment])
  end

  it "rejects unknown filters before sending" do
    expect { offline_client.invoice_items.list(parcel: 1) }.to raise_error(ArgumentError, "Unknown parameters: parcel")
  end
end
