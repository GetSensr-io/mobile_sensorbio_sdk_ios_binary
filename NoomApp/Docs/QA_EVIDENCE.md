# Noom+ Build 30 QA Evidence

Last updated: 2026-07-14

## Release candidate identity

- Product: Noom+ / NOOM+
- Version: 1.0
- Build: 30
- Bundle ID: `ai.sensr.example.NoomApp`
- Workspace: `NoomApp.xcworkspace`
- Scheme: `NoomApp`
- Branch: `fix/noom-metric-parity`
- Base: build-29 commit `1532888722f7b046fa01313838fca46e07abc96a`
- Export compliance: `ITSAppUsesNonExemptEncryption = false`
- Release startup: production SensorBioSDK configuration only

## Build 30 scope

| Scope | State | Evidence |
|---|---|---|
| Dashboard/detail primary-value parity | Implemented | `DashboardMetricRouteSnapshot` and `MetricDisplayPolicy` |
| Steps | Same routed value, `steps`, missing state, and source day | Focused XCTest + route contracts |
| Active Calories | Same routed value, `kcal`, missing state, and source day | Focused XCTest + route contracts |
| Resting Heart Rate | Float/integer fallback with canonical `bpm` | Focused XCTest + route contracts |
| Heart Rate Variability | Float/integer fallback with canonical `ms` | Focused XCTest + route contracts |
| Respiratory Rate | Fractional value preserved; canonical `/min` | Focused XCTest + route contracts |
| Invalid values | NaN, infinity, negative, and dashboard-zero sentinels remain unavailable | `MetricDisplayPolicyTests` |
| Detail-only activity zero | Explicit Steps/Calories detail zero remains valid | `MetricDisplayPolicyTests` |
| Historical context | Route snapshot is reused only for the same local day; historical copy says selected day | XCTest + source contracts |
| Ancillary loading/errors | Same-day routed value or explicit missing state remains primary; loading/failure is secondary context | Route-resolution XCTest + five-view contracts |
| Build-29 sleep/recording/freshness guarantees | Preserved | Full XCTest and Python contract suites |

## TDD evidence

- Route contracts were observed failing before the shared presentation policy and destination injection existed.
- Focused XCTest was observed failing before `MetricDisplayPolicy` existed.
- A missing dashboard route was observed incorrectly becoming available from a detail fallback; the new same-day missing-state regression failed before `DashboardMetricRouteSnapshot` was implemented.
- The historical-detail copy regression failed while the shared detail surface still said “Today’s readings.”
- Same-day route-state contracts failed while loading/error branches could hide a routed value and while a missing calorie tile could fall through to an available detail list.
- Footer-copy contracts failed while a valid tile without a footer inherited missing-data text.
- Focused final result: **12/12 `MetricDisplayPolicyTests` passed**.

## Automated gates

- iOS XCTest suite: **159/159 passed**.
- Python QA/source contracts: **172/172 passed**.
- Debug Simulator build: **passed** as part of the XCTest run.
- Release Simulator build: **passed**.
- Generated Xcode project: regenerated from `project.yml`; CocoaPods integration completed.
- Release Simulator metadata: bundle `ai.sensr.example.NoomApp`, version `1.0`, build `30`, non-exempt encryption `false`.
- Release Simulator executable scan: zero occurrences of the checked Debug route/host strings and staging-environment marker.
- `git diff --check`: **passed** on the frozen candidate.
- Independent reviews: the active-series selection P2, same-day loading/error continuity finding, explicit missing-calorie fallthrough, and no-footer caption conflict were all resolved with regressions before this freeze.

Known non-blocking warnings are inherited from dependencies or pre-existing source: CocoaPods header-symlink scripts without outputs, a Swift-6 future exhaustiveness warning in recording code while the app builds in Swift 5 mode, an unreachable existing switch case, a simulator Metal-toolchain search-path warning, and skipped AppIntents metadata because the app does not link AppIntents.

## Delivery gates

- [ ] Release commit created and pushed
- [ ] Device Release archive succeeds
- [ ] Archived identity/build/signature/provisioning metadata matches this candidate
- [ ] Archived executable contains no checked Debug route/fixture or staging strings
- [ ] IPA exports and matches archived identity
- [ ] App Store Connect upload succeeds
- [ ] Apple begins processing build 30
- [ ] Build 30 becomes available to test
- [ ] Intended TestFlight tester group assignment is verified if accessible

## Physical-device boundary

Software and Simulator verification do **not** establish physical Sensor Bio v2 wake behavior, background BLE delivery, recording continuity, sensor accuracy, or backend processing latency. Those remain unverified until the exact reviewed build is exercised on a physical iPhone and Band with redacted logs.
