# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::Returns do
  let(:payload) do
    {
      "from_address" => {"name" => "Example Person", "country_code" => "GB"},
      "to_address" => {"name" => "Example Warehouse", "country_code" => "GB"},
      "ship_with" => {"type" => "shipping_option_code", "shipping_option_code" => "sendcloud:letterreturn"},
      "weight" => {"value" => 0.5, "unit" => "kg"},
      "external_reference" => "postco-ref-1"
    }
  end

  it "creates a return and returns both the return and parcel ids" do
    client = serve(:post, "returns", body: fixture("return_created.json"))
    response = client.returns.create(payload: payload)

    expect(sent_json).to eq(payload)
    expect(response.body).to eq("multi_collo_ids" => [], "parcel_id" => 729017591, "return_id" => 24260544)
  end

  it "raises a definite ConflictError when the external reference already exists" do
    client = serve(:post, "returns", status: 409, body: fixture("return_duplicate_reference.json"))

    expect { client.returns.create(payload: payload) }.to raise_error(SendcloudAPI::ConflictError) { |error|
      expect(error).not_to be_ambiguous
      expect(error.body).to eq(fixture("return_duplicate_reference.json"))
    }
  end

  it "reports a server error after create as an uncertain write" do
    client = serve(:post, "returns", status: 503, body: {"errors" => []})

    expect { client.returns.create(payload: payload) }.to raise_error(SendcloudAPI::ServerError) { |error|
      expect(error).to be_ambiguous
    }
  end

  it "validates a return as a read" do
    client = serve(:post, "returns/validate", body: fixture("return_validated.json"))

    expect(client.returns.validate(payload: payload).body).to eq(fixture("return_validated.json"))
    expect(sent_json).to eq(payload)
  end

  it "never reports a failed validation as an uncertain write" do
    client = serve(:post, "returns/validate", status: 503, body: {"errors" => []})

    expect { client.returns.validate(payload: payload) }.to raise_error(SendcloudAPI::ServerError) { |error|
      expect(error).not_to be_ambiguous
    }
  end

  it "reads a return, which Sendcloud does not wrap in data" do
    client = serve(:get, "returns/24260544", body: fixture("return.json"))
    body = client.returns.retrieve(id: 24260544).body

    expect(body.slice("id", "status", "is_cancellable")).to eq("id" => 24260544, "status" => "open", "is_cancellable" => true)
    expect(body).not_to include("parcel_id", "external_reference")
  end

  it "lists returns with filters and continues from the body next URL with the same filters" do
    page = fixture("returns.json").merge("next" => "https://panel.sendcloud.sc/api/v3/returns?cursor=cD0yNDIxNTUwNA%3D%3D&page_size=1")
    client = serve(:get, "returns", body: page)
    filters = {page_size: 1, parent_parcel_status: "ready-to-send", cursor: nil}
    response = client.returns.list(**filters)

    expect(request.params).to eq("page_size" => "1", "parent_parcel_status" => "ready-to-send")
    expect(response.body["data"].first["id"]).to eq(24215504)

    client.returns.list(**SendcloudAPI::Pagination.next_params(response, filters))
    expect(request.params).to eq("page_size" => "1", "parent_parcel_status" => "ready-to-send", "cursor" => "cD0yNDIxNTUwNA==")
  end

  it "rejects unknown list filters before sending" do
    expect { offline_client.returns.list(status: "open") }.to raise_error(ArgumentError, "Unknown parameters: status")
  end

  it "accepts String filter keys and still rejects unknown ones" do
    client = serve(:get, "returns", body: fixture("returns.json"))
    client.returns.list("cursor" => "cD0yNDIxNTUwNA==", "page_size" => 1)

    expect(request.params).to eq("cursor" => "cD0yNDIxNTUwNA==", "page_size" => "1")
    expect { offline_client.returns.list("status" => "open", :cursr => "x") }.to raise_error(ArgumentError, "Unknown parameters: cursr, status")
  end

  it "cancels a return with an empty PATCH body" do
    client = serve(:patch, "returns/24260544/cancel", status: 202, body: fixture("return_cancelled.json"))
    response = client.returns.cancel(id: 24260544)

    expect(sent_json).to eq({})
    expect(response.status).to eq(202)
    expect(response.body).to eq("message" => "Cancellation requested successfully")
  end

  it "requires ids and escapes them into one path segment" do
    expect { offline_client.returns.retrieve(id: " ") }.to raise_error(ArgumentError, "id is required")
    expect { offline_client.returns.cancel(id: nil) }.to raise_error(ArgumentError, "id is required")

    client = serve(:get, "returns/1%2F..%2Fcancel", body: fixture("return.json"))
    client.returns.retrieve(id: "1/../cancel")
    expect(request.url.path).to eq("/api/v3/returns/1%2F..%2Fcancel")
  end
end
