# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::Integrations do
  it "reads an integration" do
    client = serve(:get, "integrations/637034", body: fixture("integration.json"))
    data = client.integrations.retrieve(id: 637034).body["data"]

    expect(data.slice("id", "type", "webhook_active")).to eq("id" => 637034, "type" => "api", "webhook_active" => false)
  end

  it "updates an integration with PATCH and accepts the empty 204" do
    client = serve(:patch, "integrations/637034", status: 204)
    response = client.integrations.update(id: 637034, payload: {"webhook_active" => true, "webhook_url" => "https://example.com/webhooks/sendcloud"})

    expect(sent_json).to eq("webhook_active" => true, "webhook_url" => "https://example.com/webhooks/sendcloud")
    expect(response).to be_no_content
  end

  it "returns the captured validation error as a definite rejection" do
    client = serve(:patch, "integrations/637034", status: 400, body: fixture("integration_blank_webhook_url.json"))

    expect { client.integrations.update(id: 637034, payload: {"webhook_url" => ""}) }
      .to raise_error(SendcloudAPI::BadRequestError, /webhook_url cannot be blank/) { |error| expect(error).not_to be_ambiguous }
  end
end
