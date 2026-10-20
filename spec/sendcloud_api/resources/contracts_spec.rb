# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::Contracts do
  let(:contract) do
    {
      "carrier_code" => "dpd_gb",
      "is_active" => false,
      "contract_data" => {"name" => "Example DPD UK", "client_id" => "example-client", "secret" => "example-carrier-password", "account_nr" => "0000000"}
    }
  end

  it "lists contracts with filters and exposes the Link header cursor" do
    link = '<https://panel.sendcloud.sc/api/v3/contracts?cursor=cD0zNDg5MTc%3D&page_size=2>; rel="next"'
    client = serve(:get, "contracts", body: fixture("contracts.json"), headers: {"Link" => link})
    response = client.contracts.list(carrier_code: "royal_mailv2", is_active: false, page_size: 2)

    expect(request.params).to eq("carrier_code" => "royal_mailv2", "is_active" => "false", "page_size" => "2")
    expect(response.body["data"].map { _1["id"] }).to eq([351090, 348920])
    expect(SendcloudAPI::Pagination.next_cursor(response)).to eq("cD0zNDg5MTc=")
  end

  it "has no next cursor on the last page" do
    client = serve(:get, "contracts", body: fixture("contracts.json"))

    expect(SendcloudAPI::Pagination.next_cursor(client.contracts.list)).to be_nil
  end

  it "creates a contract without exposing the carrier password" do
    created = fixture("contract_created.json")
    client = serve(:post, "contracts", status: 201, body: created.merge("data" => created["data"].merge("secret" => "example-carrier-password")))
    response = client.contracts.create(payload: contract)

    expect(sent_json).to eq(contract)
    expect(response.body["data"]).to include("id" => 355760, "state" => "validating", "secret" => "[FILTERED]")
  end

  it "requires a carrier code to create a contract" do
    expect { offline_client.contracts.create(payload: {"is_active" => false}) }.to raise_error(ArgumentError, "carrier_code is required")
  end

  it "reads a contract after asynchronous validation" do
    client = serve(:get, "contracts/355760", body: fixture("contract_validation_failed.json"))

    expect(client.contracts.retrieve(id: 355760).body["data"]["state"]).to eq("validation_failed")
  end

  it "returns the captured not-found error" do
    client = serve(:get, "contracts/355760", status: 404, body: fixture("contract_not_found.json"))

    expect { client.contracts.retrieve(id: 355760) }.to raise_error(SendcloudAPI::NotFoundError)
  end

  it "updates a contract with PATCH" do
    client = serve(:patch, "contracts/355760", body: fixture("contract_created.json"))
    client.contracts.update(id: 355760, payload: {"is_active" => true})

    expect(sent_json).to eq("is_active" => true)
  end

  it "deletes a contract" do
    client = serve(:delete, "contracts/355760", status: 204)

    expect(client.contracts.delete(id: 355760)).to be_no_content
  end

  it "reads contract schemas for one carrier or all carriers" do
    client = serve(:get, "contracts/schemas", body: fixture("contract_schemas_dpd_gb.json"))
    fields = client.contracts.schemas(carrier_code: "dpd_gb").body["data"].first["fields"]

    expect(request.params).to eq("carrier_code" => "dpd_gb")
    expect(fields.select { _1["required"] }.map { _1["name"] }).to eq(%w[client_id secret account_nr])

    client.contracts.schemas
    expect(request.params).to eq({})
  end
end
