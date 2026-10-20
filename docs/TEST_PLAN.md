# Verification matrix — v0.1.1

Run from a matching Discourse checkout; not from this standalone archive. Make sure to test **the exact pinned Discourse commit** and matching Chat plugin.

## Server checks

- `ruby -c plugin.rb`
- `ruby -c lib/discourse_reliable_push/engine.rb`
- `ruby -c app/controllers/discourse_reliable_push/subscriptions_controller.rb`
- `ruby -c app/jobs/regular/reliable_push_test_notification.rb`
- `bundle exec rspec plugins/discourse-reliable-push/spec/requests/discourse_reliable_push/subscriptions_spec.rb`

## Physical devices / PWA

| Scenario | Expected |
|---|---|
| Android, fresh installed PWA, click enable | Permission asked through user gesture and registered server-side |
| iPhone iOS 16.4+, first launch before worker controls the page | Wait for worker readiness; enable without requiring a pre-existing controller |
| PWA closed, forum mention | Core notification appears subject to permissions/policy |
| Chat channel `always`, new message | Core Chat notification appears when core considers it eligible |
| Chat channel `mention`, ordinary message | No push unless eligible via mention or separate Chat rule |
| Chat channel `never` or muted | No new-message push |
| Chat DM | Follows core DM notification policy and relevant options |
| Explicit native Discourse disable | No automatic repair/resubscribe |
| Push permission denied in OS | No prompting/repair; clear status |
| Logout, login as a different user | Server subscription is reassigned to newly authenticated user on sync |
| Test button pressed | Only current browser gets diagnostic push; queue response is not delivery receipt |
| Test pressed repeatedly | Server rate limit fires after two attempts/minute/user |
| Invalid subscription keys | API rejects request |
| Reopen PWA while previously subscribed but browser subscription lost | Auto-repair if browser/OS permits |
| Reopen in airplane mode | Visible error, no unbounded retries |

**Network:** inspect Sidekiq and browser developer tools. If tests aren't working, collect logs with sensitive `endpoint`/`auth`/`p256dh` values redacted.

## Closed-PWA diagnostic test

- In PWA: ensure ready, click **Test in background (30 sec)**, then close interface immediately.
- Check OS notification after 45–90 sec; do not force-stop from OS application settings.
- Test immediate push separately.
- Confirm `Rails.logger` includes acceptance line for successful `WebPush.payload_send`; absence of display after provider acceptance is **not** an indication that the server never sent.
- Verify DND returns `queued: false`, no job queued.
- Confirm rate limit applies jointly to immediate and delayed tests.
- If delayed test works but Chat message push does not, test after a period longer than `push_notification_time_window_mins`, with another account sending the message and channel preferences verified.
