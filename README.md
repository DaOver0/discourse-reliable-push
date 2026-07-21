# discourse-reliable-push

A server-side Discourse plugin that replaces the browser-delivery portion of Discourse Web Push with a durable, observable outbox and per-device retry queue.

## What it does

- Captures Discourse `push_notification` events before core delivery.
- Captures persisted `notification_created` events, including badge and plugin notification types.
- Covers topic replies, mentions, private messages, Discourse Chat messages/mentions, badges, and other personal notifications.
- Optionally broadcasts every new public topic to members of configured groups.
- Keeps the existing Discourse browser `PushSubscription` and VAPID keys, but mirrors subscriptions into plugin-owned multi-device storage.
- Suppresses only `PushNotificationPusher.push` when replacement mode is enabled. In-app MessageBus notifications and Discourse Hub remain intact.
- Stores one delivery per semantic user event and one attempt per browser device.
- Retries network errors, HTTP 429, and server errors with configurable backoff.
- Disables expired subscriptions on HTTP 404/410 or `WebPush::ExpiredSubscription`.
- Re-checks topic/chat access immediately before every delivery attempt.
- Records accepted, service-worker received, and notification-opened timestamps.
- Exposes authenticated user status and an administrator-only aggregate health endpoint.

## Status

This repository is an implementation-ready MVP. Ruby/JavaScript/YAML syntax is validated in the repository, but full integration tests must run inside a matching Discourse checkout because Discourse models, Sidekiq, PostgreSQL, and the plugin test harness are runtime dependencies.

## Installation

In your Discourse container configuration:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/DaOver0/discourse-reliable-push.git
```

Then rebuild the container:

```bash
cd /var/discourse
./launcher rebuild app
```

Enable `reliable_push_enabled` in **Admin → Settings → Plugins**.

## Migration strategy

1. Install the plugin with `reliable_push_replace_core_web_push` disabled.
2. Ask users with existing push permission to open the forum once. The client initializer mirrors their active subscription.
3. Check `/reliable-push/status.json` while logged in and confirm `active_subscriptions` is non-zero.
4. Inspect `/reliable-push/admin/status.json` as an administrator for aggregate delivery health.
5. Enable `reliable_push_replace_core_web_push`.
6. Watch Sidekiq and Rails logs for `Reliable Push` errors.

Core's notification permission UI remains the enrollment mechanism. This avoids attempting to register a second root service worker or a second Push API subscription.

## New-topic broadcasts

Broadcasts are off by default. To enable them:

- enable `reliable_push_broadcast_new_topics`;
- put numeric Discourse group IDs in `reliable_push_broadcast_group_ids`;
- set a conservative `reliable_push_broadcast_max_recipients`.

Every recipient is checked with `Guardian#can_see?` before event creation and again immediately before delivery. Private-message topics are never broadcast.

## Delivery states

Delivery states:

- `pending`
- `preparing`
- `accepted` — push service accepted the encrypted message
- `received` — the browser service worker received the event
- `opened` — the user clicked the notification
- `no_subscription`
- `expired`
- `failed`
- `cancelled`

`accepted` does not prove that a human saw the notification. The service-worker acknowledgement provides a stronger device-level signal, while `opened` is the explicit interaction signal.

## Security properties

- No second service worker registration is created.
- ACK routes use a per-delivery random token and do not expose message contents.
- Topic and chat ACLs are checked before each attempt.
- Push endpoint credentials stay server-side after synchronization.
- A browser endpoint is globally owned by one account, preventing account-switch notification leakage.
- A browser subscription is disabled when the browser reports it as expired.

## Known limitations

- Desktop push still depends on the browser/OS background process. A fully terminated browser may delay delivery.
- The plugin uses the forum's existing VAPID keys. Changing VAPID keys requires users to create new browser subscriptions.
- Per-user event-category preferences are not included in the MVP; browser permission, core subscription state, DND, and site-wide settings are respected.
- Full compatibility must be verified against the exact Discourse commit used by the forum before production rollout.

## Development

Place this repository under `plugins/discourse-reliable-push` in a Discourse development checkout, migrate, and run:

```bash
bundle exec rake db:migrate
bundle exec rspec plugins/discourse-reliable-push/spec
bin/lint plugins/discourse-reliable-push
```

## License

MIT
