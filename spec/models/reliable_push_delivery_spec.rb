# frozen_string_literal: true

RSpec.describe ReliablePush::Delivery do
  fab!(:user)

  before { SiteSetting.reliable_push_delivery_ttl_hours = 24 }

  it "deduplicates the same semantic event for a user" do
    first = described_class.ingest!(user:, kind: "mentioned", dedupe_key: "post:mentioned:1", payload: { title: "one" }, priority: 100)
    second = described_class.ingest!(user:, kind: "mentioned", dedupe_key: "post:mentioned:1", payload: { title: "two" }, priority: 100)

    expect(second.id).to eq(first.id)
    expect(second.payload["title"]).to eq("two")
    expect(described_class.count).to eq(1)
  end
end

RSpec.describe ReliablePush::Delivery, "acknowledgement state" do
  fab!(:user)

  it "does not downgrade an opened delivery when a received acknowledgement arrives late" do
    delivery = described_class.create!(
      user: user,
      kind: "mentioned",
      dedupe_key: "ack-order",
      payload: {},
      priority: 100,
      expires_at: 1.day.from_now,
    )

    delivery.mark_opened!
    delivery.mark_received!

    expect(delivery.reload).to be_opened
    expect(delivery.received_at).to be_present
  end
end
