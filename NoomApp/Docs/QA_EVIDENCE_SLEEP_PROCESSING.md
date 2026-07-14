# Noom+ Sleep Processing QA Evidence

**Branch:** `feature/noom-rock-solid-sleep`
**Base:** Build 28 (`cfc4f469eca5bc21112785ef4fc24eb468b706ea7`)
**Date:** 2026-07-13

## Evidence ledger

| Gate | Status | Artifact / command | Notes |
|---|---:|---|---|
| Initial native RED | Captured | `/private/tmp/noom-rock-solid-sleep-focused-red.xcresult` | Missing root journey state/coordinator symbols; accepted pre-implementation RED. |
| Architecture RED | Captured | `/private/tmp/noom-rock-solid-sleep-source-red-v2.log` | 14 source contracts intentionally failed before root ownership/migration. |
| Architecture GREEN | Passed | `python3 -m unittest docs.qa.test_noom_sleep_processing_architecture -v` | 14/14 after final coordinator implementation and root account/date rebinding. |
| Visual route RED | Captured | `/private/tmp/noom-rock-solid-sleep-visual-red.log` | DEBUG lifecycle matrix absent. |
| Visual route GREEN | Passed | `python3 -m unittest docs.qa.test_noom_sleep_processing_visuals -v` | 4/4 final DEBUG route/shared-component/capture-script contracts. |
| Focused native sleep suites | Passed | `/private/tmp/noom-sleep-final-focused.xcresult` | Final tree: 62/62 across domain (15), processing state (11), journey reducer (21), and coordinator/effects (15, incl. back-to-back account/day metadata-restore regression). |
| Coordinator/effects RED | Captured | `/private/tmp/noom-rock-solid-sleep-coordinator-red2.xcresult` | Test-first notification/dependency API absent before implementation. |
| Coordinator/effects GREEN | Passed | `/private/tmp/noom-sleep-cg3.xcresult` | 14/14; exact stale guards, bounded retries/deadline, protected metadata, background resume, notification dedupe, explicit retry, multiple candidates. |
| Full XCTest suite | Passed | `/private/tmp/noom-sleep-final-full.xcresult` | Final tree after cleanup-serialization + reconciliation-generation hardening: 83/83; expected unsigned-Keychain diagnostics only. |
| Full Python source contracts | Passed | `/private/tmp/noom-sleep-final-contracts.log` | Final tree: 153/153. |
| XcodeGen reproducibility | Passed | `xcodegen generate --spec project.yml` | Exit 0; post-generation `pod install` and scheme repair ran; regenerated project then passed full XCTest and Release. |
| Debug build | Passed | `/private/tmp/noom-rock-solid-sleep-debug-build-after-a11y-label.log` | Final accessibility implementation on dedicated iOS 26.5 simulator, signing disabled. |
| Release build | Passed | `/private/tmp/noom-sleep-final-release.log` | Final tree; exact fixture namespace scan returned 0 matches. |
| Simulator visual matrix | Passed | `/private/tmp/noom-rock-solid-sleep-screens/` | 11/11 DEBUG routes captured and inspected at full resolution; no crash/blank/clipping; truthful pending, terminal, stale, history, and picker states. |
| VoiceOver/Dynamic Type | Passed | `/private/tmp/noom-rock-solid-sleep-screens-axxxl/` + Appium | At `accessibility-extra-extra-extra-large`: 3-page scroll confirmed; retry ID/label visible after scroll and tappable; picker visible/hittable with both choices and Selected trait; pending banner announces Jul 12 source vs Jul 13 pending. Fixed swallowed retry ID and doubled spoken punctuation. |
| Independent spec review | Passed | fresh-context report, 2026-07-13 | 6/6 invariants PASS with line citations; no HIGH defects. Informational: `lastCompleted` intentionally not restored from envelope; OS replaces (not stacks) the deterministic notification identifier. |
| Independent quality/security/privacy review | Passed | fresh-context report, 2026-07-13 | No HIGH findings. Keychain envelope lifecycle-only, SHA-256 namespace, ThisDeviceOnly + non-synchronizable; actor-safe sinks; serialized cleanup/save tasks. Low notes: in-memory reuse of `accountScopeHash` field name; best-effort `try?` on metadata deliver/save/clear. |
| Physical Band/iPhone | **Not verified** | `Docs/SLEEP_WAKE_QA.md` | Required before physical/TestFlight-ready/“instant” claims. |
| TestFlight | **Not verified** | App Store Connect build record | Not part of Simulator evidence. |

## Required final assertions

- Only `SleepProcessingCoordinator` subscribes to SDK sleep lifecycle events and fetches exact daily detail.
- Identity-free `sleepStored`/`sleepUploaded` events trigger reconciliation but never bind a candidate.
- Every response is guarded by account, local day, exact session identity, and request generation.
- A newer pending session cannot erase the dated previous completion.
- Body Status receives one typed-success snapshot only and never mixes a current-date signal with an older sleep result.
- Polling is finite in foreground, single-attempt in background, cancellation-aware, and foreground-resumable.
- Protected persistence contains no SDK detail or health values and uses a hashed account namespace.
- Notification permission is inspected, never requested by the sleep pipeline; duplicates are suppressed and account cleanup removes pending/delivered items.
- DEBUG synthetic state and route strings are absent from the Release binary.
