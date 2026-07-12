# NoomPlus QA Evidence

Last updated: 2026-07-11

## Release candidate

- Product: NoomPlus / NOOM+
- Version: 1.0
- Build: 20
- Bundle ID: `ai.sensr.example.NoomApp`
- Workspace: `NoomApp.xcworkspace`
- Scheme: `NoomApp`
- Export compliance declaration: `ITSAppUsesNonExemptEncryption = false`
- Release commit: current release candidate; remote push tracked separately

## Task ledger

| Scope | State | Evidence |
|---|---|---|
| Population insight graphs | Implemented and Simulator-verified | `42c8c37`, `a2801ae`; finite/range-safe histogram and radar contracts |
| Independent Band connection/sync/data states | Implemented and Simulator-verified | `3e54e40`; `test_noom_sync_experience.py` |
| Home tab label | Implemented and Simulator-verified | `0533f7a`; authenticated Home screenshot |
| Home floating Record action | Implemented and Simulator-verified | `DashboardView.swift`; `/tmp/noomplus-build20-main_default.png` |
| Recording hub | Implemented and Simulator-verified | `/tmp/noomplus-build20-recording_hub_preview.png` |
| Spot check | Implemented and deterministic-fixture verified | `/tmp/noomplus-build20-recording_spot_preview.png`; `test_noom_recording_experience.py` |
| Activity tracking | Implemented and deterministic-fixture verified | `/tmp/noomplus-build20-recording_activity_preview.png`; `test_noom_recording_experience.py` |
| Live PPG/HR/HRV/IBI/RR/SpO₂/SNR rendering | Implemented with finite-value guards | `RecordingExperienceView.swift`; synthetic Debug fixtures only |
| Recording persistence/finalization/error states | Implemented and contract-verified | SDK-owned active recording restoration and friendly error mapping |
| Required-reason API declaration | Implemented | App-owned `PrivacyInfo.xcprivacy` declares UserDefaults reason `CA92.1`; dependency manifests remain embedded separately |
| Physical BLE and recording continuity | Pending device | No connected physical iPhone/Noom Band available |

## Automated gates

- iOS source contracts: **114/114 passed**
- Backend TypeScript check: **passed**
- Backend tests: **3/3 passed**
- `git diff --check`: **passed**
- Debug Simulator build: **passed**
- Release Simulator build: **passed**
- Release Simulator executable Debug-fixture scan: **passed**
- App-owned privacy manifest embedding: **passed**
- Final recording visual gates: **passed** for hub, Spot check, Activity tracking, and Home Record action
- Independent final diff review: **passed** with no security concerns or logic errors
- Release archive: **pending**
- Release archive executable Debug-fixture scan: **pending**
- App Store Connect IPA export/upload: **pending**
- TestFlight processing/compliance/tester assignment: **pending**

## Simulator evidence

Simulator: `A208E85C-7453-40E3-91ED-810DEF25B54C` (`Hermes-SensorBio-iPhone-17-Pro`, iOS 26.5)

| Route | Artifact | Visual result |
|---|---|---|
| `recording_hub_preview` | `/tmp/noomplus-build20-recording_hub_preview.png` | Pass |
| `recording_spot_preview` | `/tmp/noomplus-build20-recording_spot_preview.png` | Pass |
| `recording_activity_preview` | `/tmp/noomplus-build20-recording_activity_preview.png` | Pass |
| `main_default` | `/tmp/noomplus-build20-main_default.png` | Pass |

Debug QA routes use production components and are wrapped in `#if DEBUG`. These screenshots validate layout and deterministic state presentation only; they do not establish hardware capture accuracy or continuity.

## Remaining release gates

- [x] Independent final review passes
- [ ] Verified release commit is created and pushed to `noomapp/main`
- [ ] Release archive succeeds with build 20 and production-only startup
- [ ] Archived executable contains no Debug QA route/fixture or staging-switch strings
- [ ] Archived plist contains `ITSAppUsesNonExemptEncryption = false`
- [ ] App Store Connect export/upload succeeds
- [ ] App Store Connect processing completes
- [ ] Missing Compliance is absent or cleared using the recorded Noom decision
- [ ] Build 20 is assigned to the intended TestFlight tester group
- [ ] Build 20 is installable in TestFlight
- [ ] Physical iPhone/Band recording matrix is executed when hardware is available
