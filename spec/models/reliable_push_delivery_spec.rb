# frozen_string_literal: true

RSpec.describe ReliablePush::Delivery do
  fab!(:user)

  before do
    SiteSetting.reliable_push_enabled = true
    SiteSetting.reliable_push_delivery_ttl_hours = 24
  end

  def ingest(kind:, priority:, title:)
    described_class.ingest!(
      user: user,
      kind: kind,
      dedupe_key: "post:42",
      payload: { "title" => title, "preference_key" => "topic_posts" },
      priority: priority,
      source_type: "Post",
      source_id: 42,
    )
  end

  it "deduplicates equal-priority events and upgrades higher-priority semantics" do
    first, first_changed = ingest(kind: "topic_post", priority: 45, title: "Broadcast")
    duplicate, duplicate_changed = ingest(kind: "topic_post", priority: 45, title: "Duplicate")
    upgraded, upgraded_changed = ingest(kind: "mentioned", priority: 110, title: "Mention")

    expect(first_changed).to eq(true)
    expect(duplicate_changed).to eq(false)
    expect(duplicate.id).to eq(first.id)
    expect(duplicate.reload.payload["title"]).to eq("Broadcast")

    expect(upgraded_changed).to eq(true)
    expect(upgraded.id).to eq(first.id)
    expect(upgraded.reload.kind).to eq("mentioned")
    expect(upgraded.priority).to eq(110)
    expect(upgraded.payload["title"]).to eq("Mention")
    expect(described_class.where(user_id: user.id, dedupe_key: "post:42").count).to eq(1)
  end


  it "revives a failed semantic delivery when a higher-priority personal event arrives" do
    delivery, = ingest(kind: "topic_post", priority: 45, title: "Broadcast")
    delivery.update!(state: :failed, last_error: "temporary failure")

    upgraded, changed = ingest(kind: "mentioned", priority: 110, title: "Mention")

    expect(changed).to eq(true)
    expect(upgraded.reload).to be_pending
    expect(upgraded.kind).to eq("mentioned")
    expect(upgraded.last_error).to be_nil
  end

  it "never downgrades received or opened state after a later device acceptance" do
    delivery, = ingest(kind: "topic_post", priority: 45, title: "Post")

    delivery.mark_received!
    delivery.mark_accepted!
    expect(delivery.reload).to be_received

    delivery.mark_opened!
    delivery.mark_accepted!
    expect(delivery.reload).to be_opened
  end
end
