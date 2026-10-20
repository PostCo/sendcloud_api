# frozen_string_literal: true

RSpec.describe SendcloudAPI::Resources::User do
  it "reads the integration and user behind the keys" do
    client = serve(:get, "user/auth/metadata", body: fixture("auth_metadata.json"))

    expect(client.user.auth_metadata.body).to eq("data" => {"integration_id" => 637034, "user_id" => 825966})
  end
end
