# Noom iOS White-Label Design Integration Goal

## `/goal` entrypoint

Use this short prompt to launch the work:

```text
/goal Read and execute the workflow in /Users/anton/mobile_sensorbio_sdk_ios_binary/docs/goals/noom-ios-design-integration-goal.md. Integrate the approved Noom white-label design into the SensorBio iOS ExampleApp, preserve functional SDK flows, verify the app builds/runs in iOS Simulator, capture screenshots, run copy/security scans, and draft the reusable Hermes skill from what worked. Run the work in parallel where file scopes are safe, with at most 3 active lanes.
```

## Mission

Integrate the new Noom white-label mobile design into the SensorBio iOS ExampleApp, verify it builds and runs in iOS Simulator, test core functionality, and capture the repeatable workflow as a future Hermes skill.

This is not a cosmetic pass. The output must be a working iOS app shell backed by real build/simulator evidence.

## Context

- Repo: `/Users/anton/mobile_sensorbio_sdk_ios_binary`
- iOS app workspace: `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp.xcworkspace`
- Main app folder: `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp`
- New Noom mockups: `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/mockups/noom-mobile-mockups/`
- Brand source: `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/brand/noom-brand.md`
- Existing implementation plan: `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/plans/noom-whitelabel-sensorbio-app.md`

Verified local stack:

- Xcode `26.6`
- Swift `6.3.3`
- CocoaPods `1.17.0`
- iOS Simulator `26.5`
- Existing simulator device: `Hermes-iPhone-17-iOS-26-5`
- Existing simulator UDID: `BB18392D-C7DC-46F0-BA4C-60FE64D3320D`

Baseline build flow:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp
pod install
xcodebuild \
  -workspace ExampleApp.xcworkspace \
  -scheme ExampleApp \
  -destination "platform=iOS Simulator,name=Hermes-iPhone-17-iOS-26-5" \
  -configuration Debug \
  -derivedDataPath /tmp/hermes-ios-dd \
  build
```

Baseline simulator flow:

```bash
UDID="BB18392D-C7DC-46F0-BA4C-60FE64D3320D"
APP="/tmp/hermes-ios-dd/Build/Products/Debug-iphonesimulator/ExampleApp.app"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")

xcrun simctl boot "$UDID" 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE"
xcrun simctl io "$UDID" screenshot /tmp/noom_ios_sim_screenshot.png
```

## Product direction

Build a premium Noom-white-labeled health app shell powered internally by SensorBio.

The visible product should feel like:

- Noom behavior change and weight care
- Oura-level calm health design
- WHOOP-style daily coaching
- Superpower-style premium health intelligence
- GLP-1 support/tracking where appropriate
- Noom Band setup and recovery context

SensorBio stays internal. The user should never feel like they are inside an SDK demo.

## Hard brand constraints

### Must not appear in visible user-facing UI

- `SensorBio`
- `Sensor Bio`
- `SDK Example`
- `SDK demo`
- `SB_`
- developer/demo language

Internal code references may remain where required for SDK integration, but must not leak into visible UI.

### Required visible naming

- Device name must be exactly `Noom Band`.

### Logo treatment

- Use official Noom Brandfetch logo asset where available.
- Logo artwork: black `#191717`.
- Logo placement: white rounded plate/background.

### Brand tokens

- Noom red: `#FB513B`
- Warm surface: `#F6F4EE`
- Deep teal/ink: `#1D3A44`
- Logo black: `#191717`

### Typography direction

- Major headings: `Untitled Serif` or closest available iOS serif.
- Body/UI: `Untitled Sans` or closest available iOS sans.
- Labels/buttons: `BrownLLWeb` style or closest available rounded/label treatment.

### Voice

Use copy that is:

- confident
- measured
- empowering
- factual

Avoid copy that is:

- cutesy
- hard sell
- shame-based
- alarmist
- over-medicalized
- fake-precise

Do not use em dashes or en dashes in visible copy.

## Parallel execution model

Run at most 3 lanes in parallel.

Do not let two writers edit the same Swift files at the same time. If file scopes collide, serialize the work.

Recommended lane structure:

1. Lane A: iOS design system and app shell
2. Lane B: product flows and SDK wiring
3. Lane C: build, simulator, QA, and scans
4. Lane D: skill capture and workflow documentation

Lane D can run after the first verification pass has enough evidence.

## Pre-flight gate

Before edits, run:

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
git status --short
git branch --show-current

cd /Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp
pod install
xcodebuild -list -workspace ExampleApp.xcworkspace
xcrun simctl list devices available | grep -E "Hermes-iPhone|iPhone" | head -20
```

Acceptance criteria:

- Workspace exists.
- Scheme `ExampleApp` is available.
- CocoaPods install succeeds.
- Simulator target is available or a replacement simulator is created.
- Dirty git state is understood before editing.

## Lane A: iOS design system and app shell

### Goal

Create the Noom visual foundation and replace the visible SDK-demo shell with a Noom-branded consumer app shell.

### Tasks

1. Inspect existing SwiftUI app structure.
2. Decide the cleanest integration point.
3. Create reusable Noom design primitives:
   - colors
   - typography helpers
   - cards
   - metric rows
   - CTA buttons
   - logo plate
4. Replace the visible `SDK Example` entry screen with a polished Noom home/dashboard shell.
5. Ensure visible copy uses Noom language and `Noom Band`.
6. Keep SensorBio imports and internal SDK calls intact but invisible.

### Acceptance criteria

- App launch screen is consumer-facing and Noom-branded.
- No visible SDK-demo language.
- Design resembles the approved mockups.
- Swift code is organized and reusable.
- No giant one-file view dump unless explicitly justified.

## Lane B: product flows and SDK wiring

### Goal

Preserve and adapt existing SDK functionality into Noom product flows.

### Tasks

1. Map current app flows:
   - auth/sign in/create account
   - environment selection
   - pairing
   - scan/connect/pairing confirmation
   - persisted device state
   - dashboard/session hydration
2. Adapt pairing UX into `Noom Band setup`.
3. Preserve the underlying SensorBio pairing behavior:
   - `startScan`
   - `deviceDiscovered`
   - `connect(pairing: true)`
   - `pairingConnection`
   - blink/confirm on device
   - `setAskForDeviceResponse(true)`
   - persist device state
   - disconnect
4. Add or shape screens for:
   - Today / Weight Care Plan
   - Noom Band setup
   - GLP-1 Check-in
   - Sleep & Recovery
   - Progress Signals
   - Coach Plan
5. Use mock/sample data where real backend/device data is unavailable, but make mock boundaries obvious in code, not in visible UI.

### Acceptance criteria

- Existing SDK flows still compile.
- Pairing entrypoint is still reachable.
- Simulator can navigate the Noom shell without crashing.
- BLE hardware limitations are documented separately, not treated as simulator failure.

## Lane C: build, simulator, QA, and scans

### Goal

Prove the app works in a real iOS Simulator and catch visual/copy regressions.

### Tasks

1. Run `pod install`.
2. Build the workspace with `xcodebuild` for iOS Simulator.
3. Boot or create an iPhone simulator if needed.
4. Install and launch the built app.
5. Capture screenshots of the main screens.
6. Run forbidden-copy scans across Swift, plist, markdown, and generated UI assets.
7. Verify required allowed language appears.
8. Inspect `Info.plist`.
9. Run visual QA on simulator screenshots.

### Required forbidden scan terms

```text
SensorBio
Sensor Bio
SDK Example
SDK demo
SB_
—
–
Bearer
BRANDFETCH_API_KEY
```

### Required allowed language checks

```text
Noom Band
GLP-1
Weight Care
Sleep
Recovery
Coach
```

### Suggested scan command

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
python3 - <<'PY'
from pathlib import Path
terms = [
    'SensorBio', 'Sensor Bio', 'SDK Example', 'SDK demo', 'SB_',
    '—', '–', 'Bearer', 'BRANDFETCH_API_KEY'
]
roots = [Path('ExampleApp/ExampleApp'), Path('docs/mockups/noom-mobile-mockups')]
for term in terms:
    hits = []
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob('*'):
            if p.is_file() and p.suffix.lower() in {'.swift', '.plist', '.md', '.html', '.json', '.svg'}:
                try:
                    text = p.read_text(errors='ignore')
                except Exception:
                    continue
                if term in text:
                    hits.append(str(p))
    print(f'{term}: {len(hits)}')
    for h in hits[:20]:
        print(f'  {h}')
PY
```

Important: internal SDK references may appear in Swift source where required. The QA report must distinguish internal implementation references from visible UI strings.

### Build acceptance criteria

- `xcodebuild` returns `BUILD SUCCEEDED`.
- App installs into Simulator.
- App launches in Simulator.
- Screenshot files exist.
- No crash on launch.

### Visual QA acceptance criteria

- Logo is black on white plate.
- Typography hierarchy is clear.
- No clipped text.
- No oversized hero-title problem.
- No generic AI gradient slop.
- No visible SensorBio branding.
- Primary flows are reachable.

## Lane D: skill capture and workflow documentation

### Goal

Turn the successful process into a reusable Hermes skill draft.

### Output path

Create or update:

```text
docs/skills/noom-ios-whitelabel-integration-skill-draft.md
```

### Include

1. Trigger conditions.
2. Repo assumptions.
3. Parallel lane structure.
4. Build/test commands that worked.
5. Simulator commands that worked.
6. Visual QA checklist.
7. Copy/security scan checklist.
8. Acceptance criteria.
9. Known blockers and recovery steps.
10. Notes on what failed or wasted time.

### Pitfalls to capture

- `xcode-select` pointing at Command Line Tools instead of full Xcode.
- Simulator runtime unavailable or device missing.
- CocoaPods `post_install` flags required for this SDK.
- BLE cannot be fully tested in Simulator.
- Visible white-label copy must not leak SensorBio branding.
- Brandfetch secrets must never be written, logged, or summarized.

## Execution rules

- Start with pre-flight.
- Commit nothing unless explicitly instructed.
- Do not change external accounts, backend config, or production settings.
- Do not expose secrets.
- Prefer minimal, reversible SwiftUI changes.
- Keep SensorBio as internal infrastructure only.
- If the app cannot build, stop design work and fix the build first.
- If simulator launch fails, report the exact simulator/runtime blocker and keep build verification separate from launch verification.
- If visual QA fails, create a precise punch list and fix the top issues before reporting done.
- Use parallelism only where file scopes are disjoint.

## Final report format

Return a concise report with:

1. Files changed.
2. Screens implemented.
3. Build command and result.
4. Simulator launch result.
5. Screenshot paths.
6. Forbidden-copy scan result.
7. Functional flows verified.
8. Known limitations, especially BLE hardware testing.
9. Skill draft path.
10. Recommended next step.

## Definition of done

Done means all of this is true:

- Noom-branded app shell is implemented.
- Existing SDK functionality is preserved or clearly marked as blocked.
- Build succeeds from workspace.
- App launches in iOS Simulator.
- Screenshots prove the rendered UI.
- Copy/security scans ran.
- Visual QA ran on actual simulator screenshots.
- Skill draft exists.
- Final report separates fixed, verified, and blocked items.
