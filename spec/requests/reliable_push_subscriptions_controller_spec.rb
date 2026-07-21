# frozen_string_literal: true

RSpec.describe ReliablePush::SubscriptionsController do
  fab!(:user)

  before do
    SiteSetting.reliable_push_enabled = true
    sign_in(user)
  end

  it "synchronizes the active browser subscription" do
    post "/reliable-push/subscriptions/sync.json",
         params: {
           subscription: {
             endpoint: "https://push.example/device",
             keys: { p256dh: "key", auth: "auth" },
           },
         }

    expect(response.status).to eq(200)
    expect(ReliablePush::Subscription.active.where(user: user).count).to eq(1)
  end
end
