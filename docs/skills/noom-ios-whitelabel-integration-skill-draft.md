---
name: noom-ios-whitelabel-integration
description: Use when integrating a Noom white-label design into the SensorBio iOS NoomApp while preserving SDK flows, simulator verification, copy/security scans, and reusable workflow capture.
version: 0.1.0
author: Hermes Agent
license: Internal draft
metadata:
  hermes:
    tags: [ios, swiftui, whitelabel, noom, sensorbio, simulator, qa]
    related_skills: [mobile-sdk-integration-analysis, test-driven-development, computer-use]
---

# Noom iOS White-Label Integration Skill Draft

## Overview

Use this procedure to convert the SensorBio iOS NoomApp from an SDK demo shell into a Noom-branded consumer health app while keeping the underlying SensorBio SDK wiring intact. The workflow is designed for parallel Hermes lanes where design, SDK flow adaptation, verification, and skill capture can proceed without file conflicts.

The final deliverable must be a working app backed by real local evidence: workspace listing, CocoaPods install, Xcode build, simulator install and launch, screenshots, and copy/security scan output.

## Trigger Conditions

Use this skill when the task includes any of these:

- Apply Noom white-label UI or copy to `NoomApp/NoomApp`.
- Preserve SensorBio SDK flows while hiding SensorBio branding from visible UI.
- Verify an iOS NoomApp through Xcode build plus iOS Simulator launch.
- Scan Swift, plist, markdown, HTML, JSON, or SVG assets for forbidden visible terms and secret markers.
- Capture screenshots for visual QA after a simulator launch.
- Coordinate parallel lanes while avoiding simultaneous edits to the same Swift files.

Do not use this skill for production backend changes, external account changes, credential management, or non-local API work.

## Assumptions

Default repository context:

```bash
REPO="/Users/anton/mobile_sensorbio_sdk_ios_binary"
APP_DIR="$REPO/NoomApp"
WORKSPACE="$APP_DIR/NoomApp.xcworkspace"
SCHEME="NoomApp"
DEVICE_NAME="Hermes-iPhone-17-iOS-26-5"
UDID="BB18392D-C7DC-46F0-BA4C-60FE64D3320D"
DERIVED_DATA="/tmp/hermes-ios-dd"
SCREENSHOT="/tmp/noom_ios_sim_screenshot.png"
```

Expected sources:

- Goal: `docs/goals/noom-ios-design-integration-goal.md`
- Plan: `docs/plans/noom-whitelabel-sensorbio-app.md`
- Brand reference: `docs/brand/noom-brand.md`
- Mockups: `docs/mockups/noom-mobile-mockups/`
- App code: `NoomApp/NoomApp/`
- Workspace: `NoomApp/NoomApp.xcworkspace`

## Parallel Lane Structure

Run at most three active lanes. Never let two lanes edit the same Swift file at the same time.

1. Lane A, design system and shell
   - Owns reusable SwiftUI design primitives, app shell, and launch dashboard.
   - Must preserve SDK imports and app entry points.
2. Lane B, product flows and SDK wiring
   - Owns auth, environment, pairing, device state, and Noom Band setup flow mapping.
   - Must keep existing SDK behaviors reachable.
3. Lane C, build, simulator, QA, and scans
   - Owns CocoaPods, xcodebuild, simulator boot/install/launch/screenshot, Info.plist inspection, and copy/security scans.
   - Should avoid long builds while Swift files are actively changing.
4. Lane D, skill capture and workflow documentation
   - Owns this draft and reusable procedure notes.
   - Can run in parallel once enough workflow evidence exists.

## Preflight Commands

Run these before modifying app code:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
git status --short --branch

cd /Users/anton/mobile_sensorbio_sdk_ios_binary/NoomApp
pod install
xcodebuild -list -workspace NoomApp.xcworkspace
xcrun simctl list devices available | grep -E "Hermes-iPhone|iPhone" | head -20
```

Preflight acceptance:

- Workspace exists.
- Scheme `NoomApp` appears in the workspace list.
- CocoaPods install succeeds.
- Target simulator exists or a replacement can be created.
- Dirty git state is understood before editing.

If `xcodebuild` points at Command Line Tools, recover with:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## Final Build Command

Run after Lane A and Lane B stop writing Swift files:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary/NoomApp
pod install
xcodebuild \
  -workspace NoomApp.xcworkspace \
  -scheme NoomApp \
  -destination "platform=iOS Simulator,name=Hermes-iPhone-17-iOS-26-5" \
  -configuration Debug \
  -derivedDataPath /tmp/hermes-ios-dd \
  build
```

Build acceptance:

- Command exits 0.
- Output contains `BUILD SUCCEEDED`.
- App product exists at `/tmp/hermes-ios-dd/Build/Products/Debug-iphonesimulator/NoomApp.app`.

If the named simulator is missing, list available devices:

```bash
xcrun simctl list devices available | grep -E "iPhone|Hermes"
```

Then create a replacement only if needed:

```bash
xcrun simctl create "Hermes-iPhone-17-iOS-26-5" "iPhone 17" "iOS26.5"
```

## Final Install, Launch, and Screenshot Commands

```bash
UDID="BB18392D-C7DC-46F0-BA4C-60FE64D3320D"
APP="/tmp/hermes-ios-dd/Build/Products/Debug-iphonesimulator/NoomApp.app"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")

xcrun simctl boot "$UDID" 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE"
xcrun simctl io "$UDID" screenshot /tmp/noom_ios_sim_screenshot.png
ls -lh /tmp/noom_ios_sim_screenshot.png
```

Simulator acceptance:

- Simulator boots or is already booted.
- App installs without error.
- App launch prints a process id.
- Screenshot file exists and is non-empty.
- No crash appears immediately after launch.

Optional crash check:

```bash
xcrun simctl spawn "$UDID" log show --last 2m --predicate 'process == "NoomApp"' --style compact | tail -80
```

## Copy and Security Scan

Use the deterministic local script when present:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
python3 docs/qa/noom_ios_scan.py
```

JSON output for automation:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
python3 docs/qa/noom_ios_scan.py --json > /tmp/noom_ios_scan.json
```

Strict mode for zero internal hits:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
python3 docs/qa/noom_ios_scan.py --strict-internal
```

Required forbidden terms:

```text
SensorBio
Sensor Bio
Noom App
SDK demo
SB_
—
–
Bearer
BRANDFETCH_API_KEY
```

Required allowed language:

```text
Noom Band
GLP-1
Weight Care
Sleep
Recovery
Coach
```

Important caveat: internal SensorBio SDK references in Swift implementation can be acceptable when they are not string literals and do not render in visible UI. The scan must separate internal implementation hits from visible UI or security hits. Security markers such as bearer tokens or Brandfetch key names are never acceptable in scanned files.

## Info.plist Inspection

```bash
APP="/tmp/hermes-ios-dd/Build/Products/Debug-iphonesimulator/NoomApp.app"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Print NSBluetoothAlwaysUsageDescription' "$APP/Info.plist" 2>/dev/null || true
```

Acceptance:

- Display name and visible metadata do not say SensorBio or SDK demo.
- Bluetooth usage copy is user-facing and Noom appropriate if present.
- Internal bundle identifiers may retain implementation naming if not visible to users, but note any risk.

## Visual QA Checklist

Run visual QA against actual simulator screenshots, not only mockups.

- [ ] Launch screen and first screen are Noom-branded.
- [ ] No visible SensorBio, Noom App, SDK demo, or developer/demo language.
- [ ] Device name appears as exactly `Noom Band` where relevant.
- [ ] No em dash or en dash appears in visible copy.
- [ ] Logo is black on a white rounded plate if visible.
- [ ] Noom red, warm surface, deep teal/ink, and logo black are used consistently.
- [ ] Typography hierarchy is clear and not oversized.
- [ ] Text is not clipped or overlapped on the simulator device.
- [ ] Primary flows are reachable: Today, Noom Band setup, GLP-1 Check-in, Sleep and Recovery, Progress Signals, Coach Plan.
- [ ] Simulator limitations around BLE hardware are documented as limitations, not as app failures.

## Functional QA Checklist

- [ ] App launches without crash.
- [ ] Auth or entry flow remains reachable.
- [ ] Environment selection remains reachable if still required by SDK workflow.
- [ ] Pairing entrypoint remains reachable through Noom Band setup.
- [ ] Existing SDK calls compile: scan, connect, pairing confirmation, persistence, disconnect.
- [ ] Dashboard or home state can render with mock/sample data when device or backend data is unavailable.

## Acceptance Criteria

Done means:

- `xcodebuild` returns `BUILD SUCCEEDED` from the workspace.
- App installs and launches in iOS Simulator.
- One or more screenshot files exist from the simulator.
- Copy/security scan runs locally and returns no visible forbidden terms or security markers.
- Required Noom language appears in visible assets or Swift UI strings.
- Visual QA passes or produces a precise punch list.
- BLE hardware gaps are explicitly documented.
- Skill draft is updated with what worked and what failed.
- No secrets are printed, stored, or summarized.
- No external accounts, backend config, or production settings are changed.

## Blockers and Recovery

| Blocker | Recovery |
| --- | --- |
| `xcodebuild` cannot find Xcode | Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, then `xcodebuild -version`. |
| CocoaPods install fails | Run from `NoomApp`, inspect `Podfile`, avoid changing repo-wide pod settings unless required. |
| Scheme missing | Re-run `xcodebuild -list -workspace NoomApp.xcworkspace`; open workspace metadata only if the scheme is not shared. |
| Simulator missing | List available iPhone devices and create a replacement with the same runtime. |
| Build fails during active Swift edits | Stop Lane C long build, wait for Lane A/B to stabilize, then rebuild. |
| BLE cannot be tested in Simulator | Verify pairing navigation and compile-time SDK calls, then document hardware-only validation as a blocker. |
| Visible forbidden term hit | Inspect the file and line locally, remove or rewrite the user-facing copy, then rerun the scan. |
| Internal SensorBio hit | Confirm whether it is a non-rendered implementation reference. If it is a Swift string literal or plist value, treat it as visible and fix it. |
| Security marker hit | Remove the marker or secret reference. Do not print line contents in reports. |
| Screenshot shows visual regression | Create a ranked punch list and fix the top issues before claiming done. |

## What Failed or Wasted Time in This Draft Run

- Do not run a long build while design lanes are still editing Swift files. Preflight only is enough until Swift stabilizes.
- Broad file searches from repo root include Pods and build metadata. Scans should target `NoomApp/NoomApp` and Noom mockup assets, excluding Pods, screenshots, and font binaries.
- Copy/security scans should not print matched source lines because secret markers could be adjacent to values.

## Final Report Template

```text
Files changed:
- docs/qa/noom_ios_scan.py
- docs/skills/noom-ios-whitelabel-integration-skill-draft.md

Preflight:
- git status: <summary>
- workspace schemes: NoomApp present or missing
- simulator: <UDID and state>

Build:
- command: <exact command>
- result: <BUILD SUCCEEDED or blocker>

Simulator:
- install: <result>
- launch: <result>
- screenshots: <paths>

Scan:
- command: python3 docs/qa/noom_ios_scan.py
- result: <PASS or exact counts>
- caveat: internal SDK references reviewed separately from visible UI copy

Known limitations:
- BLE hardware validation requires physical device.

Next step:
- <one concrete step>
```
