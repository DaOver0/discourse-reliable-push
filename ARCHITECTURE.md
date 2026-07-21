# Architecture

## Event path

```text
Discourse notification or chat/post push event
  → ReliablePush::EventIngestor
  → reliable_push_deliveries (deduplicated outbox)
  → ReliablePushPrepareDelivery
  → reliable_push_attempts (one row per active device)
  → ReliablePushDeliverAttempt
  → Web Push service
  → Discourse service worker + plugin extension
  → received/opened ACK
```

## Core replacement boundary

The plugin prepends only `PushNotificationPusher.push`. When replacement mode is active, the standard browser sender is skipped. It does not register a global push filter, because that filter is also used by Discourse for live in-browser MessageBus alerts. `HubPushNotificationPusher` continues to run from the core delivery job.

## Deduplication

Semantic keys prioritize stable source identifiers:

- `chat:<type>:<chat_message_id>`
- `post:<type>:<post_id>`
- `topic-post:<type>:<topic_id>:<post_number>`
- `notification:<notification_id>`

The database enforces uniqueness per user.

## Retry policy

Retries are per device. Successful devices are never resent merely because another device failed. Default delays are 60 seconds, 5 minutes, 30 minutes, 2 hours, 6 hours, and 24 hours, capped by both maximum attempts and delivery TTL.

## Observability

The schema distinguishes:

- push-service acceptance;
- browser service-worker receipt;
- notification click.

This is intentionally more precise than treating an HTTP success from the push endpoint as delivery to the user.
