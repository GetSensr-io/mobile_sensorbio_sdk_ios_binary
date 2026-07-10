# Noom Product-Loop Build Plan

Status: architecture contract + task-sized implementation sequence. Do not implement product code from this card.

Program root:
- `/Users/anton/mobile_sensorbio_sdk_ios_binary`

Primary inputs:
- Parity contract: `docs/plans/noom-exampleapp-parity.md`
- Current SDK interface: `SDK_INTERFACE.md` at `ccb317efa5866b17392472500187ec72916aace6`
- Canonical ExampleApp behavior: `33d7a341f7d72d63669c86ce0478a9008fd8a139`
- Current Noom WIP: `NoomApp/`
- Real backend ownership discovered by read-only GitHub inspection:
  - `GetSensr-io/server_svc_core_api_monolith` — private Go backend, default branch `develop`, updated 2026-07-08. Relevant files from tree: `api/mobile/dashboard.go`, `api/mobile/insights.go`, `api/mobile/experiments.go`, `api/mobile/in_app_notifications.go`, `api/mobile/user_custom_settings.go`, `api/webdashboard/push_notifications.go`, `api/publicapi/insights.go`, `api/publicapi/sleep.go`.
  - `GetSensr-io/mobile_grpc_protos` — private proto contracts, default branch `new_proto_structure`, updated 2026-07-07. Relevant files: `proto/experiments.proto`, `proto/new_insights.proto`, `proto/population_insights.proto`, `proto/dashboardv2.proto`, `proto/recovery_score.proto`, `proto/svc_in_app_notifications.proto`, `proto/svc_user.proto`, `proto/timeseries_data.proto`.
  - `GetSensr-io/infrastructure` — private AWS IaC, default branch `develop`, HCL, updated 2026-07-07.
  - `GetSensr-io/web_platform` — private TypeScript web/admin platform, default branch `sensr_develop`, updated 2026-07-07.
- Local backend repos were not present under `/Users/anton` except SDK/firmware/public-audit repos; backend implementation should clone/use the real private backend repos above in its own card, not in this iOS binary repo.

Product-loop contract:
Sensor Band -> Body State -> Suggested Experiment -> Sleep/Recovery Progress

Hard rule:
NoomApp may present only SDK-backed body-state and insights now. Persisted experiment lifecycle, progress signals, settings, and notifications are backend-owned contracts. Do not fake those in SwiftUI. Do not create local-only state as the source of truth.

Current SDK-backed features shippable now:
1. Auth/session/profile:
   - `signIn`, `createAccount`, `hydrateSession`, `signOut`, password APIs, agreements: `SDK_INTERFACE.md:L327-L370`.
   - Noom has sign-in/sign-up forms wired to `sensorBio.signIn` and `sensorBio.createAccount` (`NoomApp/NoomApp/SignInFormState.swift:L33-L53`, `NoomApp/NoomApp/SignUpFormState.swift:L68-L108`).
   - Must add `hydrateSession` before claiming shippable cold relaunch support.
2. Band setup and BLE lifecycle:
   - v0.12 device APIs: `startScan`, `stopScan`, `connect`, `disconnect`, `removeDeviceFromPairedDevices`, `persistPairedDevice`, `clearPairedDevice`, `userLED`, `setAskForDeviceResponse`: `SDK_INTERFACE.md:L374-L424`.
   - Noom already has scan/connect/confirm states (`NoomApp/NoomApp/PairDeviceState.swift:L39-L90`, `L98-L149`) but must migrate old persistence calls to v0.12 APIs.
3. Paired/live/device status:
   - Observable state includes `pairedDevice`, `haveDevice`, `connected`, `isFullyConfigured`, `deviceSyncing`, `percentSynced`, `lastSyncd`, `batteryLevel`, `charging`, `worn`, `buttonTaps`: `SDK_INTERFACE.md:L187-L248`.
   - Noom exposes paired-vs-live state via `NoomBandConnectionState` (`NoomApp/NoomApp/NoomBandConnectionState.swift:L3-L48`) and connection indicator (`NoomApp/NoomApp/MainTabView.swift:L56-L87`).
4. Automatic sync:
   - Sync runs automatically on paired-device connect; no app-side manual sync trigger: `SDK_INTERFACE.md:L525-L528`.
   - Noom watches `lastSyncd` and refreshes today's dashboard after sync (`NoomApp/NoomApp/DashboardView.swift:L59-L67`).
5. Dashboard + body-state foundation:
   - `fetchDashboardData(date:tzOffset:)`: `SDK_INTERFACE.md:L537-L541`.
   - Recovery score/body-state inputs are SDK-backed through `fetchDailyRecovery`, `fetchRangeRecovery`, and recovery factor models: `SDK_INTERFACE.md:L571-L610`.
   - Noom's only shippable Body State is Recovery, because it is already returned by the SDK and displayed by Noom (`NoomApp/NoomApp/DashboardView.swift:L40-L45`, `L72-L94`; `NoomApp/NoomApp/RecoveryDetailView.swift`).
6. Sleep/recovery/steps/calories/HR/HRV/RR details:
   - SDK reads: `SDK_INTERFACE.md:L543-L632`.
   - Noom has detail view files but not all visible routes; restore routes before claiming parity.
7. Personal insights seed:
   - SDK exposes `fetchNewInsights`: `SDK_INTERFACE.md:L634-L643`.
   - Noom displays recommendations, predictions, influencers, and `suggestedExperiment` reason if present (`NoomApp/NoomApp/InsightsView.swift:L64-L91`). This is a seed/display only, not lifecycle ownership.

Features not shippable from iOS alone:
1. Persisted suggested-experiment lifecycle.
   - Existing proto has an older `ExperimentStatus` shape (`EXP_NOT_STARTED`, `EXP_IN_PROGRESS`, `EXP_ABANDONED`, `EXP_COMPLETED`) and experiment method/recommendation objects (`mobile_grpc_protos/proto/experiments.proto:L11-L59`).
   - Noom needs a stricter lifecycle: `proposed -> active -> completed | cancelled`, explicit user acceptance, one active experiment, audit/versioning, idempotent transitions, server timestamps, and source insight ID.
   - iOS must not invent this with `UserDefaults`, SwiftData, or local files.
2. Progress-signal time series.
   - Existing SDK gives processed sleep/recovery/activity/biometric reads and recovery factors (`SDK_INTERFACE.md:L543-L632`), but not a Noom product-loop progress contract tying experiment adherence to sleep/recovery movement.
   - Backend must provide versioned time series with `source`, `date`, `coverage`, `algorithmVersion`, `metricWindow`, and no causal claims.
3. Settings and notifications.
   - Backend tree has likely owners (`api/mobile/in_app_notifications.go`, `api/mobile/user_custom_settings.go`, `api/webdashboard/push_notifications.go`; proto has `svc_in_app_notifications.proto`, `svc_user.proto`), but availability must be verified in backend card.
   - iOS should only register device/preferences if existing infrastructure supports it.
4. GLP-1, appetite, nausea, care-team notes, coaching plans, medication/dosing support.
   - Current Noom WIP has fake/static UI for these (`NoomApp/NoomApp/NoomProductScreens.swift:L46-L89`, `L152-L224`). Remove or feature-gate until Noom/backend product contracts exist. No medication dosing, appetite, GLP-1 efficacy, clinical causality, raw PPG org exposure, composite health score, or AI coach.

Architecture:

1. iOS app boundary
   - Owns Noom UX, navigation, copy, feature gating, and presentation transforms.
   - Talks only to `sensorBio` public SDK and future documented backend/SDK contracts.
   - Does not call SDK internals or backend endpoints directly unless SDK/API contract explicitly says so.
   - Does not persist product-loop truth locally except short-lived UI state/cache.

2. SensorBioSDK boundary
   - Owns auth, session hydration, BLE pairing/connection/sync, processed dashboard/detail reads, personal insights, population insights, profile, goals, and workout/recording APIs.
   - Exposes Combine state and async methods documented in `SDK_INTERFACE.md`.
   - Owns paired-device persistence in v0.12 (`SDK_INTERFACE.md:L381-L407`).

3. Backend boundary
   - `server_svc_core_api_monolith`: source of truth for experiment lifecycle, progress signals, notification/settings persistence, authorization, audit/versioning, and any generated API implementation.
   - `mobile_grpc_protos`: versioned mobile contracts. Add proto messages/RPCs here before SDK/iOS consumption.
   - `infrastructure`: only if migrations/deploy/IaC changes are needed.
   - `web_platform`: only for internal/admin visibility, support/debug views, or operator-facing controls.

Data flow:
1. Sensor Band syncs via SDK.
2. SDK surfaces processed dashboard/detail reads: sleep, recovery, steps, calories, HR, HRV, RR.
3. Noom computes/presents Body State from existing Recovery only. It may explain contributing sleep/resting-signal factors returned by SDK; it must not create a new composite score.
4. `fetchNewInsights()` can show a suggested experiment reason now. If the user accepts, iOS calls backend lifecycle endpoint once implemented.
5. Backend stores accepted experiment lifecycle and adherence/progress signal series.
6. Noom fetches progress signals and displays trend/progress with disclaimers: associated with sleep/recovery/adherence, no causal/medical claim.

Backend contract proposal:

A. Suggested experiment lifecycle
- Entity: `NoomSuggestedExperiment`
  - `id`: UUID/server ID
  - `userId`
  - `sourceInsightId`: `SB_NewInsights.insight_id` when available
  - `sourceGeneratedAt`
  - `sourceRecommendationText`
  - `experimentMethodId` if seeded from existing `ExperimentMethod`, otherwise nullable typed enum/string
  - `title`, `reason`, `instructions`, `expectedDurationDays`
  - `status`: `proposed | active | completed | cancelled`
  - `statusVersion`: monotonic int
  - `activeStartedAt`, `completedAt`, `cancelledAt`
  - `createdAt`, `updatedAt`
  - `audit`: actor, action, old/new status, idempotency key
- Rules:
  - Creating a proposal is idempotent by `(userId, sourceInsightId, experimentMethodId)`.
  - Accepting a proposal requires explicit user action and idempotency key.
  - One active experiment per user unless backend/product explicitly allows more.
  - Completion/cancellation only from active; proposed can be cancelled/dismissed.
  - No clinical/medication content in experiment text.

B. Progress-signal time series
- Entity: `NoomProgressSignalPoint`
  - `userId`, `experimentId?`, `date`, `tzOffset`
  - `signalType`: `recovery_score | sleep_duration | sleep_efficiency | resting_hr | hrv | adherence | coverage`
  - `value`, `unit`, `rangeMin?`, `rangeMax?`
  - `coverage`: 0..1
  - `source`: `sdk_dashboard | sdk_recovery | sdk_sleep | backend_adherence`
  - `sourceWindowStart`, `sourceWindowEnd`
  - `algorithmVersion`
  - `createdAt`
- Rules:
  - Use processed SDK/backend metrics only; no raw PPG exposure.
  - Do not infer GLP-1 efficacy, medication response, appetite causality, or treatment advice.
  - UI copy says “associated with,” “context for,” “tracked alongside,” never “caused by.”

C. Settings/notification preference
- Entity: `NoomSignalPreference`
  - `userId`
  - `dailyCheckInEnabled`, `experimentReminderEnabled`, `quietHours`, `timezone`, `pushTokenRef?`
  - `createdAt`, `updatedAt`
- Only implement if backend already supports auth/user settings and mobile push registration. Otherwise document blocker and keep iOS notification UI hidden.

Task-sized implementation sequence:

Phase 0 — freeze iOS parity before product-loop work
1. In iOS repo, preserve WIP and repair build setup.
   - Files: `NoomApp/Podfile`, generated workspace/Pods if approved, project settings if required.
   - Test: `pod install`; `xcodebuild -workspace NoomApp/NoomApp.xcworkspace -scheme NoomApp -destination 'generic/platform=iOS Simulator' build`.
   - Acceptance: import `SensorBioSDK` resolves from workspace, no project-only build assumption.
2. Add production-safe startup lifecycle.
   - Files: `NoomApp/NoomApp/NoomApp.swift`, `NoomApp/NoomApp/ContentView.swift`.
   - Change: production default outside DEBUG, DEBUG-only staging control, `sensorBio.hydrateSession()` after environment set.
   - Acceptance: cold relaunch with stored auth routes to tabs; release build cannot default to staging.
3. Migrate v0.12 paired-device persistence.
   - Files: `PairDeviceState.swift`, `ProfileView.swift`, parity tests.
   - Change: `persistPairedDevice(macAddress:name:type:)`, `clearPairedDevice()`, `removeDeviceFromPairedDevices(_:)`; stop old `persistDeviceState` calls.
   - Acceptance: pair/unpair/sign-out state flips `pairedDevice`, `haveDevice`, `connected` correctly.
4. Restore ExampleApp navigation parity.
   - Files: `DashboardView.swift`, `MainTabView.swift`, detail views, tests.
   - Change: all dashboard metrics link to detail screens; population insights restored.
   - Acceptance: parity matrix rows 28-49 pass.
5. Remove/feature-gate fake Noom product screens.
   - Files: `NoomProductScreens.swift`, `InsightsView.swift`, `ContentView.swift` QA routes.
   - Change: GLP-1/appetite/progress/coach fake screens hidden from release; only SDK-backed Recovery/Sleep/Insights remain.
   - Acceptance: no empty-action buttons or static fake status in release UI.

Phase 1 — backend contract design and proto/API skeleton
1. Clone or open `GetSensr-io/mobile_grpc_protos` in a backend-card workspace.
   - Files likely: `proto/experiments.proto`, new `proto/noom_product_loop.proto` or extension of existing experiments/new insights protos.
   - Acceptance: versioned messages for `NoomSuggestedExperiment`, `NoomProgressSignalPoint`, and preferences; no medication/GLP-1 efficacy fields.
2. Clone or open `GetSensr-io/server_svc_core_api_monolith`.
   - Files likely: `api/mobile/experiments.go`, `api/mobile/insights.go`, `api/mobile/in_app_notifications.go`, `api/mobile/user_custom_settings.go`, tests alongside.
   - Acceptance: ownership confirmed; if repo access/migrations are unavailable, block rather than fabricate APIs.
3. Add persistence/migrations.
   - Tables: experiment proposals/lifecycle, experiment audit, progress signal points, optional preferences.
   - Acceptance: migration tests, uniqueness/idempotency constraints, privacy review.
4. Add lifecycle endpoints/RPCs.
   - Endpoints/RPCs: list proposals/current, accept, complete, cancel, progress series, preferences if supported.
   - Acceptance: auth enforces user ownership; one-active-experiment invariant; idempotent retries.
5. Add progress-signal generation job/query.
   - Sources: existing processed sleep/recovery data and adherence events only.
   - Acceptance: coverage and algorithmVersion present; no causal claims; tests cover missing data.
6. Update SDK interface once backend contract exists.
   - Files: source SDK repo, binary SDK interface docs, generated protos.
   - Acceptance: public `sensorBio` facade exposes typed async methods; binary release/tag planned.

Phase 2 — iOS product-loop consumption
1. Add client-facing models/view models behind feature flag.
   - Files: new `NoomApp/NoomApp/ProductLoop/...` or equivalent.
   - Acceptance: no direct backend URL/secrets; uses SDK/public API only.
2. Replace `NoomProgressSignalsView` static bars with real progress points.
   - Files: `NoomProductScreens.swift` or split views.
   - Acceptance: empty/loading/error/partial coverage states; no fake values.
3. Add accept/active/completed/cancelled experiment UI.
   - Acceptance: explicit user acceptance, no local-only truth, idempotent button handling.
4. Add notification/settings UI only if backend confirms support.
   - Acceptance: hidden when unsupported; no orphan buttons.
5. Add route screenshots + tests.
   - Acceptance: scanner passes, parity tests pass, build passes, simulator route screenshots refreshed.

Test plan:
- Python static/parity tests:
  - `python3 docs/qa/noom_ios_scan.py --repo-root . --json`
  - `python3 -m unittest docs/qa/test_noom_auth_routing.py docs/qa/test_noom_band_state.py`
  - Add tests for `hydrateSession`, no `persistDeviceState`, password reset implementation/removal, all detail route reachability, no fake product-loop UI in release.
- iOS build:
  - `cd NoomApp && pod install`
  - `xcodebuild -workspace NoomApp.xcworkspace -scheme NoomApp -destination 'generic/platform=iOS Simulator' build`
- Simulator routes:
  - signed-out home, sign-in, sign-up, dashboard empty/default, profile no-device, pair setup/scanning, paired-connected, paired-disconnected, sleep detail, recovery detail, steps/calories/HR/HRV/RR detail, insights personal/population, product loop feature-gated states.
- Backend tests:
  - lifecycle transition table tests.
  - idempotency tests.
  - one-active-experiment invariant tests.
  - auth/authorization tests.
  - no raw PPG/no medication/no GLP-1-efficacy field tests.
  - migration rollback/sanitized fixture tests.

Acceptance criteria for architecture card completion:
- `docs/plans/noom-exampleapp-parity.md` exists and gives exact pass/partial/fail count.
- `docs/plans/noom-product-loop-build.md` exists and separates SDK-backed shippable features from backend-required features and unsupported removals.
- Real backend repos are identified without secrets.
- No product code is implemented on this card.
- Checks run and results recorded.

Open blockers / decisions for child cards:
1. Backend card must verify database tech, migration framework, auth middleware, and deployment policy inside `server_svc_core_api_monolith` before coding.
2. Product owner must approve copy/legal boundaries for Noom experiment/progress language.
3. If SDK facade cannot expose new backend contracts quickly, decide whether iOS calls a documented public API directly or waits for SDK release. Default recommendation: SDK/public typed contract, not ad hoc direct HTTP.
4. Production deployment is not approved by this card. Staging deploy only if existing work-scoped policy and credentials support it.
