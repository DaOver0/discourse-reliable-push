# frozen_string_literal: true

RSpec.describe ReliablePush::Admin::StatusController do
  fab!(:admin)

  before do
    SiteSetting.reliable_push_enabled = true
    sign_in(admin)
  end

  it "returns aggregate delivery health without endpoint credentials" do
    get "/reliable-push/admin/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "subscriptions",
      "deliveries",
      "attempts",
      "oldest_pending_delivery",
      "latest_delivery",
    )
    expect(response.body).not_to include("p256dh")
    expect(response.body).not_to include("auth")
  end
end
