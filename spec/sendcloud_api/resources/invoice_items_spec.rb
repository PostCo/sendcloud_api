# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::InvoiceItems do
  it "lists invoice items for a parcel and pages with the Link header cursor" do
    link = '<https://panel.sendcloud.sc/api/v3/invoice-items?cursor=bz0xJnI9MCZwPTUyNzE3NzIxNQ%3D%3D&page_size=1>; rel="next"'
    client = serve(:get, "invoice-items", body: fixture("invoice_items.json"), headers: {"Link" => link})
    response = client.invoice_items.list(parcel_id: 729018065, type: "shipment", page_size: 1)

    expect(request.params).to eq("parcel_id" => "729018065", "type" => "shipment", "page_size" => "1")
    expect(response.body["data"].map { _1["type"] }).to eq(%w[parcel_cancelled shipment])
    cursor = SendcloudAPI::Pagination.next_cursor(response)
    expect(cursor).to eq("bz0xJnI9MCZwPTUyNzE3NzIxNQ==")

    client.invoice_items.list(cursor: cursor, created_after: "2026-10-01T00:00:00Z")
    expect(request.params).to eq("cursor" => cursor, "created_after" => "2026-10-01T00:00:00Z")
  end

  it "rejects unknown filters before sending" do
    expect { offline_client.invoice_items.list(parcel: 1) }.to raise_error(ArgumentError, "Unknown parameters: parcel")
  end
end
