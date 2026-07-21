# frozen_string_literal: true

RSpec.describe ReliablePush::Subscription do
  fab!(:user)
  fab!(:other_user) { Fabricate(:user) }

  def payload(endpoint, suffix = "one")
    {
      endpoint: endpoint,
      keys: {
        p256dh: "p256dh-#{suffix}",
        auth: "auth-#{suffix}",
      },
    }
  end

  it "keeps independent browser subscriptions active for the same user" do
    first = described_class.sync!(user: user, subscription: payload("https://push.test/one"))
    second = described_class.sync!(user: user, subscription: payload("https://push.test/two", "two"))

    expect(first.reload).to be_enabled
    expect(second).to be_enabled
    expect(described_class.active.where(user_id: user.id).count).to eq(2)
  end

  it "reassigns an endpoint to the currently authenticated owner" do
    original = described_class.sync!(user: user, subscription: payload("https://push.test/shared"))
    reassigned =
      described_class.sync!(
        user: other_user,
        subscription: payload("https://push.test/shared", "new-owner"),
      )

    expect(reassigned.id).to eq(original.id)
    expect(reassigned.user_id).to eq(other_user.id)
    expect(reassigned.p256dh).to eq("p256dh-new-owner")
    expect(reassigned).to be_enabled
  end
  it "does not let server-side mirroring steal an endpoint from another signed-in user" do
    original = described_class.sync!(user: user, subscription: payload("https://push.test/shared"))

    mirrored =
      described_class.sync!(
        user: other_user,
        subscription: payload("https://push.test/shared", "stale-core"),
        allow_reassignment: false,
      )

    expect(mirrored).to be_nil
    expect(original.reload.user_id).to eq(user.id)
    expect(original.p256dh).to eq("p256dh-one")
  end

end
