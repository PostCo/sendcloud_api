# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::Base do
  {
    "returns.retrieve" => [->(client, value) { client.returns.retrieve(id: value) }, :id, "returns/%s"],
    "returns.cancel" => [->(client, value) { client.returns.cancel(id: value) }, :id, "returns/%s/cancel"],
    "contracts.retrieve" => [->(client, value) { client.contracts.retrieve(id: value) }, :id, "contracts/%s"],
    "contracts.update" => [->(client, value) { client.contracts.update(id: value, payload: {"is_active" => true}) }, :id, "contracts/%s"],
    "contracts.delete" => [->(client, value) { client.contracts.delete(id: value) }, :id, "contracts/%s"],
    "integrations.retrieve" => [->(client, value) { client.integrations.retrieve(id: value) }, :id, "integrations/%s"],
    "integrations.update" => [->(client, value) { client.integrations.update(id: value, payload: {"webhook_active" => false}) }, :id, "integrations/%s"],
    "parcel_documents.retrieve parcel_id" => [->(client, value) { client.parcel_documents.retrieve(parcel_id: value, type: "label", format: :pdf) }, :parcel_id, "parcels/%s/documents/label"],
    "parcel_documents.retrieve type" => [->(client, value) { client.parcel_documents.retrieve(parcel_id: 1, type: value, format: :pdf) }, :type, "parcels/1/documents/%s"],
    "parcel_tracking.retrieve" => [->(client, value) { client.parcel_tracking.retrieve(tracking_number: value) }, :tracking_number, "parcels/tracking/%s"]
  }.each do |name, (call, parameter, path)|
    describe name do
      let(:paths) { [] }
      let(:client) do
        build_client(Faraday::Adapter::Test::Stubs.new do |stub|
          %i[get patch delete].each do |method|
            stub.public_send(method, /.*/) do |env|
              paths << env.url.path
              [200, {"Content-Type" => env.request_headers["Accept"]}, "{}"]
            end
          end
        end)
      end

      it "rejects . and .. before sending" do
        %w[. ..].each do |value|
          expect { call.call(client, value) }.to raise_error(ArgumentError, "#{parameter} cannot be . or ..")
        end
        expect(paths).to be_empty
      end

      it "keeps other dotted values inside one path segment" do
        ["...", "../user", "a.."].each { |value| call.call(client, value) }

        expect(paths).to eq(["...", "..%2Fuser", "a.."].map { |segment| "/api/v3/#{format(path, segment)}" })
      end
    end
  end
end
