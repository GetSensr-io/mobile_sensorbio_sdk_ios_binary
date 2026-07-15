# Noom+ Build 31 QA Evidence

Last updated: 2026-07-14

## Release candidate identity

- Product: Noom+ / NOOM+
- Version: 1.0
- Build: 31
- Bundle ID: `ai.sensr.example.NoomApp`
- Workspace: `NoomApp.xcworkspace`
- Scheme: `NoomApp`
- Branch: `fix/noom-metric-parity`
- Base: build-30 commit `9eb1674296efb7a11ea2ea143bb6d09dfb48f86a`
- Chart polish: `8b603dca4bab16c62ce1c8331365df8e60fa26f7`
- Export compliance: `ITSAppUsesNonExemptEncryption = false`
- Release startup: production SensorBioSDK configuration only

## Build 31 scope

| Scope | State | Evidence |
|---|---|---|
| Build 30 dashboard/detail metric parity | Preserved | Shared `MetricDisplayPolicy` + route snapshots |
| Population Insights bar gaps | Implemented | Histogram bars inset ~10% for visible gaps |
| HRV display window | Implemented | Max x-axis clamp **150** hides long outlier tails |
| Resting HR display window | Implemented | Max x-axis clamp **90** |
| Total sleep display window | Implemented | Min x-axis clamp **3 hours** |
| “You” marker clearance | Implemented | Top plot padding so capsule does not overlap axis/insight text |

### What changed (user feedback)

| Feedback | Change |
|---|---|
| Bars look glued together | Slightly narrower bars with a small gap |
| HRV bell curve distorted by outliers | Clamp distribution display to ≤ 150 ms |
| Resting HR range too wide | Clamp display to ≤ 90 bpm |
| Sleep includes unrealistically low totals | Start display window at ≥ 3 h |
| “You” overlaps axis/insight words | Move plot down with top padding |

## Automated gates

- Focused insights contracts: **14/14 passed**
- Full Python QA suite: **173/173 passed**
- Full XCTest suite: **159/159 passed**
- Release Simulator build: **passed**
- Generated Xcode project: regenerated from `project.yml`
- Release Simulator metadata: bundle `ai.sensr.example.NoomApp`, version `1.0`, build `31`, non-exempt encryption `false`
- Release Simulator executable scan: zero checked Debug route/host/staging strings
- Export compliance: `false`

## Delivery gates

- [ ] Release commit created and pushed
- [ ] Device Release archive succeeds
- [ ] Archived identity/build matches build 31
- [ ] Archived/IPA executable has no Debug fixture/staging strings
- [ ] App Store Connect upload succeeds
- [ ] Apple begins processing build 31
- [ ] Build 31 becomes available to test

## Physical-device boundary

Software/simulator verified; physical wake, background BLE delivery, and backend latency unverified.
