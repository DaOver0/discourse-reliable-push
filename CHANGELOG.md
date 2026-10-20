# Changelog

## 0.1.1 — 2026-10-20

- Fix missing `admin_js.admin.site_settings.categories.discourse_reliable_push` translations (ru/en).
- Add localized admin settings labels.
- Add optional 30-second delayed, server-side Web Push diagnostic for closed PWA.
- Distinguish a job scheduled from successful device delivery.
- Log successful provider acceptance without subscription secrets; diagnose server-side DND in test response.
- Document push activity-window and OS troubleshooting.

## 0.1.0 — 2026-10-20

- Added authenticated per-device Web Push subscription verification and sync.
- Added consent-aware recovery that does not override explicit disabled state.
- Added per-device Sidekiq test push, throttling and RU/EN UI.
- Reused native Discourse Forum/Chat notification pipeline; no delivery modifications.
- Added installation and physical-device verification documentation.
