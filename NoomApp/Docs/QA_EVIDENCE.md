# NoomPlus QA Evidence

Last updated: 2026-07-11

## Release candidate

- Product: NoomPlus / NOOM+
- Version: 1.0
- Build: 19
- Bundle ID: `ai.sensr.example.NoomApp`
- Workspace: `NoomApp.xcworkspace`
- Scheme: `NoomApp`
- Export compliance declaration: `ITSAppUsesNonExemptEncryption = false`

## Task ledger

| Scope | State | Evidence |
|---|---|---|
| SDK background-sync parity audit | Verified | `bluetooth-central`; SDK-owned BLE/sync lifecycle documented in `README.md` |
| Compact real sync progress | Implemented | `BandBatteryBadge` uses SDK `deviceSyncing` and `percentSynced` |
| Immediate post-sync dashboard refresh | Verified by contract | `test_noom_sync_experience.py`; forced remote dashboard/sleep/range fetches |
| First-night sleep and missing-metric states | Verified by contract and screenshot | `test_noom_sync_experience.py`; `/tmp/noomplus-qa-features/feature-montage.jpg` |
| Contextual loading system | Verified by contract and screenshot | `test_noom_loading_experience.py`; feature montage |
| Shared date navigator | Verified by contract and screenshot | `test_noom_date_navigator_consistency.py`; feature montage |
| Responsive auth layouts | Verified on three Simulator sizes | `test_noom_auth_responsive_layout.py`; `/tmp/noomplus-qa-auth/auth-montage-v2.jpg` |
| Physical BLE and background behavior | Pending device | `xcrun devicectl list devices` returned no connected iPhone |

## Automated gates

- iOS source contracts: **90/90 passed**
- Backend TypeScript check: **passed**
- Backend tests: **3/3 passed**
- `git diff --check`: **passed**
- Debug Simulator build: **passed**
- Release archive: **passed** (`/tmp/NoomPlus-TestFlight-build19.xcarchive`)
- Release executable scan: **passed**; Debug QA and staging-switch strings absent
- App Store Connect IPA export: **passed** (`/tmp/noomplus-build19-export/NoomApp.ipa`)
- Exported IPA signing verification: **passed**
- Exported IPA SHA-256: `79c32204f46455d4aca06c947677eeef079e3368208bae23caf76ac72895d0c3`
- Independent uncommitted-diff review: **passed**; no actionable correctness issue identified
- Static visual review: **no release-blocking defect** across iPhone SE, iPhone 17 Pro, and iPhone 17 Pro Max auth layouts
- Feature visual review: **no release-blocking defect** for loading, date navigation, and first-night states

## Simulator evidence

Auth routes captured on:

- Hermes-Noom-Audit-SE
- Hermes-SensorBio-iPhone-17-Pro
- iPhone 17 Pro Max

Routes:

- `signedout_home`
- `signin_preview`
- `signup`

Feature routes captured on iPhone 17 Pro:

- `loading_metric_preview`
- `loading_dashboard_preview`
- `loading_sleep_preview`
- `date_navigator_preview`
- `sleep_empty_preview`
- `dashboard_no_sleep_preview`

Debug QA routes use production components and are wrapped in `#if DEBUG`.

## Remaining release gates

- [x] Final Release archive succeeds
- [x] Final Release executable contains no Debug QA route or staging-switch strings
- [x] Final App Store Connect export succeeds
- [ ] Upload succeeds
- [ ] App Store Connect processing completes
- [ ] Build 19 is assigned to intended TestFlight groups
- [ ] Beta App Review state is confirmed
- [ ] Physical iPhone BLE/background/sleep matrix is executed when a device is available
