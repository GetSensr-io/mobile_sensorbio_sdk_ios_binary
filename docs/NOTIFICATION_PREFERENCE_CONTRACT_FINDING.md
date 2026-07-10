# Settings / Notification-Preference & Device-Registration Contracts — Implementation Finding

Task: t_d44d3c76 (parent t_26857dad ownership map). Author: coder (kanban worker), GitHub `sontakey`.
Date: 2026-07-09. Repo: `GetSensr-io/server_svc_core_api_monolith` (Go monolith, default branch `develop`).
Branch: `task/notification_prefs_device_contracts` (worktree at `.claude/worktrees/SB-NOTIFPREF`).

## Decision: IMPLEMENT (existing infrastructure supports both contracts)

The acceptance criteria offered two branches — implement on real existing infra, or
document a deferral. Evaluation found **real, deployed supporting infrastructure on
every axis**, so this is the IMPLEMENT branch. No new notification infrastructure was
built and no integrations with non-existent services were fabricated.

### Existing infrastructure that was verified (not assumed)

| Concern | Existing infra found | Evidence |
| --- | --- | --- |
| Device registration | `pkg/pushnotification` `RegisterAppForPushNotification` / `RemoveAppFromPushNotfication`; table `push_notification_app_instances` PK `(user_id, device_push_token)` with `ON DUPLICATE KEY UPDATE` upsert | `db/pushnotifications.go` `SaveAppInstanceForPushNotification`; migration `1610053322_add_pushnotification_related_schemas.up.sql`; live API caller `api/mobile/userservice.go` `RegisterApp` |
| Push notifications | `pkg/pushnotification` full pipeline (push service, schedule details, per-device instances), workers `pushnotifications`/`org_pushnotifications_reminders` | `pkg/pushnotification/{pushnotification,lib,repo,pushservice}.go` |
| User settings store | Generic per-user typed KV store `user_custom_settings` PK `(user_id, setting)` | `pkg/users/custom_settings/*`, `db/user_custom_settings.go`, migration `1585325400_add_schema_for_app_custom_settings.up.sql` |

Toolchain verified locally: Go 1.26.4, package builds + existing tests run **offline
with mocks** (no Aurora needed for unit layer).

## What was implemented

### 1. Notification-preference contract (`pkg/users/custom_settings`)
Built ON TOP of the existing `user_custom_settings` KV store — **no schema migration
required** (new preferences are just new boolean `Setting` keys in the same
`(user_id, setting, value)` rows; per-user isolation is inherited from the composite PK).

- New setting keys: `push_notifications_enabled`, `daily_reminder_notifications_enabled`,
  `insights_notifications_enabled`. Defaults are **opt-IN (true)** to preserve current
  behaviour for users who never set a preference.
- `notification_preferences.go`: `GetNotificationPreferences` (read, per-user scoped),
  `SaveNotificationPreferences` (partial/PATCH-style update — nil field = leave as-is;
  empty update rejected; returns effective prefs), and `ShouldSend{PushNotification,
  DailyReminder,InsightsNotification}` consult helpers (master push switch vetoes
  per-category flags).
- Each preference maps to a real notification pathway (push pipeline, daily-reminder
  workers, insights/smart-metric generators). This change owns only the read/write
  contract; wiring the consult-before-send call sites into those producers is left as a
  separate reviewable change (deliberately not scope-crept).

### 2. Persistence fix (`db/user_custom_settings.go`)
`SaveUserCustomSettings` previously did a plain `INSERT` and only handled `AppLogs`
(zero production callers). Extended to persist the new preference fields **and** made it
an idempotent upsert (`ON DUPLICATE KEY UPDATE`) — without this, a second save of any
setting would fail on the `(user_id, setting)` PK. Only non-nil fields are written, which
is what makes single-toggle partial updates work.

### 3. Tests (offline, mock-backed — no live DB)
- `notification_preferences_test.go` (18 tests): CRUD, partial-update-preserves-others,
  upsert idempotency (same write ×3, no error), per-user isolation (user-1 / user-2 /
  untouched user-3 never cross-contaminate), empty-update rejection, error propagation,
  master-switch veto semantics.
- `device_registration_contract_test.go` (8 tests): re-registering the same device is
  idempotent (N registrations → 1 row, stable registration id); distinct devices → distinct
  rows; registration failure persists no row; per-user isolation on shared token and on
  deregistration (removing user-1's device leaves user-2 intact); repeated removal is safe.
  Uses in-memory `Repository`+`PushService` doubles that faithfully model the real DB
  upsert (`ON DUPLICATE KEY UPDATE`) and delete-by-`(user_id, source_type, device_type,
  device_id)` semantics.

## Verification (all green)
- `go build ./api/... ./pkg/users/... ./pkg/pushnotification/... ./db/...` — exit 0
- `go test ./pkg/pushnotification/... ./pkg/users/custom_settings/...` — ok (26 new tests
  pass, existing suite unaffected)
- `gofmt -l` — clean; `go vet` — exit 0; `go mod tidy` — no go.mod/go.sum drift
  (matches CI `build.yml` required gates)

## Scope boundaries respected
- **No production deploys**, no migrations run, no AWS calls (parent task flagged staging
  runtime creds as an open item; not needed for this unit-layer contract work).
- **No proto/gRPC regen**: exposing these contracts as new mobile RPCs requires the
  Docker `buf` codegen path (`make protoc`) and crosses into wire-contract + deploy
  territory. The domain + repo + service contracts and their tests are complete; the
  transport binding (proto RPC + `api/mobile` handler calling `GetNotificationPreferences`/
  `SaveNotificationPreferences`) is the natural follow-up and is called out for the
  reviewer.
- **No commit/push**: per repo AGENTS.md, changes are left staged in the worktree for
  human review rather than committed.

## Files changed
```
db/user_custom_settings.go                                     (+38/-9  upsert + prefs)
pkg/users/custom_settings/custom_settings.go                   (+61     setting keys/defaults)
pkg/users/custom_settings/library.go                           (+15     wiring)
pkg/users/custom_settings/notification_preferences.go          (NEW 215 contract)
pkg/users/custom_settings/notification_preferences_test.go     (NEW 314 tests)
pkg/pushnotification/device_registration_contract_test.go      (NEW 319 tests)
```

## Recommended follow-up (for a reviewer / next task, NOT done here)
1. Add mobile gRPC RPCs (`GetNotificationPreferences` / `UpdateNotificationPreferences`)
   to `specs/proto/user_service.proto`, regen via `make protoc`, and add `api/mobile`
   handlers that call the contract functions with `GetTargetUser(ctx)` for auth/isolation.
2. Wire `ShouldSend*` consult calls into the push producers (daily-reminder worker,
   insights/smart-metric generators, generic push send path).
3. Integration test against a local MySQL (`go-scripts/cmd/migrate_local_mysql`) to
   exercise the real `ON DUPLICATE KEY UPDATE` upsert end-to-end.
