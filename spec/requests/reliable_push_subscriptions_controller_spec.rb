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
             endpoint: "https://push.test/current-device",
             keys: { p256dh: "current-key", auth: "current-auth" },
           },
         }

    expect(response.status).to eq(200)
    expect(ReliablePush::Subscription.active.where(user: user).count).to eq(1)
  end

  it "does not disable another device when the current browser has no subscription" do
    subscription =
      ReliablePush::Subscription.sync!(
        user: user,
        subscription: {
          endpoint: "https://push.test/other-device",
          keys: { p256dh: "other-key", auth: "other-auth" },
        },
      )

    post "/reliable-push/subscriptions/sync.json", params: { subscription: nil }

    expect(response.status).to eq(200)
    expect(subscription.reload).to be_enabled
  end
end
