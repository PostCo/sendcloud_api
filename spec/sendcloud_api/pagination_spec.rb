# frozen_string_literal: true

RSpec.describe SendcloudAPI::Pagination do
  def page(headers: {}, body: {"data" => []})
    SendcloudAPI::Response.new(status: 200, headers: headers, body: body)
  end

  it "reads the next cursor when the Link header also carries prev" do
    link = '<https://panel.sendcloud.sc/api/v3/contracts?cursor=cHJldg%3D%3D>; rel="prev", <https://panel.sendcloud.sc/api/v3/contracts?page_size=5&cursor=bmV4dA%3D%3D>; rel="next"'

    expect(described_class.next_cursor(page(headers: {"link" => link}))).to eq("bmV4dA==")
  end

  it "returns nil without a next page" do
    prev_only = '<https://panel.sendcloud.sc/api/v3/contracts?cursor=cHJldg%3D%3D>; rel="prev"'

    expect(described_class.next_cursor(page(headers: {"link" => prev_only}))).to be_nil
    expect(described_class.next_cursor(page(body: {"data" => [], "next" => nil}))).to be_nil
    expect(described_class.next_cursor(page(body: "%PDF".b))).to be_nil
  end
end
