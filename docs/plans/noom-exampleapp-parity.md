# Noom ExampleApp 100% Parity Contract

Status: frozen contract + current Noom gap map. This is not product-code implementation.

Canonical sources:
- Canonical ExampleApp: `33d7a341f7d72d63669c86ce0478a9008fd8a139` (`v0.11.0`). Use citations as `git show 33d7a341f7d72d63669c86ce0478a9008fd8a139:<path>:Lx-Ly`.
- Current upstream binary repo / SDK release: `ccb317efa5866b17392472500187ec72916aace6` (`v0.12.0`, current `main`).
- Current Noom WIP app: untracked `NoomApp/` in `/Users/anton/mobile_sensorbio_sdk_ios_binary`; do not reset, stash, clean, or discard.
- Current public API docs: `SDK_INTERFACE.md` at `ccb317efa5866b17392472500187ec72916aace6`.
- Current binary Swift interface: `SensorBio/SensorBioSDK.xcframework/ios-arm64-simulator/SensorBioSDK.framework/Modules/SensorBioSDK.swiftmodule/arm64-apple-ios-simulator.swiftinterface`.

Definition of 100% support:
Every user-visible and lifecycle capability that canonical ExampleApp exposes must remain reachable in NoomApp and behave equivalently against the current v0.12 SDK. Noom may change copy, layout, styling, and IA, but it may not remove, fake, or silently neuter an ExampleApp capability. If v0.12 changed the public API, Noom must preserve the behavior using the v0.12 public replacement, not the old private/manual path.

Current parity count:
- Contract rows: 57.
- Fully passing now: 28/57.
- Partial/reachable-but-not-contract-correct: 7/57.
- Failing/not reachable/not implemented: 22/57.
- Strict green parity: 28/57. Partial rows do not count as done for child implementation.

Critical current regressions:
1. Cold session restore is missing. v0.12 docs require `sensorBio.hydrateSession()` after setting `SB_SDK.environment` (`SDK_INTERFACE.md:L134-L139`, `L339`); Noom only sets environment in `NoomApp/NoomApp/NoomApp.swift:L20-L23`.
2. Production safety is wrong. Noom registers `envIsDev = true`, which defaults every build to staging (`NoomApp/NoomApp/NoomApp.swift:L20-L22`). Customer/release builds must default to production; staging controls must be DEBUG/internal only.
3. Password reset is a visible no-op. SDK supports `requestPasswordReset(email:)` (`SDK_INTERFACE.md:L344` and swiftinterface `L11269`), but Noom's button is empty (`NoomApp/NoomApp/SignInView.swift:L99-L102`).
4. Pair persistence uses the old dictionary API. v0.12 docs say use `persistPairedDevice(macAddress:name:type:)`, `clearPairedDevice()`, and `removeDeviceFromPairedDevices(_:)` (`SDK_INTERFACE.md:L381-L407`). Noom still calls `persistDeviceState([device.id: entry])` (`NoomApp/NoomApp/PairDeviceState.swift:L134-L148`) and `persistDeviceState([:])` (`NoomApp/NoomApp/ProfileView.swift:L119-L132`).
5. Population insights are broken/unimplemented. ExampleApp loads filter list and population charts (`git show 33d7a341f7d72d63669c86ce0478a9008fd8a139:ExampleApp/ExampleApp/InsightsState.swift:L50-L80`); v0.12 still exposes this (`SDK_INTERFACE.md:L638-L642`), but current `InsightsState` only implements `loadPersonal()` (`NoomApp/NoomApp/InsightsState.swift:L11-L23`) while `InsightsView` calls missing `loadFilters()` / `loadPopulation()` (`NoomApp/NoomApp/InsightsView.swift:L40-L49`).
6. Several metric-detail paths exist as files but are no longer reachable from the visible dashboard/tab IA. ExampleApp linked all metric details from Dashboard (`git show 33d7a341f7d72d63669c86ce0478a9008fd8a139:ExampleApp/ExampleApp/DashboardView.swift:L31-L45`, `L99-L108`). Current Dashboard only renders recovery, sleep, and a filtered grid of steps/HRV without detail links (`NoomApp/NoomApp/DashboardView.swift:L97-L125`).
7. Static/fake Noom product screens are present and must be removed or feature-gated until backed by real contracts: GLP-1 check-in/appetite/care note (`NoomApp/NoomApp/NoomProductScreens.swift:L46-L89`), static progress signals (`L152-L183`), and static coach plan (`L186-L224`).
8. Current project build check fails before source-level parity compile errors because the project build cannot resolve `SensorBioSDK` without the Pods workspace/dependencies: `xcodebuild -project NoomApp/NoomApp.xcodeproj ...` returned exit 65 with `unable to resolve module dependency: 'SensorBioSDK'`.

Public SDK facts that the Noom app must obey:
- CocoaPods integration is iOS 18+, Xcode 16.3+, CocoaPods 1.16+, with C++17 and `BUILD_LIBRARY_FOR_DISTRIBUTION` post-install settings (`SDK_INTERFACE.md:L17-L40`, `L46-L51`).
- Host apps only import `SensorBioSDK`; `sensorBio` is the preferred singleton alias (`SDK_INTERFACE.md:L53-L65`, `L173-L185`).
- Required BLE plist/background modes: `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`, and `UIBackgroundModes` `bluetooth-central` (`SDK_INTERFACE.md:L67-L106`). Current Noom has these (`NoomApp/NoomApp/Info.plist:L21-L28`).
- Lifecycle: set `SB_SDK.environment`, then call `sensorBio.hydrateSession()`, then optionally subscribe to SDK logs (`SDK_INTERFACE.md:L117-L150`).
- Observable session/device/sync state: `session`, `userProfile`, `organization`, `featureFlags`, `pairedDevice`, `haveDevice`, `connected`, `isFullyConfigured`, `bluetoothAvailable`, `networkStatus`, `deviceSyncing`, `percentSynced`, `lastSyncd`, `batteryLevel`, `charging`, `worn`, `buttonTaps` (`SDK_INTERFACE.md:L187-L248`; binary swiftinterface citations include `haveDevice:L10979-L10986`, `batteryLevel:L10919-L10926`, `connected:L11015-L11022`, `percentSynced:L11151-L11158`).
- Event streams include `deviceDiscovered`, `pairingConnection`, `deviceDisconnected`, `deviceConnected`, `deviceFullyConfigured`, `deviceLinkFailed`, `subscriptionLost`, and live biometric subjects (`SDK_INTERFACE.md:L263-L294`).
- Auth: `signIn`, `createAccount`, `checkEmailAvailability`, `validateAccountRequirements`, `hydrateSession`, `signOut`, `requestPasswordReset`, `changePassword`, agreements (`SDK_INTERFACE.md:L327-L370`).
- Device control: `startScan`, `stopScan`, `connect`, `disconnect`, `removeDeviceFromPairedDevices`, `persistPairedDevice`, `clearPairedDevice`, `setAskForDeviceResponse`, `userLED`, `airplaneMode`, `reset`, `updateFirmware` (`SDK_INTERFACE.md:L374-L424`).
- Sync is automatic after a paired device connects; Noom should not invent a manual sync trigger (`SDK_INTERFACE.md:L525-L528`).
- Server reads for dashboard/activity/recovery/HR/HRV/RR/SpO2/sleep/insights/goals/workouts are SDK facade methods (`SDK_INTERFACE.md:L531-L684`). Noom should use the SDK-backed subset it actually ships and omit unsupported Noom-only claims.

Parity matrix:

| # | Capability | Canonical/source citation | Current Noom evidence | Status | Required next action |
|---|---|---|---|---|---|
| 1 | iOS 18 + CocoaPods post-install | `SDK_INTERFACE.md:L17-L40` | `NoomApp/Podfile:L1-L34` | PASS | Keep. |
| 2 | Customer release pin by tag/SHA | `SDK_INTERFACE.md:L23-L25` | `NoomApp/Podfile:L4-L13` uses local `:path => '..'` | PARTIAL | For customer/release plan, pin `v0.12.0` or exact SHA; local path ok for this WIP repo only. |
| 3 | Environment setup/switch | ExampleApp sets env from `envIsDev`: `SDKExampleApp.swift:L22`; v0.12 requires env before RPC: `SDK_INTERFACE.md:L134-L138` | `NoomApp.swift:L20-L22` defaults staging in all builds; no visible toggle found | FAIL | Production default outside DEBUG; DEBUG-only staging toggle. |
| 4 | Cold session hydration | v0.12 startup example `SDK_INTERFACE.md:L134-L139`; public API `L339` | No `hydrateSession` in Noom source | FAIL | Call `sensorBio.hydrateSession()` after env selection before rendering auth gate. |
| 5 | SDK logging bridge | v0.12 startup example `SDK_INTERFACE.md:L140-L145` | `NoomApp.swift:L32-L55` wires `SB_SDK.log` to OSLog | PASS | Keep. |
| 6 | BLE permissions/background | `SDK_INTERFACE.md:L67-L106`; ExampleApp plist `Info.plist:L21-L28` | `NoomApp/Info.plist:L21-L28` | PASS | Keep Noom copy. |
| 7 | Signed-out sign-in/sign-up routes | ExampleApp `ContentView.swift:L26-L31` | `ContentView.swift:L83-L101` | PASS | Keep. |
| 8 | Sign-in outcomes | ExampleApp `SignInFormState.swift:L34-L50`; v0.12 `SDK_INTERFACE.md:L331`, `L356-L364` | `SignInFormState.swift:L33-L53` | PASS | Keep; do not manually set session. |
| 9 | Sign-up outcomes | ExampleApp `SignUpFormState.swift:L81-L105`; v0.12 `SDK_INTERFACE.md:L332` | `SignUpFormState.swift:L68-L108` | PASS | Keep; validate against v0.12 enum shape. |
| 10 | Password reset | v0.12 `SDK_INTERFACE.md:L344`; swiftinterface `L11269` | Empty button `SignInView.swift:L99-L102` | FAIL | Implement request/reset outcome UI or remove button until implemented. |
| 11 | Email availability / account requirements | v0.12 `SDK_INTERFACE.md:L333-L336` | No current Noom calls | FAIL | Add preflight if user-visible sign-up needs duplicate/error parity. |
| 12 | Agreements | v0.12 `SDK_INTERFACE.md:L347-L350` | No current Noom agreement flow | FAIL | Add ToS/health-data gate if SDK/org requires it. |
| 13 | Profile/session data | ExampleApp `ProfileView.swift:L25-L37` | `ProfileView.swift:L30-L35` | PASS | Keep username/email; consider userProfile expansion only if ExampleApp did. |
| 14 | Safe sign-out/wipe | v0.12 says `signOut()` clears device/cache: `SDK_INTERFACE.md:L370` | Noom calls `signOut` but then manually removes device and nils session: `ProfileView.swift:L123-L135` | PARTIAL | Use `signOut()` as source of truth; avoid manual state mutation except documented workaround with test. |
| 15 | Scan/discover | ExampleApp `PairDeviceState.swift:L40-L49`, `L98-L106`; v0.12 `SDK_INTERFACE.md:L379-L398` | `PairDeviceState.swift:L40-L48`, `L99-L107` | PASS | Keep. |
| 16 | Scan timeout/cancel | ExampleApp `PairDeviceState.swift:L98-L116` | `PairDeviceState.swift:L99-L121` | PASS | Keep; ensure stopScan on all exits. |
| 17 | Connect with pairing | ExampleApp `PairDeviceState.swift:L118-L128`; v0.12 `SDK_INTERFACE.md:L381-L400` | `PairDeviceState.swift:L123-L131` | PASS | Keep. |
| 18 | Pairing connection blink/ask response | ExampleApp `PairDeviceState.swift:L51-L63`; v0.12 `SDK_INTERFACE.md:L402-L420` | `PairDeviceState.swift:L51-L64` | PASS | Keep. |
| 19 | Button confirmation | ExampleApp `PairDeviceState.swift:L77-L89`; v0.12 state `buttonTaps` `SDK_INTERFACE.md:L224-L228` | `PairDeviceState.swift:L81-L90` | PASS | Keep. |
| 20 | v0.12 paired-device persistence | v0.12 `persistPairedDevice`, `clearPairedDevice`: `SDK_INTERFACE.md:L381-L407` | Noom uses old `persistDeviceState` dictionary: `PairDeviceState.swift:L134-L148` | FAIL | Replace with `persistPairedDevice(macAddress:name:type:)` and `clearPairedDevice()` where appropriate. |
| 21 | Disconnect after pair/cancel | ExampleApp `PairDeviceState.swift:L110-L142` | `PairDeviceState.swift:L115-L148` | PASS | Keep behavior after API migration. |
| 22 | Device disconnected error during pair | ExampleApp `PairDeviceState.swift:L66-L74` | `PairDeviceState.swift:L67-L77` | PASS | Keep. |
| 23 | Paired vs live-connected distinction | ExampleApp indicator `MainTabView.swift:L24-L47`; v0.12 `haveDevice`/`connected`: `SDK_INTERFACE.md:L204-L207` | `NoomBandConnectionState.swift:L3-L15`; `MainTabView.swift:L56-L87` | PASS | Keep. |
| 24 | Battery/charging display | ExampleApp `MainTabView.swift:L28-L47`, `L53-L66`; v0.12 `SDK_INTERFACE.md:L224-L225` | `MainTabView.swift:L58-L87` | PASS | Keep. |
| 25 | Sync progress/last sync | ExampleApp `ProfileView.swift:L7-L12`, `L80-L84`; v0.12 sync `SDK_INTERFACE.md:L213-L218`, `L525-L528` | `ProfileView.swift:L8-L13`, `L93-L98` | PASS | Keep. |
| 26 | Reconnect paired device | Required by task; v0.12 has `connect(_:, pairing:)` `SDK_INTERFACE.md:L379-L382` | CTA exists but routes into setup/pair sheet: `NoomBandConnectionState.swift:L37-L43`, `NoomProductScreens.swift:L33-L42` | PARTIAL | Add explicit reconnect path for paired-but-disconnected device; do not re-pair unless needed. |
| 27 | Unpair | v0.12 `removeDeviceFromPairedDevices` clears persisted store: `SDK_INTERFACE.md:L383`, `L407` | Noom calls remove plus old `persistDeviceState([:])`: `ProfileView.swift:L113-L121` | FAIL | Use v0.12 unpair/clear API only; verify state flips. |
| 28 | Dashboard date/tz load | ExampleApp `DashboardState.swift:L17-L20`; v0.12 `SDK_INTERFACE.md:L540` | `DashboardState.swift:L17-L20` | PASS | Keep. |
| 29 | Dashboard date picker | ExampleApp `DashboardView.swift:L59-L66` | `DashboardView.swift:L50-L57` | PASS | Keep. |
| 30 | Manual refresh | ExampleApp `DashboardView.swift:L68-L70` | `DashboardView.swift:L58` | PASS | Keep. |
| 31 | Post-sync refresh | ExampleApp `DashboardView.swift:L72-L84` | `DashboardView.swift:L59-L67` | PASS | Keep. |
| 32 | Recovery dashboard | ExampleApp `DashboardView.swift:L31-L37` | `DashboardView.swift:L40-L45`, `L72-L94` | PASS | Keep, Noom styling ok. |
| 33 | Sleep dashboard | ExampleApp links sleep detail from dashboard `DashboardView.swift:L38-L45` | Noom renders sleep card but no dashboard detail link: `DashboardView.swift:L97-L111` | PARTIAL | Make sleep dashboard card navigable or provide equivalent reachable path from same context. |
| 34 | Steps dashboard | ExampleApp metric link `DashboardView.swift:L99-L100` | Noom includes steps tile only when present but no link: `DashboardView.swift:L113-L125` | PARTIAL | Restore route to `StepsDetailView`. |
| 35 | Calories dashboard | ExampleApp metric link `DashboardView.swift:L101-L102` | No current dashboard calories route/tile | FAIL | Restore visible calories route or justify SDK removal. |
| 36 | HR dashboard | ExampleApp metric link `DashboardView.swift:L103-L104` | No current dashboard HR route/tile | FAIL | Restore visible HR route. |
| 37 | HRV dashboard | ExampleApp metric link `DashboardView.swift:L104-L105` | HRV tile can appear but no link: `DashboardView.swift:L113-L125` | PARTIAL | Restore route to `HRVDetailView`. |
| 38 | RR dashboard | ExampleApp metric link `DashboardView.swift:L106-L107` | No current dashboard RR route/tile | FAIL | Restore visible RR route. |
| 39 | Sleep detail | ExampleApp `SleepDetailView.swift:L24-L55`, `L112-L149`, `L213-L221` | `MainTabView.swift:L23-L34`; Noom detail source `SleepDetailView.swift:L416-L419` | PASS | Keep after dashboard routing fixed. |
| 40 | Recovery detail | ExampleApp `RecoveryDetailView.swift:L24-L61` | `MainTabView.swift:L32-L34`; Noom detail renders daily/range data | PASS | Keep. |
| 41 | Steps detail reachability | ExampleApp route `DashboardView.swift:L99-L100` | File exists but no visible route | FAIL | Add route. |
| 42 | Calories detail reachability | ExampleApp route `DashboardView.swift:L101-L102` | File exists but no visible route | FAIL | Add route. |
| 43 | HR detail reachability | ExampleApp route `DashboardView.swift:L103-L104` | File exists but no visible route | FAIL | Add route. |
| 44 | HRV detail reachability | ExampleApp route `DashboardView.swift:L104-L105` | File exists but no visible route | FAIL | Add route. |
| 45 | RR detail reachability | ExampleApp route `DashboardView.swift:L106-L107` | File exists but no visible route | FAIL | Add route. |
| 46 | Personal insights | ExampleApp `InsightsState.swift:L12-L23` equivalent via v0.12 `fetchNewInsights`: `SDK_INTERFACE.md:L637` | `InsightsState.swift:L11-L23`; `InsightsView.swift:L25-L31`, `L64-L91` | PASS | Keep. |
| 47 | Population filters/charts | ExampleApp `InsightsState.swift:L50-L80`; v0.12 `SDK_INTERFACE.md:L638-L642` | Missing state methods; view calls nonexistent `loadFilters/loadPopulation`: `InsightsView.swift:L40-L49` | FAIL | Rebuild population filter + chart state/UI or remove unreachable calls until implemented. |
| 48 | Insights feedback | v0.12 `SDK_INTERFACE.md:L643` | No current call found | FAIL | Add feedback or hide feedback controls. |
| 49 | Loading/empty/error behavior | ExampleApp uses progress/errors across views | Noom has loading/no-data cards `DashboardView.swift:L35-L39`, `L155-L177`; insights `InsightsView.swift:L25-L31`, `L104-L119` | PASS | Keep, add to all restored routes. |
| 50 | Body State from Sensor Band | Product-loop task requires existing Recovery only; v0.12 recovery model `SDK_INTERFACE.md:L571-L610` | Recovery card/detail are SDK-backed | PASS | Treat Recovery as the only shippable Body State. |
| 51 | Suggested experiment display | v0.12 personal insights include `suggestedExperiment` via `SB_NewInsights`; Noom maps it if present `InsightsView.swift:L88-L90` | Only display, no accept/active/completed lifecycle | PARTIAL | Keep as seed display only; backend owns lifecycle. |
| 52 | Persisted experiment lifecycle | Remote proto has old `ExperimentStatus` but no Noom lifecycle persisted in iOS; see `proto/experiments.proto:L11-L59` | No Noom backend/client lifecycle | FAIL | New backend contract: proposed -> active -> completed/cancelled. |
| 53 | Progress-signal time series | Not in ExampleApp; required product loop | Static UI only: `NoomProductScreens.swift:L152-L183` | FAIL | Replace fake chart/status with backend + SDK-backed signals. |
| 54 | GLP-1/appetite/care-note flow | Not SDK-backed; task forbids unsupported features | Static UI + empty save: `NoomProductScreens.swift:L46-L89` | FAIL | Remove/feature-gate until real Noom-owned contract exists; no medication claims. |
| 55 | Settings/notifications/backend contracts | v0.12 has SDK server APIs but no Noom loop contract | No current durable settings/notifications layer | FAIL | Backend card must own this if supported by existing infra. |
| 56 | DEBUG QA routes only | Debug routes in `ContentView.swift:L117-L249` | Release path excludes QA host `ContentView.swift:L20-L26` | PASS | Keep debug-only. |
| 57 | Build readiness | Required child implementation acceptance | `xcodebuild -project NoomApp/NoomApp.xcodeproj ...` exit 65: cannot resolve `SensorBioSDK` without Pods workspace/deps | FAIL | Run `pod install`/workspace build in child implementation; then fix source compile errors. |

Implementation sequence for child card:
1. Preserve current WIP. Capture `git status --short --branch`, do not reset/stash/clean.
2. Fix project integration enough to build via CocoaPods workspace; do not start product changes until build command is deterministic.
3. Apply lifecycle gate: production-safe env + `hydrateSession` + session routing.
4. Migrate device persistence/unpair/sign-out to v0.12 public API.
5. Restore all ExampleApp navigation paths: dashboard metric links and population insights.
6. Remove or feature-gate unsupported fake Noom screens.
7. Add parity scanner/tests that assert every row above either PASS or intentionally feature-gated with documented backend blocker.
8. Run `python3 docs/qa/noom_ios_scan.py --repo-root . --json`, Python regression tests, `pod install`, `xcodebuild`, and simulator route screenshots.

Read-only checks run on this card:
- `git status --short --branch`: dirty WIP preserved; ExampleApp deleted, NoomApp/docs untracked.
- `python3 docs/qa/noom_ios_scan.py --repo-root . --json`: scanned 35 files; visible hits 0; security hits 0; internal hits 97; missing required Noom terms 0.
- `python3 -m unittest docs/qa/test_noom_auth_routing.py docs/qa/test_noom_band_state.py`: 7 tests run, 2 failures. Failures are test-wiring bugs: `test_noom_band_state.py` sets `STATE = DASHBOARD`, so it searches DashboardView for `NoomBandConnectionState` enum cases.
- `xcodebuild -project NoomApp/NoomApp.xcodeproj -scheme NoomApp -destination 'generic/platform=iOS Simulator' -derivedDataPath NoomApp/build/DerivedDataParityCheck build`: exit 65; cannot resolve module dependency `SensorBioSDK` because Pods/workspace dependencies were not generated/resolved for that derived data path.

Acceptance criteria for parity completion:
- All 57 rows are PASS or explicitly marked unsupported with product-approved removal/feature gate.
- No visible fake values, empty-action buttons, raw SensorBio/SB strings, or unsupported GLP-1/coach/progress claims in release UI.
- Release build defaults production; staging is DEBUG/internal only.
- Fresh install, cold relaunch, signed-in relaunch, sign-out, pair/unpair/reconnect, and post-sync dashboard refresh are verified on simulator/device as applicable.
- Every ExampleApp user-visible path is reachable in Noom styling.
- `pod install` + workspace `xcodebuild` pass, Python scanner/tests pass, and route screenshots are refreshed.
