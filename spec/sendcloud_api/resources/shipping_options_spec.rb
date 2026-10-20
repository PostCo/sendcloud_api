# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::ShippingOptions do
  let(:query) do
    {
      "from_country_code" => "GB",
      "to_country_code" => "GB",
      "functionalities" => {"returns" => true},
      "parcels" => [{"weight" => {"value" => 1, "unit" => "kg"}}],
      "calculate_quotes" => true
    }
  end

  it "searches shipping options" do
    client = serve(:post, "shipping-options", body: fixture("shipping_options.json"))
    option = client.shipping_options.search(payload: query).body["data"].first

    expect(sent_json).to eq(query)
    expect(option["code"]).to eq(fixture("shipping_options.json")["data"].first["code"])
  end

  it "never reports a failed search as an uncertain write" do
    client = serve(:post, "shipping-options", status: 500, body: {"errors" => []})

    expect { client.shipping_options.search(payload: query) }.to raise_error(SendcloudAPI::ServerError) { |error|
      expect(error).not_to be_ambiguous
    }
  end

  it "returns the captured invalid-country error" do
    client = serve(:post, "shipping-options", status: 400, body: fixture("shipping_options_invalid_country.json"))

    expect { client.shipping_options.search(payload: query) }.to raise_error(SendcloudAPI::BadRequestError)
  end

  it "requires String keys" do
    expect { offline_client.shipping_options.search(payload: {from_country_code: "GB"}) }.to raise_error(ArgumentError, /String keys/)
  end
end
