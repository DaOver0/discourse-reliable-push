# frozen_string_literal: true

RSpec.describe ReliablePush::Subscription do
  fab!(:user)

  it "upserts a browser subscription without disabling other devices" do
    old = described_class.create!(user:, endpoint: "https://push.example/old", endpoint_digest: described_class.digest("https://push.example/old"), p256dh: "old-key", auth: "old-auth")

    current = described_class.sync!(
      user: user,
      subscription: { endpoint: "https://push.example/new", keys: { p256dh: "new-key", auth: "new-auth" } },
      user_agent: "RSpec",
    )

    expect(current).to be_enabled
    expect(old.reload).to be_enabled
    expect(current.user_agent).to eq("RSpec")

    other_user = Fabricate(:user)
    moved = described_class.sync!(
      user: other_user,
      subscription: { endpoint: "https://push.example/new", keys: { p256dh: "moved-key", auth: "moved-auth" } },
    )
    expect(moved.id).to eq(current.id)
    expect(moved.user).to eq(other_user)
  end
end
