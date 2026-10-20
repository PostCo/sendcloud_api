# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::ParcelTracking do
  it "reads tracking events by tracking number" do
    client = serve(:get, "parcels/tracking/SCEXAMPLE0003", body: fixture("parcel_tracking.json"))
    data = client.parcel_tracking.retrieve(tracking_number: "SCEXAMPLE0003").body["data"]

    expect(data["events"].first.slice("description", "exception")).to eq("description" => "Cancelled", "exception" => "cancelled")
  end

  it "raises NotFoundError while Sendcloud has not registered the parcel yet" do
    client = serve(:get, "parcels/tracking/SCEXAMPLE0001", status: 404, body: fixture("parcel_not_found.json"))

    expect { client.parcel_tracking.retrieve(tracking_number: "SCEXAMPLE0001") }.to raise_error(SendcloudAPI::NotFoundError) { |error|
      expect(error.body).to eq("detail" => "Parcel does not exist")
    }
  end

  it "requires a tracking number" do
    expect { offline_client.parcel_tracking.retrieve(tracking_number: "") }.to raise_error(ArgumentError, "tracking_number is required")
  end
end
