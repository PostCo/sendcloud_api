# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::InvoiceItems do
  it "lists invoice items for a parcel and keeps its filters on every page" do
    link = '<https://panel.sendcloud.sc/api/v3/invoice-items?cursor=bz0xJnI9MCZwPTUyNzE3NzIxNQ%3D%3D&page_size=1>; rel="next"'
    client = serve(:get, "invoice-items", body: fixture("invoice_items.json"), headers: {"Link" => link})
    filters = {parcel_id: 729018065, type: "shipment", page_size: 1}
    response = client.invoice_items.list(**filters)

    expect(request.params).to eq("parcel_id" => "729018065", "type" => "shipment", "page_size" => "1")
    expect(response.body["data"].map { _1["type"] }).to eq(%w[parcel_cancelled shipment])

    params = filters
    2.times do
      params = SendcloudAPI::Pagination.next_params(response, params)
      response = client.invoice_items.list(**params)
      expect(request.params).to eq("parcel_id" => "729018065", "type" => "shipment", "page_size" => "1", "cursor" => "bz0xJnI9MCZwPTUyNzE3NzIxNQ==")
    end
  end

  it "rejects unknown filters before sending" do
    expect { offline_client.invoice_items.list(parcel: 1) }.to raise_error(ArgumentError, "Unknown parameters: parcel")
  end
end
