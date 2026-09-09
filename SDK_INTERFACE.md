# SensorBioSDK — iOS Integration Guide

This document describes the **public** customer-facing surface of `SensorBioSDK` as it exists today. The SDK ships as a set of `.xcframework`s consumed via CocoaPods (see [README.md](./README.md) for integration); `import SensorBioSDK` is the only line a customer app needs.

> **Source of truth.** This file lives on `mobile_sensorbio_sdk_ios` `main` and tracks the latest public surface. A copy is synced into [`mobile_sensorbio_sdk_ios_binary`](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary/blob/main/SDK_INTERFACE.md) at each tagged binary release; customers pinning to a binary tag should read the copy in the binary repo for the surface that matches their pin. The SDK-repo version may include symbols not yet present in the most recent binary release.

> **Visibility note.** This document covers the customer-facing API surface only. SDK-internal symbols are filtered out of the binary framework's Swift interface and are not documented here.

> **Backend guide.** Registration needs one endpoint on your own server, which mints the single-use SDK token your app hands to the SDK. [§5](#5-minting-sdk-tokens--your-backend) is the guide for whoever builds it: the exchange contract, reference implementations, error handling, and key rotation.

---

## 1. Adding the SDK

### 1.1 CocoaPods (binary distribution)

The SDK ships as three `.xcframework`s plus an umbrella binary podspec at the root of [the binary repo](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary). Pin a tagged release in your `Podfile`:

```ruby
platform :ios, '18.0'

target 'MyApp' do
  use_frameworks!

  pod 'SensorBioSDK',
    :git => 'git@github.com:GetSensr-io/mobile_sensorbio_sdk_ios_binary.git',
    :tag => 'v2.3.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']     = '18.0'
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD']    = 'c++17'
      config.build_settings['CLANG_CXX_LIBRARY']              = 'libc++'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
```

Then `pod install`, open `MyApp.xcworkspace`, and `import SensorBioSDK`. The `post_install` block bumps the deployment target to iOS 18 (SDK requires), forces C++17 (retained but no longer load-bearing — abseil used to arrive as a transitive pod and static-asserts C++17; it now lives inside the xcframework and your build compiles no C++ of its own), and turns on library-evolution mode (the SDK's SwiftQueue `Job` subclasses reference method descriptors that only exist when all transitive pods are also built BLFD).

The single `pod 'SensorBioSDK'` line vendors the three xcframeworks and transitively brings the third-party pods the SDK links against (SwiftProtobuf; SwiftKeychainWrapper; KeychainAccess; SwiftQueue; CocoaMQTT). **gRPC is not one of them** — gRPC-Core, abseil and BoringSSL are linked inside `SensorBioSDK.xcframework` with their symbols hidden, so they never reach your dependency graph and cannot collide with a gRPC your app links for its own reasons (Firebase/Firestore being the common case). **Customers only import `SensorBioSDK`** — the BT SDK and LibFXC are linked transitively and have no user-callable surface.

Full integration walkthrough: see [README.md](./README.md).

### 1.2 Platform requirements

- **iOS 18+** — required minimum deployment target
- **Xcode 16.3+** (Swift 6.1 toolchain)
- **CocoaPods 1.16+**
- **Bluetooth + Background Modes capabilities** — required so the SDK can stay connected to the wearable and finish syncs while the app is backgrounded

### 1.3 Importing

```swift
import SensorBioSDK
```

The library exports a single top-level accessor for the SDK singleton — use it instead of `SB_SDK.shared` (both work; the short alias is the preferred idiom):

```swift
public let sensorBio = SB_SDK.shared
```

> **Module vs class.** The framework module is `SensorBioSDK`; the singleton class inside it is `SB_SDK`. The `SB_` prefix on the class is part of the SDK's binary-distribution naming convention.

### 1.4 Required `Info.plist` keys & background capabilities

The SDK talks to Sensor Bio wearables over Bluetooth LE and needs to stay connected while the host app is backgrounded so syncs can complete. Packet uploads now drive off BLE-sync completion — there is no separate background-fetch or `BGTaskScheduler` path — so the consuming app only has to declare the BLE-related keys below.

#### Bluetooth

Add the user-facing usage strings to `Info.plist`. They are surfaced in the system permission prompt the first time the SDK starts a scan; ship a copy that names your product:

| Key | Required | Purpose |
|---|---|---|
| `NSBluetoothAlwaysUsageDescription` | yes | Shown when the SDK requests Bluetooth permission on iOS 13+. Required for scanning, connecting, syncing, and background BLE. |
| `NSBluetoothPeripheralUsageDescription` | yes (legacy) | Required for App Store review on apps that still target older iOS deployment floors. Even on iOS 18+ apps it is safest to include it. |

Example:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>MyApp uses Bluetooth to connect to your Sensor Bio wearable and sync biometrics in the background.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>MyApp uses Bluetooth to connect to your Sensor Bio wearable.</string>
```

#### Background mode

Enable the **Background Modes** capability on the app target and tick *Uses Bluetooth LE accessories* (or add `bluetooth-central` directly to `Info.plist` under `UIBackgroundModes`):

| Mode | `UIBackgroundModes` value | Why the SDK needs it |
|---|---|---|
| Uses Bluetooth LE accessories | `bluetooth-central` | Keep the BLE connection alive, finish in-progress syncs, and receive sensor packets while the app is backgrounded. Uploads run as each sync completes. |

Example:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

> The SDK does not register `BGTaskScheduler` identifiers, so there is no `BGTaskSchedulerPermittedIdentifiers` requirement and no need for `fetch` or `processing` modes.

#### Sanity check

If either of the BLE-related entries is missing, you will see one of the following at runtime:

- **No BLE prompt / `CBManager.authorization == .denied`** → `NSBluetoothAlwaysUsageDescription` is missing.
- **App suspends mid-sync** → `bluetooth-central` is not in `UIBackgroundModes`.

---

## 2. Lifecycle & Configuration

### 2.1 App startup

The SDK self-observes `UIApplication.didBecomeActiveNotification` / `didEnterBackgroundNotification`.

```swift
import SensorBioSDK
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 1. Pin server environment (staging vs production)
        SB_SDK.environment = .production

        // 2. (Optional) restore prior session from keychain
        sensorBio.hydrateSession()

        // 3. (Optional) bridge SDK logs into your own logging pipeline
        SB_SDK.log
            .sink { level, file, function, line, message in
                print("[SDK \(level)] \(message)  (\(file):\(line))")
            }
            .store(in: &cancellables)

        return true
    }
}
```

### 2.2 Static configuration knobs

```swift
extension SB_SDK {
    public static var environment: Environment                                     // .staging | .production
    public static var log: AnyPublisher<(LogLevel, String, String, String, Int), Never>
    public static let version: String                                              // SDK semver
}

extension SB_SDK {
    public enum Environment {
        case staging         // staging server
        case production      // production server (default)
    }
}
```

> **Bluetooth SDK license.** The underlying Bluetooth SDK license key is bundled inside `SB_SDK` and is supplied to `acquireLicense(_:)` internally. There is no integration step for it. A future release will expose a public setter so customer apps can ship their own key.

---

## 3. The `SB_SDK` Facade

All customer-facing functionality is exposed off the `sensorBio` singleton. The class drops the canonical-product prefix from history because **it is the SDK** — there is one and only one — but adopts `SB_` in the source rename for binary-distribution hygiene.

### 3.1 Singleton & class shape

```swift
public class SB_SDK: @unchecked Sendable {
    public static let shared = SB_SDK()
}

public let sensorBio = SB_SDK.shared
```

### 3.2 Observable state (Combine `@Published`)

Subscribe via `sensorBio.$propertyName` or read directly. All are read-only from the app's perspective.

**Session & user**

| Property | Type | Description |
|---|---|---|
| `session` | `SB_Session?` | Signed-in user session (token + profile snapshot) |
| `userProfile` | `SB_UserProfile?` | Full user identity + body metrics |
| `organization` | `SB_OrgMembership?` | User's org / group membership |
| `featureFlags` | `[String]` | Server-driven feature flags |

> **An absent birthday is null, not a sentinel.** `SB_UserProfile.birthday` is
> `DateComponents?` — nil when the server has no birthday for the user — and
> `SB_UserProfile.age` is `Int?` for the same reason. Neither is ever the zero
> calendar date. Before SB-1837 both platforms represented "no birthday" as that
> zero date, which no type check could distinguish from a real one: iOS computed an
> age around 2025 from it (a max HR of roughly -912), and Android threw
> `IllegalFieldValueException` out of `age`, `BMR` and `CFF`. Host code that has to
> produce a number should substitute `SDKConstants.DefaultUserMetrics.Age`, which is
> what the SDK's own internal compute uses and is the same on both platforms.

**Pairing, connection & reachability**

| Property | Type | Description |
|---|---|---|
| `pairedDevice` | `SB_PairedDeviceState?` | Pre-connection device snapshot (name, type, macAddress) |
| `haveDevice` | `Bool` | A device is paired |
| `pairingState` | `SB_PairingState?` | Where the open pairing transaction stands; `nil` when none is open (§6.1) |
| `connected` | `Bool` | BLE connection is up |
| `isFullyConfigured` | `Bool` | Device finished configuration and is usable |
| `bluetoothAvailable` | `Bool` | BLE is available on the phone |
| `networkStatus` | `SB_NetworkStatus` | Reachability — wifi / cellular / unreachable |

**Sync**

| Property | Type | Description |
|---|---|---|
| `deviceSyncing` | `Bool` | Active sync in progress |
| `percentSynced` | `Int` | Sync progress (0–100) |
| `lastSyncd` | `Date` | Wall-clock of last successful sync |
| `latestDeviceEpochInMillis` | `Int64` | Epoch (ms) of the newest sensor packet synced from the device; advanced only from real packet timestamps (never wall-clock). Diagnostic (Developer Tools); recording finalize gates on the device bookend, not this |

**Device telemetry**

| Property | Type | Description |
|---|---|---|
| `batteryLevel` | `Int?` | 0–100 |
| `charging` | `Bool?` | Device is on its charger |
| `worn` | `Bool?` | Device is being worn |
| `buttonTaps` | `Int?` | Last button-tap event. Pairing no longer needs this — the SDK consumes it internally to detect the confirmation press (§6.1) |

**Device identity & firmware**

| Property | Type | Description |
|---|---|---|
| `type` | `SB_BluetoothDeviceType?` | Device model |
| `serialNumber` | `String?` | |
| `modelNumber` | `String?` | |
| `manufacturerName` | `String?` | |
| `hardwareRevision` | `String?` | |
| `firmwareVersion` | `String?` | Device firmware as `"major.minor.build"` |
| `latestFirmwareVersion` | `String?` | Recommended firmware version |
| `bluetoothSoftwareRevision` | `String?` | |
| `algorithmsSoftwareRevision` | `String?` | |
| `sleepSoftwareRevision` | `String?` | |

**Update prompts & misc**

The following `@Published` properties are also observable:

`forceUserToUpdatePassword`, `forceUserToUpdateProfile`, `exerciseZoneAttributes`, `updateSuggested`, `updateRequired`, `deviceAirplaneModeOn`, `webAppCookie`, `lastSyncedTemp`.

### 3.3 Computed read-only properties

```swift
public var isAuthenticated: Bool         // session != nil
public var hasStoredAuthToken: Bool      // keychain holds an auth token
public var isDeviceConnected: Bool       // paired + connection up
public var sdkVersion: String            // this SDK's version, e.g. "2.3.0 (41)"
public var isAirplaneModeActive: Bool    // device is in airplane mode
public var isRawLoggingEnabled: Bool     // white-label raw-sensor-logging on
public var haveUnuploadedPackets: AnyPublisher<Bool, Never>
public var developmentLogStats: (storeURL: URL, enginePacketCount: Int)
```

### 3.4 Event streams (Combine subjects)

Subscribe via `sensorBio.<subject>.sink { … }`.

```swift
// Auth & connection lifecycle
// (Pairing is not here — it is one transaction reported on the
//  `$pairingState` @Published property. See §6.1.)
public let signOutComplete:             PassthroughSubject<Void, Never>
public let deviceDisconnected:          PassthroughSubject<String, Never>   // payload: macAddress
public let deviceConnected:             PassthroughSubject<Void, Never>     // low-level BLE connect
public let deviceFullyConfigured:       PassthroughSubject<Void, Never>     // post-configure
public let deviceLinkFailed:            PassthroughSubject<SB_DeviceLinkFailure, Never>  // server rejected the device-link (serial-enforced subscription)
public let subscriptionLost:            PassthroughSubject<Void, Never>     // server rejected an authenticated RPC for no active subscription — host should alert + force logout (see §3.4.1)

// Streaming biometrics — timestamp + value
public let hr:    PassthroughSubject<(Int, Int),     Never>                 // bpm
public let hrv:   PassthroughSubject<(Int, Int),     Never>                 // ms
public let rr:    PassthroughSubject<(Int, Int),     Never>                 // breaths/min
public let spo2:  PassthroughSubject<(Int, Float),   Never>                 // %
public let snr:   PassthroughSubject<(Int, Float),   Never>                 // dB
public let bbi:   PassthroughSubject<(Int64, Int),   Never>                 // ms
public let ppg:   PassthroughSubject<(Int64, Float), Never>                 // raw
public let ecg:   PassthroughSubject<(Int64, Float), Never>                 // raw
public let firmwareProgress:            PassthroughSubject<Float, Never>

// Biometric-record & sleep-store results
public let biometricRecordResult:       PassthroughSubject<SB_BiometricRecordResult, Never>
public let spotCheckReport:             PassthroughSubject<SB_SpotCheckReportEvent, Never>   // local report, at finalize
public let activityReport:              PassthroughSubject<SB_WorkoutDetail, Never>          // local report, at finalize
public let meditationReport:            PassthroughSubject<SB_MeditationGraph, Never>        // local report, at finalize
public let biometricRecordProcessed:    PassthroughSubject<Void, Never>
public let sleepStored:                 PassthroughSubject<Void, Never>
public let sleepDetected:               PassthroughSubject<SB_DetectedSleep, Never>  // valid on-device sleep finalized (start/end epoch ms)
```

#### 3.4.1 `subscriptionLost` and the subscription block

When the server rejects an authenticated RPC because the user has no active
device subscription, the SDK does two things: it fires `subscriptionLost`, and
it enters a **subscription block** — it disconnects the band and refuses to
auto-connect or sync until the block lifts. The block is a data-exfil guard, not
a UI state: BLE sync pulls data off the band with no server round-trip, so the
gate is persisted and deliberately survives relaunch.

What a host needs to know about it:

- **The band is inert while blocked.** No auto-connect on launch, no reconnect
  after a drop. `pairedDevice` stays populated and pairing a *new* band still
  works, so "paired but never connects" is the shape the user sees.
- **The signal can arrive in any app state, and not only after a call you
  made.** Background uploads and the SDK's own foreground re-verification both
  reach the server, so `subscriptionLost` can land mid-session, while
  backgrounded, or moments after a launch. A host must therefore be able to act
  on it without a screen to present on: sign the user out first and explain
  afterwards, rather than gating the sign-out behind a modal that a backgrounded
  app cannot show. MySensr signs out immediately, states the reason on the
  onboarding landing, and adds a local notification when the app was not in
  front of the user.
- **It lifts by itself when the subscription is genuinely fine.** Any successful
  authenticated RPC clears the block and reconnects the band — the server gates
  its whole authenticated surface on the subscription, so a `200` is proof. A
  block that was armed by a transient server condition therefore heals on the
  next successful call or the next foreground, with no alert and no user action.
- **Inconclusive is not "cleared".** Offline or a transport failure leaves the
  block standing and re-checks next foreground, rather than freeing the band on
  no evidence.

So the host's job is only the alert + forced sign-out on `subscriptionLost`.
Do not build a local mirror of the blocked state, and do not treat one
`subscriptionLost` as permanent — the SDK owns the lifecycle and will stop
re-firing once the server stops rejecting.

`biometricRecordResult` emits once for **every** accepted spot check, and the host has three outcomes to tell apart:

| `id` | `error` | meaning | host should |
|---|---|---|---|
| non-nil | nil | scored — a report exists | show the report |
| nil | non-nil | submit failed | retryable; the SDK keeps re-driving it |
| nil | nil | accepted, but the server scored **no report** | tell the user there wasn't enough data — nothing further is coming |

The third row is the one to handle explicitly. It previously emitted nothing at all (the publish guarded on the id being present), so a host waiting on this subject would wait forever for a report the server had already declined to produce. Note also that such a submission is marked terminal at submit time rather than entering the in-flight set, so it does **not** appear as a "Processing…" card — there is no pending server-side work for it to represent.

#### `spotCheckReport` — the report, before the upload

A spot check's report is **not** a server calculation. bioedge derives it on the phone from the recording's beat-to-beat intervals, the submit ships those numbers up as `spotCheckData`, the server persists them, and `fetchSpotCheckDetails(id:)` hands the same values back. A host that waits for the round trip is therefore holding the user on a spinner to retrieve numbers the device already produced.

`spotCheckReport` fires once per finalized spot check, at the end of finalize — before the submit, and independent of whether it ever succeeds:

```swift
public enum SB_SpotCheckReportEvent: Sendable, Equatable {
    case ready(SB_SpotCheckDetails)
    case unscoreable
    case deferred
}
```

| case | meaning | host should |
|---|---|---|
| `.ready` | the report, built from the data being uploaded | show it now — no wait, works offline |
| `.unscoreable` | data is all in and holds no beat-to-beat intervals: no report exists and none will | tell the user there wasn't enough data |
| `.deferred` | the post-stop sync couldn't run, so the window's data may still be on the band | tell the user it'll appear on their timeline |

`.ready` carries every field the server would return **except `pdfReportURL`**, which only exists once the server has rendered it. Keep any "share the PDF" affordance hidden until `biometricRecordResult` delivers an id for the same recording; that id is also what the timeline entry is keyed on, so a host showing a local report can refresh it in place when the id lands (the numbers are identical by construction — the shown report and the uploaded one are the same derive).

`.deferred` and `.unscoreable` are both terminal for the in-session decision: neither will be followed by a `.ready` for that recording.

#### `activityReport` and `meditationReport` — always a report

Both fire exactly once per finalized recording and carry the report directly — `SB_WorkoutDetail` for an activity, `SB_MeditationGraph` for a meditation. These are the same types `fetchWorkoutDetail(workoutTime:)` and `fetchMeditationGraph(date:sessionTimestamp:)` return, so a host renders local and server data through one screen.

**There is no "not enough data" verdict on these two, deliberately.** An activity or a meditation is a real event with a duration, a name and a time whether or not biometrics came through — so whatever the window holds is plotted and whatever it doesn't simply isn't there. A workout that captured no heart rate yields a detail with `hrmData == nil`; a meditation with no respiration yields an empty `brpms`. Hosts already omit a chart with no series, which is the whole behaviour.

Spot check is the exception, and keeps its three-way `SB_SpotCheckReportEvent`: its entire content *is* its biometrics, so an empty window leaves genuinely nothing to show, and the server will decline to score it.

`activityReport`'s `.headerMetrics` carry duration, calories and — for step-based workouts only — distance and pace. Non-step workouts (swimming, basketball) carry **no** steps or distance rather than zeros: the band doesn't count them there, so a zero would read as "you took no steps" instead of "steps aren't measured here". This mirrors the server, which skips the block entirely for them.

`meditationReport`'s graph keeps the score's own explained failure states — a session missing an input arrives with a **negative sentinel score** (−1 … −6), `processState == .processedWithError`, and the server's own message ("Minimum 10 HRV readings are needed…"). Those live *inside* the graph; they explain the score, they don't gate whether the user sees a report. The guards, in evaluation order: HRV readings ≥ 10, HR readings ≥ 10, respiration readings ≥ 10, both regressions established, HR baseline established, HRV baseline established.

**Neither is guaranteed to match the server, and that is worth knowing before building on it.** A spot check's report agrees by construction — the phone computes it, the submit ships it, the server stores it verbatim. These two do not:

* **Activity calories.** The server recomputes from its own copy of the HR series and its own 30-day resting-HR baseline, and chooses between two calorie formulas with a deployment flag the client can't see (`SB_WorkoutCalorieFormula` documents this). The computation is ported line-for-line, so the drift is small and confined to the calorie figure — but the number can settle when the server's entry lands.
* **Meditation score.** Recomputed on every server read against 30-day baselines drawn from the whole account, where the SDK's come from local sleep history. Two further parity notes: the **movement penalty is always 0**, locally and on the server — the variable feeding it is declared and never assigned, so it has never contributed to any meditation ever scored, and "fixing" it locally would make every score read low. And a device holding less history than the account produces a lower baseline, or none, which fails the score honestly rather than scoring against a wrong number.

Refresh the on-screen report in place when the server's entry arrives, rather than re-navigating.

Manually-logged sessions (`createActivitySession`) fire neither — there is no recorded window to build a report from.

`SB_MeditationGraph` gains `hrLinearFit` / `hrvLinearFit` (`SB_TimeValueStraightLine?`). The server has always sent them; the SDK simply never surfaced them. They are bridged from the proto as well as built locally, so a fetched graph and a local one carry the same fields — and they are the endpoints the HR and HRV penalties are computed from, which is why a fit that can't be made (fewer than 2 points, or more than 3600) is what produces the "regression not established" sentinel.


### 3.5 Recording submissions (optimistic timeline)

In-flight finished-recording submissions the SDK is still uploading /
processing, backed by the durable `SB_RecordingSubmission` store. Drive the
timeline's pinned "we're working on it" cards off this, then reconcile them
against the fetched timeline. Values cross the boundary as the
`SB_RecordingSubmissionInfo` value type (no SwiftData leak); status is
`SB_RecordingSubmissionStatus` (`pendingUpload` → `uploaded` → `processed`,
or `failed`). Only non-`processed` rows are surfaced.

```swift
// Current in-flight submissions (status != .processed), newest first;
// CurrentValueSubject-backed, so new subscribers get the state immediately.
public var pendingSubmissionsPublisher: AnyPublisher<[SB_RecordingSubmissionInfo], Never> { get }

// One-shot snapshot of the same set (e.g. on .onAppear).
public func pendingSubmissions() -> [SB_RecordingSubmissionInfo]

// Flip any in-flight submission the server now shows to .processed (drops it
// from the set). Call after fetchWorkoutTimeline, passing the flattened
// entries: result.items.flatMap { $0.entries }. No extra network.
public func reconcileSubmissions(against entries: [SB_WorkoutEntry])

// Manually re-drive a .failed submission (reset to .pendingUpload + kick the
// engine). No-op if the id is unknown or the submission isn't .failed.
public func retrySubmission(localId: UUID)
```

### 3.5.1 Local-first timeline entries (SB-1956)

A finished recording's report is now **stored** on its submission row, so it
survives a relaunch, a recreated view model, or the user backing out and coming
back — none of which the `PassthroughSubject` events could. At that point a
"Processing…" placeholder is the app declining to show data it already holds, so
the SDK synthesizes the real row instead:

```swift
// In-flight recordings that have a stored report, as real timeline rows.
public func localRecordingEntries() -> [SB_LocalRecordingEntry]

// The stored report for a recording, by its start timestamp.
public func localWorkoutDetail(startTsMillis: Int64) -> SB_WorkoutDetail?
public func localMeditationGraph(startTsMillis: Int64) -> SB_MeditationGraph?
public func localSpotCheckDetails(startTsMillis: Int64) -> SB_SpotCheckDetails?
```

`SB_LocalRecordingEntry` carries a real `SB_WorkoutEntry` — same shape the
timeline read returns — plus the submission's `status`, its `scoredNoResult`
flag, and the `dateInt` (`yyyyMMdd`) section it belongs in. The SDK does the
assembly so a host renders these through its existing row view and routes taps
through its existing per-type detail screens.

**Three merge rules, each a bug if dropped:**

* **Page 1 only.** These are minutes old and belong at the head of the list.
  Cursor pages encode a server-side query; don't merge into them.
* **Dedup on the correlator, at second granularity.** `reconcileSubmissions`
  normally removes a local row before its server entry renders, but there is a
  window where both exist. Match at **seconds**, not milliseconds: the
  spot-check server domain drops the sub-second remainder, which is why exact
  millisecond matching could never match a spot check (SB-1214).
* **Not while searching or filtering.** A synthesized row never went through the
  server's query.

`fetchWorkoutDetail(workoutTime:)` and `fetchMeditationGraph(date:sessionTimestamp:)`
now **fall back to the stored report** when the server has no answer — a
just-ingested workout returns `NOT_FOUND`, a meditation's summary can be twelve
minutes behind, and offline there is no answer at all. The server stays the
authority whenever it has one. `fetchSpotCheckDetails(id:)` gets no such
fallback: it is addressed by a server-assigned id that doesn't exist until the
submit lands, so there is no key to fall back *from* — use
`localSpotCheckDetails(startTsMillis:)` while `entry.workoutId` is empty.

**`SB_RecordingSubmissionInfo` changes.** `autoPresentOnProcessed` and
`presentedAt` are **removed**. They were added for an auto-present-on-`processed`
flow that was designed, dropped in the 2026-07-06 scope revision, and never read;
SB-1747/1952/1954 settled the question they existed for by another route — every
recording type now shows its report at finalize, so there is nothing left to
present later. In their place, `hasLocalReport: Bool` says whether a stored
report exists. Submissions where it is `false` — a manually-logged session, an
`.unscoreable` / `.deferred` recording, a row predating this version — are the
only ones with nothing to render but a status.

### 3.6 Detected activities (confirm-or-dismiss)

The band's firmware can decide by itself that an activity has started — from
accelerometer motion, from cadence, or from both agreeing — switch the PPG into
continuous mode to capture it, and stop when it thinks the activity is over. On
the next sync that arrives as a single activity bookend, and the SDK stores it.

**Nothing is uploaded on its own.** A detection is an *offer*: the SDK holds it
in the durable `SB_DetectedActivity` store and publishes it, and the user either
confirms it (which submits it as a real activity) or dismisses it. Values cross
the boundary as the `SB_DetectedActivityInfo` value type (no SwiftData leak).

```swift
// Detections that are ready to be confirmed, oldest first;
// CurrentValueSubject-backed, so new subscribers get the state immediately.
public var detectedActivitiesPublisher: AnyPublisher<[SB_DetectedActivityInfo], Never> { get }

// One-shot snapshot of the same set (e.g. on .onAppear).
public func detectedActivities() -> [SB_DetectedActivityInfo]

// Confirm a detection under `activityName`: submits it as a real general-cardio
// session and retires the detection. Returns false when the detection is unknown
// or already answered, so a second call for the same detection is a no-op.
@discardableResult @MainActor
public func confirmDetectedActivity(startTsMillis: Int64, activityName: String) -> Bool

// Dismiss a detection. Marked ignored on-device and never published again,
// including when its bookend re-syncs (which it will). Nothing is uploaded.
@discardableResult
public func dismissDetectedActivity(startTsMillis: Int64) -> Bool
```

`SB_DetectedActivityInfo` carries `startTsMillis` (its identity — pass it back
to either call), `endTsMillis`, `durationMillis`, the `tzOffsetMinutes` in force
when it was ingested, an `SB_DetectedActivitySource` (`motion` / `cadence` /
`motionAndCadence`), and `createdAt` (when the bookend synced, not when the
activity happened). Field-for-field the same as Android's type of the same name,
so a host porting between them has nothing to translate. Render the activity's time from `tzOffsetMinutes`, not the
phone's current zone, so an activity confirmed after travelling still reads at
the wall-clock time it happened.

**Everything published is answerable now — that is the whole contract.** There
is no status on the type and no state machine for a host to reproduce, because
a detection is only published once:

* the band has synced past the activity's end, **and**
* the passive uploads covering its window have all landed (PPG-metrics results,
  raw activity packets, engine/step packets), **and**
* it is still today's, **and**
* it does not overlap a recording the user made themselves — the detection
  algorithm keeps running during a manual recording, so the same minutes can
  arrive twice, and the user's own recording wins.

A detection that fails any of those is simply absent. Ones from an earlier day
are retired automatically (there is nowhere left to answer them), as are ones
already answered.

Both of the first two conditions matter, and the first is not redundant: every
"is it all uploaded?" predicate is vacuously true for a window holding no rows,
and a window the band has not sent yet holds none — so without the sync-frontier
check a detection would be published the instant its bookend arrived, which is
when its data is *least* likely to have reached the server.

That gate is what makes `confirmDetectedActivity` a submit-now rather than a
submit-eventually, and it is why the confirmed activity is indistinguishable
from one the user recorded: same `SB_RecordingSubmission` row, same job queue,
same locally-built report, same `pendingSubmissionsPublisher` /
`localRecordingEntries()` surfaces described in §3.5. A host that already
renders those needs no extra work for the tail of this flow — only the card that
asks the question.

The session is stamped `used_hrm`, because unlike a manually-logged session
there genuinely are biometrics behind the window: the band turned the PPG on for
it. The per-second continuous HR it captured uploads as **part of that submit**,
attributed to the workout — which is exactly why it is not one of the uploads
the readiness gate waits on. Uploading it early to satisfy the gate would send
it with no workout to attribute it to and cost the activity its HR graph.

`activityName` decides whether steps and distance belong on the report, so
prefer a name from your activity catalogue over free text.

> Detection is a device-side behaviour: bookends only arrive when the
> organisation's sensor configuration has the auto-activity algorithm enabled.
> Where it isn't, these calls are inert and the publisher stays empty.


---

## 4. Authentication


```swift
// Account checks
public func checkEmailAvailability(email: String) async throws -> SB_EmailAvailabilityOutcome
public func validateAccountRequirements(
    _ request: SB_ValidateAccountRequirementsRequest
) async throws -> SB_ValidateAccountRequirementsResult

// SDK auth (externally-authenticated, password-less users — SB-957, SB-1933).
// Configure `SB_SDK.sdkKeyCredentials` once (like `SB_SDK.environment`), then
// register with the user identity plus a single-use `sdkToken` your own
// backend minted — see §4.1.
public static var sdkKeyCredentials: SB_SDKKeyCredentials?   // host-supplied org creds; in-memory only, never persisted
public static var sdkTokenProvider: SB_SDKTokenProvider?     // how the SDK asks YOU for a single-use token
public typealias SB_SDKTokenProvider = @Sendable () async throws -> String
public func registerUser(
    userId: String,
    email: String? = nil,
    birthday: DateComponents? = nil,
    sex: SB_Gender? = nil,
    heightCm: Float? = nil,
    weightKg: Float? = nil,
    imperialUnits: Bool = false,
    activationCode: String? = nil,
    sdkToken: String? = nil        // single-use token from your backend; preferred credential
) async throws -> SB_RegisterUserOutcome

// Session
public func hydrateSession()                                          // restore from keychain
public func signOut() async throws                                    // see side-effects note below
public func generateTemporaryAuthToken() async throws -> String?

// Password
public func requestPasswordReset(email: String) async throws -> SB_RequestPasswordResetOutcome  // ⚠️ link-based; slated for removal — see internal-only code-based reset below
public func changePassword(currentPassword: String, newPassword: String) async throws -> SB_ChangePasswordOutcome

// Agreements (ToS / Health Data)
public func shouldRequestAgreement(type: SB_AgreementType) async throws -> SB_AgreementCheck
public func acceptAgreements(tosVersion: String, healthDataVersion: String) async throws
public func acceptCurrentAgreements() async throws
```




> **`signOut()` side effects.** A successful sign-out **unlinks the paired device from the account server-side**, disconnects any connected device, clears the paired-device state, nils out `pairedDevice` / `haveDevice` / `exerciseZoneAttributes`, and wipes the SDK's locally cached user data. The unlink is awaited before the logout RPC (it needs the session's credentials) and is best-effort — if it fails it is logged and the local teardown still completes, so the user is never stranded mid-sign-out. Signing out therefore costs the user their pairing: they re-pair the band on the next sign-in, which is deliberate and matches Android. `signOut()` is the **only** customer-facing way to clear SDK persistence — a wipe without a sign-out would leave in-memory `@Published` state and the BLE connection inconsistent with the cleared cache. Account-deletion flows should call `signOut()` after the delete-account call succeeds.

### 4.1 SDK registration (`registerUser`)

For third-party apps embedding the SDK, `registerUser` is a **register-or-login** entry point for users your app has already authenticated by its own means (your login, SSO, OAuth — the SDK doesn't care which). These users have **no** Sensor Bio email/password. On success the SDK persists the returned session and publishes `session` / `userProfile`. It is the **only** registration path in the distributed SDK — there is no email/password entry point.

**Your backend mints a single-use token first.** Your organization SDK Key (`sbsk_…`) is long-lived, org-wide, and identical for every one of your users — it must **never** ship inside your app or reach a device. Your backend exchanges it for a single-use, minutes-long `sdk_token` (`sbst_…`) and hands that to the app:

```
POST https://api.sensorbio.com/sdk/v1/token
Authorization: SDKKey sbsk_...
Content-Type: application/json

{}                                    # body optional; omit for the 5-minute default TTL
```

```json
{
  "sdk_token": "sbst_...",
  "organization_id": "uuid",
  "sdk_key_id": "uuid",
  "expires_at": "2026-09-03T12:34:56Z",
  "expires_in_seconds": 300
}
```

`sdk_token` and `organization_id` are the only two fields your backend has to return to your app. The flow is: your backend authenticates **its own** user however it already does → it calls the exchange → it returns those two values to your app → your app passes them to the SDK. Staging is `https://staging.api.sensorbio.com`.

> **Building that endpoint:** [§5](#5-minting-sdk-tokens--your-backend) covers it in full — the contract to serve your app, Node and Go implementations, every error the exchange returns and what to do about it, TTL choice, and how to rotate a key without signing your users out. The example app in this repo mocks that backend in-process so the SDK can be run without one; it is marked as a stand-in everywhere, because it holds an SDK Key on a device, which is the one thing the exchange exists to prevent.

A token is good for **exactly one** register-or-login and expires within minutes. **Mint a fresh one for every `registerUser` call, and never cache or reuse one** — a spent token fails inside `registerUser` as an authentication error, which is confusing to debug because the failure surfaces far from its cause. Revoking an SDK Key in the dashboard signs out every user currently signed in through it, on every device, in addition to preventing new sign-ins.

**Configure your org credentials too.** The SDK reads your organization credentials from `SB_SDK.sdkKeyCredentials`, which you set **once** (like `SB_SDK.environment`) before registering. The SDK holds them **in memory only — it never persists them**, and it uses them on every authenticated call for the session (not just registration). Because they are not persisted, a host that relaunches into a **hydrated** session (restored from the keychain) **must set `sdkKeyCredentials` again at launch, before the first authenticated call** (e.g. in `App.init`, alongside `SB_SDK.environment`).

```swift
public struct SB_SDKKeyCredentials: Sendable, Equatable {
    public let org_id: String     // organization UUID — the `organization_id` the exchange returned
    public let sdk_token: String  // your organization SDK Key; validated as active and belonging to org_id
    public init(org_id: String, sdk_token: String)
}

// e.g. in App.init, and again after a cold launch that hydrates a session:
SB_SDK.sdkKeyCredentials = SB_SDKKeyCredentials(org_id: organizationId, sdk_token: orgSDKKey)
```

> The `sdk_token` field name predates the token exchange and still carries the **organization SDK Key**, not the single-use token: it is what the authenticated RPCs *after* a register present, and the server only derives the SDK app source from a key there. The single-use token goes to the `sdkToken` parameter of `registerUser` and nowhere else. The field will be renamed when the authenticated path stops needing a key.

`registerUser` parameters:

- **`userId`** — your own stable identifier for the end-user (`client_sdk_user_id`). The first call for a given `userId` registers; subsequent calls log in. It is also recorded as the user's **username** (visible in the web dashboard).
- **`email`** *(optional)* — a contact email. Omitted if nil/empty; when supplied it is recorded on the backend as the user's contact email (never used as the login identity).
- **`birthday` / `sex` / `heightCm` / `weightKg` / `imperialUnits`** *(optional)* — demographics. **Any omitted value is filled with a dummy** before the request is sent: the platform requires height/weight/sex/birthday to compute higher-level metrics (recovery, calories, sleep scoring, …), so a user with none would break downstream processing. Pass real values when you have them.
- **`activationCode`** *(optional)* — redeems a device-subscription activation code during a first registration.
- **`sdkToken`** *(optional, strongly preferred)* — the single-use `sdk_token` your backend just minted. When supplied, it is the credential this call presents and your long-lived SDK Key never reaches the register RPC. Omitting it falls back to presenting the SDK Key itself, which is **deprecated** and can be refused per environment.

> Everything except `sdkToken` comes from `SB_SDK.sdkKeyCredentials` or the user identity — set the credentials once (above) and pass the fresh token per call. If `sdkKeyCredentials` is unset, `registerUser` returns `.failure(errorCode: "sdkKeyCredentialsNotSet")`.

```swift
// SB_SDK.sdkKeyCredentials must already be set (see above).
// `sdkToken` is a fresh one from your backend, used by this one call only.
switch try await sensorBio.registerUser(userId: userId, sdkToken: sdkToken) {
case .success(let session):        routeToHome(session)
case .failure(let errorCode):      showError(errorCode)   // e.g. "clientSdkUserIDAlreadyInUse"
}
```

```swift
public enum SB_RegisterUserOutcome: Sendable {
    case success(SB_Session)
    case failure(errorCode: String)
}
```

#### Let the SDK ask you for tokens instead (`sdkTokenProvider`)

Passing `sdkToken:` per call means handling re-authentication yourself at every call site. The alternative is to give the SDK a way to *ask*:

```swift
// once, next to SB_SDK.environment
SB_SDK.sdkTokenProvider = { try await myBackend.mintSDKToken() }

// then this is the whole flow, for the life of the integration
try await sensorBio.registerUser(userId: user.id)
```

The SDK calls the provider in exactly two situations, and holds nothing in between — it stores your closure, never a token:

1. **`registerUser` with no `sdkToken:`.** The provider supplies it.
2. **A live session died beyond recovery** — refresh token past its 60-day inactivity window, revoked, or the SDK Key it was signed under was revoked. The SDK mints a fresh token, logs the same `client_sdk_user_id` back in, and retries the authenticated call that hit the wall. Your app sees a successful call instead of `SB_AuthError.refreshTokenExpired`.

The closure runs off the main actor, and concurrent needs are single-flighted into one call (a dead session fails every in-flight RPC at once; they share one mint). **Throw to refuse** — a host whose own user is no longer authenticated should not mint a token, and the refusal surfaces as the auth error the call would have produced anyway. That decision being yours is exactly why this is a closure and not a credential: the SDK cannot mint a token itself, and must not be able to.

For (2) the SDK remembers your `client_sdk_user_id` in its keychain, so it can name the user to log back in. It is an identifier, not a credential — worthless without a freshly minted token — and `signOut()` erases it, so a deliberate sign-out is never undone by a re-establish.

Leave `sdkTokenProvider` nil and nothing changes: pass `sdkToken:` per call, catch `SB_AuthError.refreshTokenExpired`, and sign out plus re-register by hand.

**What is transparent to your app, and what is not:**

| Event | Handled by | Your app sees |
| --- | --- | --- |
| Access token expires (15 min) | SDK refreshes and retries | Nothing |
| Refresh token rotates | SDK | Nothing |
| Refresh chain dies (60-day inactivity, revoked, SDK Key revoked) | SDK, **if** `sdkTokenProvider` is set | Nothing — one provider call |
| Same, with no provider (or the provider throws) | You | `SB_AuthError.refreshTokenExpired` → sign out, re-register with a fresh token |

---

## 5. Minting SDK tokens — your backend

§ 4 is the app side. This is the other half: the one endpoint **your server** implements, and the rules that come with it. Written for whoever runs that server, who may not be the person integrating the app.

### Why this lives on your server

Your SDK Key (`sbsk_…`) is one long-lived credential for your whole organization, identical for every one of your users. Anyone holding it can create or sign into accounts in your organization — for any user id they can obtain, and user ids are not secret (your own support staff see them in the dashboard, as does anyone who has ever had that access).

So the key must never be somewhere an attacker can reach it, and "inside your mobile app" is somewhere an attacker can always reach it: a shipped binary is not a secret, whether the key is compiled in or fetched from an endpoint of yours at runtime.

The exchange makes possession of a key insufficient. Your backend keeps the key, authenticates your own user, and mints a token worth exactly **one** sign-in for **one** user for a few minutes.

| Credential | Who holds it | Lifetime | Worth if leaked |
| --- | --- | --- | --- |
| SDK Key (`sbsk_…`) | your backend, only | until you revoke it | the ability to mint tokens; revocable, and revoking it signs out live sessions |
| SDK token (`sbst_…`) | your app, briefly | 5 min default, **single use** | one register-or-login, one user, inside that window |
| Access token | your app | 15 min | that one user's data until it expires |
| Refresh token | your app | 60 days of inactivity | that one user's session until sign-out or key revocation |

Nothing the app holds is organization-wide.

### The contract you serve to your app

Your app needs two values from you. Everything else is your choice — path, auth, shape:

```json
{
  "sdk_token": "sbst_…",
  "organization_id": "3f7c1a20-9b4e-4c11-a0d2-71f0c9a8e512"
}
```

A workable default is `POST /sdk/token` on your existing API, authenticated the way the rest of your API is (session cookie, bearer token, whatever you already use). It takes no request body: the user is whoever your own authentication says they are.

### The call you make to Sensor Bio

The request and response are the ones shown in §4.1. The request body is optional and every field in it is optional too — an empty object, or no body at all, is the common case:

| Field | Required | Notes |
| --- | --- | --- |
| `expires_in_seconds` | no | 30 to 1800. Omit for the 5-minute default. |
| `sdk_key_id` | no | Which of your SDK Keys the token is anchored to. Only meaningful on the `APIKey` path below. |

The response carries `Cache-Control: no-store`. The raw token is shown exactly once — only a hash of it is stored on our side, so there is no way to look it up again.

**Authentication.** Send exactly one of:

- `Authorization: SDKKey sbsk_…` — your SDK Key. The key you present is itself the anchor, so nothing is ambiguous. **Preferred.**
- `Authorization: APIKey sbak_…` — your organization API Key, offered so a backend that already holds one need not also deploy an SDK Key. The anchor is then resolved from your usable SDK Keys, and you must pass `sdk_key_id` if you have more than one.

**Protocol.** The API requires HTTP/2. Every modern HTTP client uses it automatically over TLS. If you get an HTTP `464`, something in your stack forced HTTP/1.x — check for an explicit version flag, a proxy, or a load balancer in front of your egress.

**Verify your key before writing any code:**

```bash
curl -sS -X POST https://staging.api.sensorbio.com/sdk/v1/token \
  -H "Authorization: SDKKey $SENSORBIO_SDK_KEY" \
  -H 'Content-Type: application/json' \
  -d '{}'
```

A token back means your credential works and the exchange is reachable. That separates "my key is wrong" from "my integration is wrong", which is worth knowing before you debug anything else.

### Four rules that actually bite

**Authenticate your own user first.** This endpoint cannot do it for you, and the token it returns is enough to create an account in your organization. Mint only after your own authentication has succeeded, and only for the user it succeeded for. An endpoint of yours that mints for any caller is the leak you just eliminated, wearing a different hat.

**One token per sign-in. Never cache one.** Tokens are single-use. A cache hands an already-spent token to the next caller, and the failure surfaces as an authentication error *inside* `registerUser` — far from the cache that caused it. Mint fresh every time, including every time the SDK asks again.

**Don't put the user id in the request.** Sensor Bio does not need to know your user. The token is anchored to your organization; your app tells the SDK which of your users it is registering.

**Prefer a random, opaque user id.** The identifier your app hands the SDK (`client_sdk_user_id`) is yours to choose. Generate a random one per user and keep the mapping on your side, and Sensor Bio never holds an identifier that means anything in your systems. Whatever you choose must be **stable for that user** — the first register for an id creates the account, and every later call with the same id signs the same person back in.

### Errors

The error body is `{"status": …, "title": …, "detail": …}`.

| Status | Meaning | What to do |
| --- | --- | --- |
| `401` | The credential was rejected. Unknown, revoked and expired keys answer **identically**, by design. | Check all three: the whole key was copied, it has not been revoked, it has not expired. |
| `403` | Your organization has no usable SDK Key. | Create one under Developer Settings. |
| `400` | An out-of-range `expires_in_seconds`, or an `sdk_key_id` that is unknown or was required and omitted. | Fix the parameter. `expires_in_seconds` must be 30–1800. |
| `464` | The request arrived over HTTP/1.x. | Enable HTTP/2 (see above). |
| `5xx` | Our problem, almost certainly not your credential. | Retry; if it persists, contact developers@sensorbio.com. |

Surface the upstream status to your app rather than collapsing everything into "token error" — a 401 from us and a failure of your own user authentication want different handling, and only your backend can tell them apart.

### Reference implementations

Both do the same three things: authenticate your user, exchange, return two fields.

**Node (Express):**

```js
app.post("/sdk/token", requireYourAuth, async (req, res) => {
  const upstream = await fetch("https://api.sensorbio.com/sdk/v1/token", {
    method: "POST",
    headers: {
      Authorization: `SDKKey ${process.env.SENSORBIO_SDK_KEY}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });

  if (!upstream.ok) {
    const detail = await upstream.text();
    return res.status(502).json({ error: "sdk_token_exchange_failed", upstream_status: upstream.status, detail });
  }

  const { sdk_token, organization_id } = await upstream.json();
  res.set("Cache-Control", "no-store").json({ sdk_token, organization_id });
});
```

**Go:**

```go
func mintSDKToken(ctx context.Context, sdkKey string) (token, orgID string, err error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.sensorbio.com/sdk/v1/token", strings.NewReader("{}"))
	req.Header.Set("Authorization", "SDKKey "+sdkKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<10))
		return "", "", fmt.Errorf("exchange failed (HTTP %d): %s", resp.StatusCode, body)
	}

	var out struct {
		SDKToken       string `json:"sdk_token"`
		OrganizationID string `json:"organization_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", "", err
	}
	return out.SDKToken, out.OrganizationID, nil
}
```

Keep the key in your secret manager or environment, never in source control, and never log it. Log tokens by prefix only (`sbst_ABCD…`) if at all — we store that same prefix, so it is the half worth quoting in a support request.

### Choosing a lifetime

The default 300 seconds is generous, because the token should be minted at the moment it is used: your app asks, you mint, it registers, the token is spent. Seconds, not minutes.

Longer lifetimes only widen the window in which a token intercepted in transit is still worth something. Mint on demand and leave the default alone; reach for `expires_in_seconds` mainly when testing what your app does with an expired token.

### Revoking and rotating keys

Revoking an SDK Key in the dashboard **signs out every user currently signed in through it**, immediately and on every device, as well as preventing new sign-ins. Accounts and data are untouched, and people sign back in as soon as your backend is minting with a working key. That makes revocation your mass-logout lever for a suspected compromise, and it makes an unplanned revocation disruptive.

To rotate without signing everyone out at once, do it in this order:

1. Create the new SDK Key.
2. Switch your backend to it and confirm tokens mint.
3. Only then revoke the old one — the sessions anchored to it end at that moment.

Multiple keys are also how you separate environments: a "staging app" key and a "production app" key can be revoked independently.

### Evaluating before you have a backend

The **example app in this repository does the exchange in-process**, mocking the backend described here so the SDK can be run end to end without one. It is marked as a stand-in everywhere it appears — in `SDKTokenExchange.swift`, in the example app's README, and on the register screen itself — because it does the one thing this section exists to prevent: it holds an SDK Key on a device.

Read it as a worked example of the request, the response, and what the app does with the result. Do not copy it into an app you ship. If you would rather run the stand-in outside your app while you integrate, ask developers@sensorbio.com — a throwaway local server that serves exactly the contract above is available.

### Checklist

- [ ] SDK Key lives in your secret manager, is not in source control, and is never logged.
- [ ] Your minting endpoint requires your own authentication and mints only for that user.
- [ ] Nothing caches, stores, or reuses a token.
- [ ] Your app receives only `sdk_token` + `organization_id`.
- [ ] The upstream status reaches your app in a form it can act on.
- [ ] `client_sdk_user_id` is stable per user, and ideally random and opaque.
- [ ] Rotation is create → switch → revoke, and you know revocation signs out live sessions.

---

## 6. BLE Device Control

### 6.1 Pairing

Pairing is **one SDK-owned transaction**, not a sequence of host calls. Three methods open, advance, and close it; everything in between is reported on `$pairingState`.

```swift
public func beginPairing()                 // open a transaction, start scanning
public func selectDevice(_ id: String)     // pair with one of the discovered bands
public func endPairing()                   // cancel, or dismiss a terminal state; idempotent

@Published public internal(set) var pairingState: SB_PairingState?
```

```swift
public enum SB_PairingState: Equatable, Sendable {
    case scanning([SB_DiscoveredDevice])          // cumulative, de-duplicated
    case connecting(SB_DiscoveredDevice)
    case awaitingConfirmation(SB_DiscoveredDevice) // band is blinking; user must press its button
    case paired(SB_PairedDeviceState)              // terminal
    case failed(SB_PairingFailure)                 // terminal
}

public enum SB_PairingFailure: Equatable, Sendable {
    case scanTimeout, connectTimeout, connectionLost,
         notConfirmed, deviceUnavailable
}
```

Render the state; make three calls:

```swift
sensorBio.$pairingState
    .receive(on: DispatchQueue.main)
    .sink { state in
        switch state {
        case .scanning(let devices):    showList(devices)          // tap → selectDevice(id)
        case .connecting:               showConnecting()
        case .awaitingConfirmation:     showPressTheButton()
        case .paired(let device):       showAllSet(device)         // dismiss → endPairing()
        case .failed(let reason):       showCantReachBand(reason)  // dismiss → endPairing()
        case nil:                       showStartScreen()
        }
    }
    .store(in: &cancellables)

sensorBio.beginPairing()
```

**What the SDK does inside the transaction**, so the host doesn't: scanning and discovery de-duplication; re-issuing the scan when Bluetooth authorization is granted mid-scan (CoreBluetooth silently drops a scan issued before the central reaches `poweredOn`); connecting; the on-band confirmation choreography (blink + buzz, listening for the button, acknowledging the press, and refusing a late press once the window closes); persistence; server registration; configuring the band over the link that is already up; and every timeout.

> **Nothing is persisted, registered, or reported to the server until the user confirms on the band.** A transaction that ends any way other than `.paired` — cancelled, timed out, dropped — leaves **no trace**: no persisted device, no BLE registration, no server-side link event. There is nothing for the host to undo, which is why no un-pair or reset call is needed on the failure paths.

`.paired` means the band is fully ready: persisted, registered, reported, and **configured** — no reconnect is required. The two terminal states persist until `endPairing()`, so a host showing an "all set" or "can't reach the band" screen keeps the transaction open until that screen is dismissed. The SDK suppresses the forced-firmware prompt (`updateRequired`) and BLE auto-reconnect for the life of the transaction.

**Connect, unpair & paired-device state**

```swift
public func connect(_ id: String)                          // manual reconnect; not needed for pairing
public func disconnect(_ id: String? = nil)
public func removeDeviceFromPairedDevices(_ id: String)    // unpair: also clears the persisted store
public func clearPairedDevice()                            // wipe the paired snapshot (e.g. fresh-onboarding reset)
public func reclassifyPairedDevice(macAddress: String, name: String, type: SB_BluetoothDeviceType)
public internal(set) var isSigningOut: Bool                // true from signOut() until the next registerUser
```

The SDK owns paired-device persistence end-to-end — there is no app-built devices dictionary, and no host-side write on pair. `removeDeviceFromPairedDevices(_:)` clears it on an explicit unpair; `clearPairedDevice()` wipes the snapshot outright; `signOut()` clears it too, and additionally unlinks the device server-side. Hosts do **not** need to call `updateUserDeviceInfo(…, unlinkDevice: true)` themselves on logout. `isSigningOut` is read-only state the SDK uses to gate BLE auto-reconnect across the signed-out window.

`reclassifyPairedDevice(…)` exists for one case: a band flashed onto different firmware **is** a different device type from then on, and the BLE layer reports a paired band's type from what was registered out of *storage*, not from the hardware. Leave storage alone after an Alter → Sensr migration and the band reconnects still classified as an Alter, `updateRequired` fires again, and the flash repeats forever. It is not part of pairing.

Static bootstrap accessor (callable before `SB_SDK.shared` initializes):

```swift
public static var persistedDevicesDictionary: [String: AnyObject]?      // persisted devices dict (devicesKey)
```

### 6.2 Device commands

```swift
public func userLED(red: Bool = false, green: Bool = false, blue: Bool = false,
                    blink: Bool = false, for seconds: Int) async throws
public func hapticMotor(pulse: Bool = false, intensity: Int, for seconds: Int) async throws
public func setAskForDeviceResponse(_ enable: Bool)
public func airplaneMode() async throws
public func reset()
public func updateFirmware(_ url: URL, delay: Int? = nil, size: Int? = nil) async throws
```

These are raw device commands. **Pairing does not require any of them** — `beginPairing()` runs the LED/haptic confirmation and the button listening itself (§6.1). Reach for `userLED` / `hapticMotor` / `setAskForDeviceResponse` only for your own device interactions outside a pair.

**Firmware debug hooks.** Gated behind `SENSORBIO_INTERNAL`; absent from the binary.

```swift
public var debugOfferFirmwareUpdate: Bool                  // offer a reflash of the version already on the band
public var debugFailFirmwareUpdate: Bool                   // drop the link ~20% into the next flash
```

Both exist to rehearse the firmware failure → band reset → retry path on demand, which is otherwise hard to provoke deliberately and easy to regress silently.

`debugOfferFirmwareUpdate` forces `updateSuggested` and points `latestFirmwareVersion` at the device's current firmware, so an update can be triggered without a newer release existing. It takes effect immediately — the update decision re-runs on assignment rather than waiting for a reconnect — and deliberately overrides the white-label firmware gate and the Alter/UART-migration special cases, since it means "let me trigger an update now".

`debugFailFirmwareUpdate` fails the next flash about 20% in by dropping the BLE link. Dropping the link rather than throwing is what makes it faithful to a real interrupted update: the band is left holding a partial image, the host takes its disconnect-during-update path, and the band reset that clears the partial image cannot be delivered until the band returns — so the host's deferral of that reset is exercised too. Leave it on to watch the failure, turn it off and retry to watch the recovery.

### 6.3 Recording

Recording is fully SDK-orchestrated — there is no low-level start/stop surface; the SDK owns the BLE session lifecycle end-to-end.

**High-level orchestrations.** Each runs a session end-to-end: BLE start/stop, timer (fixed-duration countdown or open-ended count-up), post-stop sync wait, session build, and submission. Three completion paths each: natural completion (countdown modes only) / early-finish-with-submit via `finishCurrentRecording()` / cancellation via `Task.cancel()`. Submission is automatic — there is no separate "submit" call.

```swift
@MainActor
public func recordDetailedBiometrics(
    duration: TimeInterval,
    minDuration: TimeInterval
) async throws

@MainActor
public func recordMeditation(
    duration: TimeInterval,
    minDuration: TimeInterval,
    sessionName: String? = nil,
    sessionNameAlreadyExists: Bool = false
) async throws

@MainActor
public func recordActivity(
    activityName: String,
    minDuration: TimeInterval
) async throws

public func finishCurrentRecording()        // signal: "user tapped End Recording"; persists the stop intent synchronously

public func pauseRecording()                // freeze the timer + stop the device stream
public func resumeRecording()               // restart the device stream + resume the timer
```

`recordActivity(...)` is open-ended — it has no `duration:` parameter and runs until `finishCurrentRecording()` flips or the calling `Task` cancels. `recordingState` publishes `.recording(elapsed:, target: nil)` so countdown UIs render count-up format from the `nil` target.

**Tick cadence vs. publish cadence (SB-1949).** The orchestration loop runs at 250ms, but `recordingState` is published **only when the whole second changes** — at most once per second — and the `elapsed` it carries is floored to that whole second. Hosts driving a `MM:SS` display or a `target - elapsed` countdown see no difference; hosts that were relying on sub-second `elapsed` resolution will now see integer seconds. The 250ms loop is retained because it is also the poll interval for `finishCurrentRecording()` and for countdown expiry, so End Recording latency and auto-stop precision are unchanged.

**All three are `@MainActor`.** They drive `recordingState` / `canFinalize` from a 250ms tick, and those are `@Published`, so the loop has to run on the main actor or SwiftUI observers get "Publishing changes from background threads is not allowed". `SB_SDK` itself is not main-actor-isolated, so a non-isolated `async` method would have hopped straight off the main actor and published from the cooperative pool. Source-compatible for callers: `await`ing from any context still works, and callers already on the main actor (the usual case for a UI-driven recording) see no change.

**Pause / resume** (`recordActivity` + `recordMeditation`). `pauseRecording()` freezes the elapsed clock (`recordingState` holds its last `.recording(elapsed:, target:)` value and `canFinalize` stops advancing) and stops the device's manual PPG stream, so the paused span carries no biometric data. `resumeRecording()` restarts the stream and continues the clock. Both are no-ops outside an active recording; the device stop/start is a fire-and-forget BLE round-trip so the timer freezes/thaws instantly. Each paused window is submitted as the complement `activeWorkoutSegments` on the finished session, so downstream sees only the active spans.

**Live HR for the recording (`recordingHRSeries`, SB-1968).** A recording's HR chart should be bound to `recordingHRSeries`, not accumulated from the `hr` publisher.

`hr` is a live BLE passthrough: it emits only while the band is connected and streaming. A chart built from it therefore carries a hole exactly the width of any Bluetooth disconnect — which is a normal event during a workout, not an error. The data is not lost. The band keeps logging its own per-second HR through a disconnect, and the next sync delivers it; but reassembling that into a correct series means unioning two on-device tables, filtering implausible values, excluding the spans the user paused, re-reading on each sync, and anchoring the whole thing at the recording's start. The SDK does all of it:

```swift
@Published public internal(set) var recordingHRSeries: [SB_TimeValuePoint] = []   // ascending by timestamp
@Published public internal(set) var recordingPauseSegments: [SB_TimeSegment] = []
```

Lifecycle — it is *the current or most recent recording's* series:

* cleared and re-seeded when a recording starts;
* live samples append as they arrive;
* **every completed sync republishes it**, which is where a disconnect's gap closes. Points land *inside* the series, so treat each emission as a new array rather than diffing the tail — a chart that only appends will draw the wrong thing;
* a recording **restored after an app kill** seeds from the on-device tables across the whole `[start, now]` window, so it returns complete instead of restarting at the moment the host re-subscribed;
* **finalize leaves it standing.** Finalize runs for up to ~68s, and clearing at the stop tap would blank a host's chart underneath its own "Syncing…" screen. The next recording's start is what resets it.

**Paused spans are excluded from the series**, and `recordingPauseSegments` says where they were. Shade those; leave other gaps alone. Do not infer pauses from gaps in the series — since it back-fills, a surviving gap usually means the band captured nothing there (off-wrist, poor contact), which is not the same thing and should not read as "you paused". Completed windows only; a pause in progress appears on resume, and `isRecordingPaused` covers the live state.

Note that `getHRPoints(date:)` is **not** a substitute. It answers "what was this person's HR today" from the periodic algorithm output and does not see the dense per-second recording trace at all — a short workout can be complete in one and absent from the other.

`recordingHRSeries` and the finalize report (`activityReport`) are built from the same underlying window read **and exclude paused spans the same way**, so the live chart and the report the user opens seconds later agree — including in their min / avg / max and zone breakdown. This also matches the server, which filters a workout's HR by `activeWorkoutSegments`. The paused spans are still drawn as bands on the report; there is simply no line under them.

**Manual session logging.** For "log an activity that happened earlier" (no live recording, no device involvement). The SDK builds the session from the typed inputs and queues it for upload.

```swift
public func createActivitySession(
    activityName: String,
    startDate: Date,
    duration: TimeInterval
)
```

Observable orchestration state — gates the recording UI:

| Property | Type | Description |
|---|---|---|
| `recordingState` | `SB_RecordingState` | `.idle` / `.recording(elapsed, target)` / `.finalizing(phase)` |
| `canFinalize` | `Bool` | True once `elapsed ≥ minDuration` AND at least one HR sample has arrived |
| `isRecordingPaused` | `Bool` | True while the recording is paused (see `pauseRecording()`); drives the Pause/Resume button |
| `recordingHRSeries` | `[SB_TimeValuePoint]` | The recording's complete HR series — live samples merged with what synced from the band, gaps back-filled, paused spans excluded, anchored at the recording's start. Bind a live chart to this (see below) |
| `recordingPauseSegments` | `[SB_TimeSegment]` | The recording's completed pause windows, for shading those spans on that chart |

Throws `SB_RecordingError`:

```swift
public enum SB_RecordingError: Error {
    case alreadyRecording
    case noPairedDevice
    case bleStartFailed(underlying: Error)
    case bleStopFailed(underlying: Error)
    case tooShort(elapsed: TimeInterval, minimum: TimeInterval)
    case insufficientData    // detailed-biometrics only
}
```

**Persist + restore across app kill.** The SDK persists every in-flight `record*(...)` orchestration on entry and clears the envelope on every terminal path. If the host process is killed mid-recording, `SB_SDK.init()` re-publishes the matching `recordingState` synchronously on next launch and decides what to do with the envelope, in this order:

1. **Stop already requested** (`isStopRequested`, or a legacy stop-date newer than the envelope's start) — the user tapped End before the kill, so the recording is **over**. It is finalized at the persisted stop time and submitted; it is never resumed. `recordingState` comes up `.finalizing(...)`, not `.recording(...)`.
2. **Abandoned** (`isAbandoned` — in flight longer than `SB_PersistedRecording.maxInFlightDuration`, 12h) — nobody ended it and there is no defensible end timestamp, so the *session* is discarded rather than invented. The window's packets still upload via the normal passive path, so no biometrics are lost.
3. **Expired** (fixed-duration, past its expected end) — skip the remaining countdown and finalize.
4. **Otherwise** — resume the countdown / open-ended count-up.

**A recording killed while paused comes back paused (SB-1968).** Pause state was in-memory only, so restore previously resumed it as running: the user paused, killed the app, returned, and the recording had quietly carried on — its paused span counted as active time, plotted on the chart, and submitted as an active segment. The envelope now carries the open pause (`pausedAtEpochMs`) and restore re-publishes `isRecordingPaused == true` with the elapsed clock still frozen. Hosts already binding to `isRecordingPaused` for their Pause/Resume button need no change; hosts that assumed a restored recording is always running should stop assuming it.

Case 1 is the important one: `finishCurrentRecording()` persists the stop request **synchronously, at the moment it is called**, before it signals the orchestration and before any BLE stop goes out. So "the user tapped End" survives a kill anywhere from the tap onward — including the up-to-250ms gap before the recording loop notices the flag. Previously that fact lived only in memory, so a kill mid-finalize resurrected the recording on the next launch — and because `.activity` envelopes have no expiry, an activity recording could be resurrected on *every* launch indefinitely.

Submission still flows automatically. Host viewmodels rebind via `awaitActiveRecordingCompletion()` — same `async throws` shape as the original `record*(...)` call.

```swift
public var activeRecording: SB_PersistedRecording? { get }
public func awaitActiveRecordingCompletion() async throws
public func cancelCurrentRecording()
```

- `activeRecording` is non-nil whenever `recordingState != .idle`. Read on launch to decide whether to route the user to the matching recording view.
- `awaitActiveRecordingCompletion()` no-ops when no restore is in flight, so host VMs can call it unconditionally. Cancellation forwards to the underlying SDK-owned task — the existing "cancel my local Task on End-Recording" pattern keeps working unchanged.
- `cancelCurrentRecording()` is the explicit cancel for restored recordings (no host-side `Task` to cancel). Fresh recordings still cancel by cancelling the caller's `Task` directly.

The persisted envelope:

```swift
public enum SB_PersistedRecordingKind: String, Codable, Sendable, Equatable {
    case biometrics, meditation, activity
}

public struct SB_PersistedRecording: Codable, Sendable, Equatable {
    public let kind: SB_PersistedRecordingKind
    public let startEpochMs: Int64
    public let duration: TimeInterval?              // nil for .activity
    public let minDuration: TimeInterval
    public let sessionName: String?
    public let sessionNameAlreadyExists: Bool
    public let activityType: SB_ActivityType?       // .activity only
    public let activityName: String?                // .activity only
    public let stopRequestedEpochMs: Int64?         // nil while still running
    public let stopConfirmedEpochMs: Int64?         // nil if the band never acked
    public let pauseSegments: [SB_TimeSegment]?     // nil on envelopes written before SB-1968
    public let pausedAtEpochMs: Int64?             // nil unless a pause was open when this was written
    public var startDate: Date { get }
    public var endDate: Date? { get }               // nil for .activity
    public var isExpired: Bool { get }
    public var stopRequestedDate: Date? { get }
    public var stopConfirmedDate: Date? { get }
    public var isStopRequested: Bool { get }
    public var isAbandoned: Bool { get }
    public static let maxInFlightDuration: TimeInterval  // 12h
}
```

- `stopRequestedEpochMs` is written **before** the BLE stop goes out, so the user's intent to end the recording is durable across a process kill. It is also the session's end timestamp — deliberately not "whenever finalize happened to complete", which after a kill can be a different day.
- `stopConfirmedEpochMs` records that the *band* acknowledged the stop. Tracked separately because the remedies differ: user intent is final at the tap, whereas an unconfirmed device stop is re-delivered on the next full configure. Diagnostic — no finalize decision reads it.
- `pauseSegments` carries the recording's completed pause windows so they survive a process kill (SB-1968). Without them a restored recording would back-fill `recordingHRSeries` straight through a span the user deliberately paused. `nil` means an envelope written before the field existed, and is read as "no pauses".
- `pausedAtEpochMs` is the open half of the same pair: a window only joins `pauseSegments` on resume, so an app killed while the user sat paused used to lose that pause entirely — the recording restored as **running**, back-filled the span onto the chart, and submitted it as active. It is now what lets restore bring the recording back paused (see below); the window stays open, and closes on the user's own resume.
- `isAbandoned` bounds an envelope's lifetime. `.activity` is open-ended, so `endDate` (and therefore `isExpired`) is structurally `nil`/`false` for it and nothing else caps how long one may sit in flight.


### 6.4 Sync — automatic

Sync runs automatically once a paired device connects. No customer-side method call is required to trigger it; the SDK manages the sync lifecycle internally and emits state changes via the `@Published` `deviceSyncing` / `percentSynced` / `lastSyncd` properties (see §3.2).

**Upload is automatic too.** Every data type the device produces — biometrics, activity, steps, temperature, and **sleep** — is uploaded to the server by the SDK with no customer-side trigger. Uploads are driven off sync completion and a persistent, retrying job queue that survives app relaunches and waits for connectivity, so there is nothing to call and nothing to schedule. (Sleep upload previously exposed `SB_OnDeviceSleepDecoder.launchSleepUploadThread()`; that is removed — sleep is now handled internally like every other type.)

---

## 7. Server APIs (async/await)

Every method below is `async throws` on the `SB_SDK` facade. All return typed `SB_*` domain models; authentication is automatic once the user is signed in. Outcome-style methods (e.g. `registerUser`, `updateGoals`) return discriminated enums rather than raw errors for common business cases.

**Caching (dashboard + detail reads).** These reads are disk-cache-backed. The policy has three cases:

- **Today** (any granularity) is always fetched fresh so the latest server data wins. The response is still cached, and on a network failure the last cached payload is returned — a cold relaunch with no connectivity shows stale "today" instead of a blank screen.
- **A past date** is served straight from the on-disk cache with no network call — *but only once that cache is final*, i.e. it was written after the date's own calendar day ended. An entry cached while the date was still "today" is provisional (the day was still accumulating — a late device sync, a sleep the server scores hours later), so the first time you open that day *after it has passed* the SDK refetches once to finalize it, then serves from cache thereafter. This is transparent to the caller: keep calling `fetch…` on load and the SDK decides whether a network hit is needed.
- **`forceRemote: true`** (pull-to-refresh) always fetches, regardless of the above.

**Stale-while-revalidate streams.** Each cache-backed read also has an `…Updates(…)` variant returning `AsyncThrowingStream<T, Error>` that **yields the last cached value first (if any), then the fresh server value** — consume it with `for try await v in …`. This replaces the older synchronous `cachedX(for:)` peeks (removed): the peek read the store on the caller's (main) thread; the stream reads off-main and non-blocking (SB-1546), so `for try await` inside a `@MainActor` Task both paints instantly *and* keeps the UI thread free. On a fetch failure with a cached value present, the cached value is delivered and the stream finishes (no throw); with nothing cached it throws. `fetch…` (single value) is retained for pull-to-refresh (`forceRemote: true`) and one-shot reads. The stream variants: `dashboardUpdates(for:tzOffset:)`, `dailyHRUpdates(for:)` / `rangeHRUpdates(for:granularity:)` (and the HRV / RR / SpO2 equivalents), `stepsUpdates(for:granularity:)`, `caloriesUpdates(for:granularity:)`, `dailyActivityDetailUpdates(for:granularity:)`, `dailyRecoveryUpdates(for:)` / `rangeRecoveryUpdates(for:granularity:)`, `sleepDetailUpdates(endDate:endTimestamp:)`, `sleepAggregationUpdates(for:granularity:)`, and `workoutTimelineUpdates(for:)`. Each takes a trailing `forceRemote: Bool = false` (except `workoutTimelineUpdates`, whose page is always today). **Exceptions:** `dailyRecoveryUpdates` has no stale peek and yields once — its value is computed on-device, so a peek would only paint a stale server score first (see [Local-first recovery score](#local-first-recovery-score)). `dailyActivityDetailUpdates` is the same on its local-first `.day` path, and keeps the stale peek for `.week` / `.month` / `.year` (see [Local-first activity detail](#local-first-activity-detail)).

> **Non-blocking store access (SB-1546).** All SDK SwiftData reads/writes on the async path (`getSkinTemperature`, the cache reads/writes behind the streams, and the packet-upload queue ops) now suspend on the store's serial queue rather than blocking the calling thread. `getSkinTemperature(date:)` is therefore `async`.

> **`forceRemote` (pull-to-refresh).** Every cache-backed `fetch…` read takes a trailing `forceRemote: Bool = false`. When `true`, every cache shortcut is bypassed and the read always hits the network (still writing the fresh result to the cache, and still falling back to the cached payload on a network failure). Pass `forceRemote: true` from a user-initiated refresh. This is the escape hatch for data that changes after the fact — a device synced days later, or sleep/recovery **scores** the server finishes processing asynchronously after upload — on top of the automatic provisional-cache refetch described above.

### 7.1 Dashboard

```swift
public func fetchDashboardData(date: Date, tzOffset: Int32, forceRemote: Bool = false) async throws -> SB_DashboardData
```

Each ring on the dashboard is an `SB_DashboardCircularItem`:

```swift
public struct SB_DashboardCircularItem: Codable, Equatable, Sendable {
    public var value: Float
    public var processing: Bool     // server's own "still working" flag
}
```

> **`value` vs `processing` — read both.** `value` is **not** guaranteed to be `0…100`. The server sends `-100` for a sleep it has recorded but never scored, and negative recovery values are a documented sentinel meaning "no real score for the day" (pair with `SB_DashboardItemRecoveryStage.stageNotAvailable`). Treat **any non-positive `value` as "no score"**, and read **`processing`** for progress — the two are independent. Inferring progress from a missing or non-positive `value` is wrong: it cannot distinguish "recorded but unscoreable" from "still being worked on", and will leave a ring showing *Processing* forever.
>
> `data.sleep` is now populated whenever the server sends a sleep goal item, **including when its `value` is non-positive** (it was previously dropped to `nil` by a `value > 0` gate). `data.sleep != nil` therefore no longer implies "there is a score" — check `value > 0` for that, and use `data.sleeps` (the session list) to tell whether the server knows about any sleep session at all.

### 7.2 Activity reads

```swift
public func fetchSteps(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)        async throws -> SB_StepsTrending
public func fetchCalories(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)     async throws -> SB_CaloriesTrending
public func fetchDailyActivityDetail(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false, preferLocal: Bool = true) async throws -> SB_DailyActivityDetail
public func fetchDailyRecovery(date: Date, forceRemote: Bool = false, preferLocal: Bool = true) async throws -> SB_DailyRecoveryTrending
public func fetchRangeRecovery(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false) async throws -> SB_RecoveryRangeTrending
```

> **`fetchDailyRecovery` is computed on-device where possible** — see [Local-first recovery score](#local-first-recovery-score) below. `fetchRangeRecovery` (week/month/year) is unchanged and stays server-served.
>
> **`fetchDailyActivityDetail` likewise, for `.day`** — see [Local-first activity detail](#local-first-activity-detail) below. `.week` / `.month` / `.year` stay server-served.

`fetchDailyActivityDetail` returns the activity **score** plus a per-metric breakdown — steps, calories burned, distance, and active time — each carrying chart datapoints. The metrics reuse `SB_StepMetric` (switch on `metricType`: `.steps` / `.caloriesBurned` / `.distance` / `.totalDuration`):

```swift
public struct SB_DailyActivityDetail: Codable, Equatable, Sendable {
    public var score: SB_ActivityScore?
    public var metrics: [SB_StepMetric]
    public var isLocallyComputed: Bool       // true when this day was computed on-device
}

public struct SB_ActivityScore: Codable, Equatable, Sendable {
    public var score: Float                  // 0–100
    public var diffVsBaseline: Float
    public var diffVsLastGranularityValue: Float
    public var scoreDescription: String
    public var colorHex: String              // server-suggested; app may ignore
    public var progressPercentage: Float     // baseline-relative ring fill, NOT the score
}
```

`fetchDailyRecovery` / `fetchRangeRecovery` return the recovery **score** (via `goalItem`) plus the sleep-derived context that fed it. Both trending wrappers also carry the signed-in user's `joinedDate` (sourced from the profile, not the recovery payload) so the app can describe the averaging window:

```swift
public struct SB_DailyRecoveryTrending: Codable, Equatable, Sendable {
    public var graph: SB_DailyRecoveryGraph?
    public var joinedDate: Date?             // from the user profile, nil if unknown
    public var isLocallyComputed: Bool       // true when this day's score was computed on-device
}

public struct SB_RecoveryRangeTrending: Codable, Equatable, Sendable {
    public var graph: SB_RecoveryRangeGraph?
    public var joinedDate: Date?             // from the user profile, nil if unknown
}

public struct SB_DailyRecoveryGraph: Codable, Equatable, Sendable {
    public var goalItem: SB_DashboardItemRecovery
    public var variationPercentage: Float
    public var sleepTimeSeconds: Float
    public var restingHr: Float
    public var scoreFactors: [SB_RecoveryScoreFactor]   // daily only
    public var nocturnalHrv: Float?          // ms; local path only, nil when server-served
}

public struct SB_RecoveryRangeGraph: Codable, Equatable, Sendable {
    public var goalItem: SB_DashboardItemRecovery
    public var variationPercentage: Float
    public var sleepTimeSeconds: Float
    public var restingHr: Float
    public var recoveryScoreSection: SB_RecoveryScoreSection?
}
```

Each contributing factor reports its `percentile` (0–100) and a pre-computed `scoreValue` — the factor's weighted contribution to the recovery score, i.e. `percentile × weight` under `0.4·HRV + 0.4·RHR + 0.1·Sleep Efficiency + 0.1·Sleep Duration`. Colors are **not** returned; the app derives them from the percentile.

```swift
public struct SB_RecoveryScoreFactor: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var percentile: Float             // 0–100 (e.g. a nocturnal-HRV percentile of 73)
    public var scoreValue: Float             // weighted points, e.g. 73 × 0.4 = 29.2
}
```

#### Local-first recovery score

`fetchDailyRecovery(date:)` / `dailyRecoveryUpdates(for:)` keep their signatures and their `SB_DailyRecoveryTrending` return, but the **score behind them is now computed on-device** whenever the night is on the device (SB-1682). Unlike the `get…Points` family this is not a new entry point — it is the same trending read with a local source, so **no caller changes are required**.

The daily recovery score ranks last night against the user's own recent nights (server `GenerateRecoveryScore`):

```
score = round(100 · (0.4·fracHRV + 0.4·fracBPM + 0.1·sleepGoalAchieved + 0.1·sleepEfficiency))
```

- **fracHRV / fracBPM** — the share of the prior 30 days' nights whose resting HRV was no higher than last night's / whose resting BPM was no lower (both comparisons **inclusive**). Each night's resting values are derived from that night's on-device PPG with the same server-parity math the sleep detail uses (`CalculateRestingBPM` — the mean of the 5 lowest outlier-free BPM; `CalculateRestingHRV` — the residual-outlier-free OLS HRV-vs-time line evaluated at the last epoch);
- **sleepGoalAchieved** — `min(1, totalSleep / goal)` against the user's locally-cached sleep goal (an unset goal scores full credit);
- **sleepEfficiency** — `totalSleep / (totalSleep + excessAwake + excessLatency)`, where awake time up to 5% of total sleep and latency up to 20 minutes are free. Both sleep terms read the same clamped stage minutes the local sleep detail reports.

The returned graph carries the ring score + **stage** (`.restUp` <30 · `.goEasy` <50 · `.medium` <60 · `.ready` <75 · `.excellent` ≥75) and its message, the night's resting HR and total sleep, the **vs-average trend** (`variationPercentage`, measured against the mean of the last 30 days' locally-computed scores — which is why the read gathers 60 days of nights: each of those 30 prior days ranks against its *own* 30 priors), and the four **contributing factors** in the server's order — **Nocturnal HRV** (0.4), **Resting HR** (0.4), **Sleep Efficiency** (0.1), **Total Sleep Duration** (0.1, the sleep-*goal* term despite the name) — each with its percentile and its weighted point contribution.

**Incomplete nights are backfilled, not skipped.** A prior night whose sleep *window* is on device but whose data is not — the partial day a fresh login leaves behind, or a window persisted only for vitals tagging — would otherwise drop silently out of the ranking and shrink its denominator, moving the score with nothing to signal it. Two misses are detected and repaired on read, each attempted at most once per night per process:

- **no biometrics in the window** → the night's raw HR/HRV are fetched and persisted. A night straddles midnight, so **both** calendar days it touches are fetched;
- **no stage minutes** → the night's server sleep detail is fetched and its stage minutes persisted, which is what makes the night scorable and keeps it in the 30-day average. Minutes come from the detail's typed stage intervals, so nothing depends on a localized label.

Afterwards the night is served entirely from the device.

The read **falls back to the server** for a day the device cannot score the server's way:

- no on-device sleep for the day, or a night with a window but **no stage minutes** (such a night would evaluate both sleep terms to zero — a silent 20-point hole — so it is never scored, though it still counts as a *prior*, since it supplies resting values);
- the night has no resting BPM or no resting HRV;
- fewer than **four prior nights** with sleep / with resting BPM / with resting HRV — the server's five-nights-including-tonight gate. This window matters: the backend blends a population baseline to serve a **real** score on days 1–4, and that baseline is not on the device, so those days deliberately stay server-served rather than showing nothing.

**`nocturnalHrv`** carries the night's raw resting HRV in ms — the value, not the percentile the `scoreFactors` carry. The recovery payload has never had this, so a host wanting to show it had to make a second pair of sleep reads per day view just to recover one number; on the local path the score has already derived it, so it is surfaced for free. It is `nil` on the server-served path, where the host should fall back to the sleep detail's `restingHrv` (the same figure). Note that fallback genuinely needs the network for a **server-backfilled** night: the local sleep detail deliberately skips stage-less rows, since it cannot draw a stage timeline for a night the device never recorded.

`SB_DailyRecoveryTrending.isLocallyComputed` reports which source **actually** served the day, so a host can distinguish a genuine local score from a fallback rather than reporting the source it asked for. `preferLocal: false` (on both `fetchDailyRecovery` and `dailyRecoveryUpdates`) skips the on-device computation and reads the server's score; the default `true` keeps every existing caller local-first.

`dailyRecoveryUpdates` has **no stale peek** — unlike the other `…Updates` streams it does not pre-yield the last cached value. The local computation is fast enough to be the first emission, so peeking would paint a stale *server* score for a frame and then swap it. It yields once.

`forceRemote` applies to the **fallback fetch only** — it does not bypass the local computation, matching the rest of the offline-first family. Factor titles and stage messages are the SDK's own English strings (the server's are localized server-side) — the same trade-off the local sleep score makes.

> The dashboard's recovery ring comes from a **different** read (`fetchDashboardData`), not this one, and is still server-served.

#### Local-first activity detail

`fetchDailyActivityDetail(date:granularity:)` / `dailyActivityDetailUpdates(for:granularity:)` keep their return type, but a **`.day`** read is now rebuilt **on-device** from the day's activity rows (SB-1684) — score, baseline comparison and all four metrics. As with the recovery score this is not a new entry point, so **no caller changes are required**.

The daily activity score is a pure function of one day (server `GenerateActivityScore`) — no history, no statistical aggregation, no calibration, and so (unlike recovery) no gate it can fail:

```
score = round(100 · (0.8·min(1, activeCals/caloriesGoal) + 0.2·min(1, activeHours/12)))
```

- **activeCals** — the day's active calories, `Σ(totalStepCalories + workoutCalories − workoutStepCalories)` over the local activity rows. This is the same total the calories read reports as **Active** (`SB_CaloriesDataPoints.totalActiveCalories`), including the backend's per-minute `round(steps/10)` step-calorie cap — which the server applies in its DB row scan and **skips for workout minutes**. It is deliberately *not* `SB_StepsDataPoints.totalCalories`, which caps every minute including workout ones;
- **activeHours** — local hours with **more than 250** steps (strictly greater), off the same hourly buckets the steps read exposes;
- **caloriesGoal** — the user's active-calorie goal, cached locally from `fetchGoals()` / `updateGoals(…)`, with the server's 500 default substituted for an unset goal. Because the goal is the score's *divisor* rather than a soft term, a cold cache is warmed once per process from `fetchGoals()` rather than silently scoring against the default.

The ring's **fill** is not the score: the server publishes `progressPercentage` relative to a rolling baseline, and `diffVsBaseline` alongside it. Both are reproduced — the baseline is the same score recomputed for each of the prior **30 days** and averaged, published only once **5** prior days have a score, matching the server's gate (below that the server omits `progressPercentage` too, and a host falls back to the raw score). `progressPercentage` is a full **100** at or above the baseline and the shortfall as a percentage below it (server `util.CalculateProgressPercentage` with no goal — activity has no goal term, the baseline IS the target). The prior days are read **local-only, with no backfill**: a 30-day baseline that fetched every missing day would cost 30 round-trips on first open, and a day with no local rows simply does not contribute, which is how the server treats a date with no stored score.

> The Sensor Bio app fills its activity ring from **`score`**, not `progressPercentage`, so the baseline is reproduced here for API parity with the server payload (and with Android) rather than because the shipping app needs it.

The four **metrics** — Calories, Duration, Distance, Steps, in the server's order — carry their day total in `avgValue` and hourly `timeDatapoints` in the API's wall-clock-encoded-as-UTC convention. `.distance` is emitted in the user's **display unit** (km, or miles for an imperial profile, rounded to two decimals), as the API sends it; every other metric is SI. `name` / `unit` / `barChartTitle` are left **empty** — those are localized server-side and the SDK owns no strings, so a host that shows them supplies its own (the app does, in `ActivityMetricFormat`).

The read **falls back to the server** when the day has no activity rows on device even after a backfill attempt, and always for `.week` / `.month` / `.year` — those periods average the server's *stored* daily scores and aggregate from its rollup tables, which the device does not reproduce.

`SB_DailyActivityDetail.isLocallyComputed` reports which source **actually** served the day, so a host can distinguish a genuine local score from a fallback rather than reporting the source it asked for. `preferLocal: false` (on both `fetchDailyActivityDetail` and `dailyActivityDetailUpdates`) skips the on-device computation and reads the server's payload; the default `true` keeps every existing caller local-first.

As with recovery, `dailyActivityDetailUpdates` has **no stale peek on the local `.day` path** (it yields once) while the range granularities keep theirs, and `forceRemote` applies to the **fallback fetch only** — it does not bypass the local computation.

> Org custom / white-label activity scoring stays server-computed.

### 7.3 Biometric reads — HR / HRV / RR · SpO2 🚧 WIP

```swift
public func fetchDailyHR(date: Date, forceRemote: Bool = false)                                       async throws -> SB_BiometricDailyTrending
public func fetchRangeHR(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)      async throws -> SB_HRRangeTrending
public func fetchDailyHRV(date: Date, forceRemote: Bool = false)                                      async throws -> SB_BiometricDailyTrending
public func fetchRangeHRV(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)     async throws -> SB_HRVRangeTrending
public func fetchDailyRR(date: Date, forceRemote: Bool = false)                                       async throws -> SB_BiometricDailyTrending
public func fetchRangeRR(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)      async throws -> SB_RRRangeTrending

// 🚧 WIP
public func fetchDailySpO2(date: Date, forceRemote: Bool = false)                                     async throws -> SB_BiometricDailyTrending
public func fetchRangeSpO2(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)    async throws -> SB_SpO2RangeTrending
```

#### One daily shape for all four metrics (SB-1737) ⚠️ breaking

All four daily reads return the same `SB_BiometricDailyTrending`; the per-metric
`SB_HRDailyTrending` / `SB_HRVDailyTrending` / `SB_RRDailyTrending` /
`SB_SpO2DailyTrending` and their four graph types are **gone**. The metric is
identified by the call you made, not by the type. Range reads keep their
per-metric types — those graphs genuinely differ.

```swift
public struct SB_BiometricDailyTrending: Codable, Equatable, Sendable {
    public var graph: SB_BiometricDailyGraph?          // nil when the day has no processed data
}

public struct SB_BiometricDailyGraph: Codable, Equatable, Sendable {
    public var resting: Float                          // HR: resting HR · HRV: RMSSD · RR/SpO2: nocturnal average
    public var average: Float                          // whole-day mean, sleep included
    public var lowest: Float
    public var highest: Float
    public var baseline: Float                         // 30-day median, server-computed
    public var points: [SB_BiometricPoint]             // ascending by timestamp
    public var linearFit: SB_TimeValueStraightLine?    // recovery-rate fit; HRV-only today
}

public struct SB_BiometricPoint: Codable, Equatable, Sendable {
    public var timestamp: Int64                        // absolute ms epoch
    public var value: Float
    public var valueType: SB_BiometricValueType        // sleep / awake / outlier / abnormal-rhythm
}
```

**Migrating:**

| was | now |
| --- | --- |
| `graph.restingBpm` / `.rMssd` / `.brpm` / `.spo2` | `graph.resting` |
| `graph.rawAvg` / `.rawLowest` / `.rawHighest` / `.rawBaseline` | `graph.average` / `.lowest` / `.highest` / `.baseline` |
| `graph.heartRateTimeseriesPoints` | `graph.points` |
| `graph.rawSleepPoints` + `graph.rawDatetimePoints` (and the `…HrvPoints` pair) | `graph.points`, split by `valueType` (`.sleep` / `.awake`) |
| `graph.tzOffset`, `point.timezone` | **removed** — `timestamp` is an absolute ms epoch; render it in the viewer's own zone |
| `graph.startTimestamp` | **removed** — derive the axis start as `min(localMidnight, floorToHour(points.first))` |
| `graph.improvementVsBaseline` | **removed** — compute `resting - baseline`, sign-flipped where lower is better (HR, RR); `0` when `baseline <= 0` |
| `SB_HeartRateValueType` / `SB_HRVValueType` | `SB_BiometricValueType` (HR's case list; HRV's `.hrvOutlier` maps to `.sleepOutlier`) |
| `SB_HeartRateTimeValuePoint` / `SB_HRVTimeValuePoint` | `SB_BiometricPoint` |
| `line.lineColor` (`SB_LineColor`) | `line.rating` (`SB_ImprovementRating`) — pick your own colours |

`SB_TimeValuePoint` also loses `timezone`, so every graph that carries those
points (sleep biometrics, workout, activity, meditation, spot check) now hands
back `(timestamp, value)` only.

Range graphs lose `improvementVsBaseline` too, spell `Avg` out
(`averageBpm` / `average` / `averageBrpm` / `averageSpo2`, `rolling7DayAverage`),
and `SB_HRVRangeGraph.rawBaseline` is dropped as a duplicate of `baseline`.

Cached responses from an older build fail to decode once, are deleted, and
refetch — no migration step needed.

#### Local-first HR points

`getHRPoints(date:)` returns a day's HR samples **local-first**: it reads the day's on-device HR with **no** API round-trip when that data is already synced locally. Each point is tagged `.awake` / `.asleep` from the device's sleep sessions. Only when the day predates local sync (no local HR for the window) does it fall back to the API, backfill the HR + sleep locally, and rebuild — so a subsequent call for the same day is served entirely from the device.

The day a sample belongs to, and whether it counts as asleep, follow the server's daily-trending contract exactly (SB-1994). A day is **local midnight→midnight plus the full `[onset, wakeUp]` span of every sleep _filed under_ that day** — and a sleep is filed under the day it **ends**, not the day it began. So for a 10pm→7am night:

* asking for the **wake** day returns samples starting at **10pm the previous evening**, all tagged `.asleep`;
* asking for the day that night **started** returns midnight→midnight only, and its 10pm→midnight block is tagged `.awake`, because the sleep covering it belongs to the next day.

A point is `.asleep` **iff** it falls inside one of that day's own sleeps — not merely inside any sleep. Callers that plot these points must let the x-axis start before midnight, since the first sample routinely does.

The three **resting** figures (`restingHR` / `restingHRV` / `restingRR`) follow the server's other rule: each is derived from the day's **longest sleep alone**, by that metric's own algorithm — not by averaging the day's `.asleep` samples. A day with a nap therefore has one set of sleeps driving the point tags and a single, narrower window driving the headline number.

```swift
public func getHRPoints(date: Date) async throws -> SB_HRDataPoints

public struct SB_HRDataPoints: Codable, Equatable, Sendable {
    public let points: [SB_HRDataPoint]
    // Server-parity resting HR (`CalculateRestingBPM`): the mean of the 5 lowest
    // outlier-free samples of the day's LONGEST sleep — not a mean of the .asleep
    // points. nil when the day has no sleep, or fewer than 5 usable samples in it.
    public let restingHR: Int?
    // Computed on the fly from `points`; each is nil when `points` is empty.
    public var averageHR: Int?   // mean value of all points
    public var lowestHR: Int?    // min value
    public var highestHR: Int?   // max value
}

public struct SB_HRDataPoint: Codable, Equatable, Sendable {
    public let epoch: Int64          // ms
    public let value: Int            // bpm, rounded from the stored Float
    public let type: SB_HRPointType
}

public enum SB_HRPointType: Codable, Equatable, Sendable {
    case awake
    case asleep
}
```

`throws` only on the server-backfill path (e.g. `SB_AuthError.missingAuthToken` when signed out); the pure-local path never touches the network.

#### Local-first HRV points

`getHRVPoints(date:)` is the HRV sibling of `getHRPoints(date:)`: it returns a day's HRV samples **local-first**, reading the day's on-device HRV with **no** API round-trip when that data is already synced locally. HRV shares the same per-epoch `PPGResult` rows as HR (its own `hrvValue`/`hrvValid` slot). Each point is tagged `.awake` / `.asleep` from the device's sleep sessions, over the **same day window and sleep-filing rule as `getHRPoints(date:)`** — see above. Only when the day predates local sync (no local HRV for the window) does it fall back to the API, backfill the HRV + sleep locally, and rebuild — so a subsequent call for the same day is served entirely from the device.

```swift
public func getHRVPoints(date: Date) async throws -> SB_HRVDataPoints

public struct SB_HRVDataPoints: Codable, Equatable, Sendable {
    public let points: [SB_HRVDataPoint]
    // Server-parity nocturnal HRV (`CalculateRestingHRV`): the residual-filtered
    // regression line over the day's LONGEST sleep, read off at that night's last
    // epoch — not a mean of the .asleep points. nil when the day has no sleep, or
    // that sleep has too little HRV to fit.
    public let restingHRV: Int?
    // Computed on the fly from `points`; each is nil when `points` is empty.
    public var averageHRV: Int?         // mean value of all points (day average)
    public var lowestHRV: Int?          // min value
    public var highestHRV: Int?         // max value
}

public struct SB_HRVDataPoint: Codable, Equatable, Sendable {
    public let epoch: Int64          // ms
    public let value: Int            // rMSSD in ms, rounded from the stored Float
    public let type: SB_HRPointType  // .awake / .asleep (shared with HR)
}
```

`throws` only on the server-backfill path (e.g. `SB_AuthError.missingAuthToken` when signed out); the pure-local path never touches the network.

#### Local-first RR points

`getRRPoints(date:)` is the respiratory-rate sibling of `getHRPoints(date:)` / `getHRVPoints(date:)`: it returns a day's RR samples **local-first**, reading the day's on-device RR with **no** API round-trip when that data is already synced locally. RR shares the same per-epoch `PPGResult` rows as HR/HRV (its own `rrValue`/`rrValid` slot). Each point is tagged `.awake` / `.asleep` from the device's sleep sessions, over the **same day window and sleep-filing rule as `getHRPoints(date:)`** — see above. Only when the day predates local sync (no local RR for the window) does it fall back to the API, backfill the RR + sleep locally, and rebuild — so a subsequent call for the same day is served entirely from the device.

Unlike HR/HRV (whole-number `Int`), RR is inherently fractional, so every RR value — each point and every aggregate — is an **unrounded `Float`** in breaths per minute (brpm), matching the API day chart's own `brpm` values.

```swift
public func getRRPoints(date: Date) async throws -> SB_RRDataPoints

public struct SB_RRDataPoints: Codable, Equatable, Sendable {
    public let points: [SB_RRDataPoint]
    // Nocturnal RR: the mean over the day's LONGEST sleep, to one decimal — not a
    // mean of the .asleep points. The server takes an uncertainty-weighted mean of
    // the same window; local rows carry no per-capture uncertainty, so this is the
    // unweighted mean. nil when the day has no sleep, or that sleep carries no RR.
    public let restingRR: Float?
    // Computed on the fly from `points`; each is nil when `points` is empty.
    public var averageRR: Float?         // mean value of all points (day average)
    public var lowestRR: Float?          // min value
    public var highestRR: Float?         // max value
}

public struct SB_RRDataPoint: Codable, Equatable, Sendable {
    public let epoch: Int64          // ms
    public let value: Float          // breaths per minute (brpm), unrounded from the stored Float
    public let type: SB_HRPointType  // .awake / .asleep (shared with HR)
}
```

`throws` only on the server-backfill path (e.g. `SB_AuthError.missingAuthToken` when signed out); the pure-local path never touches the network.

#### Local-first Steps points

`getStepsPoints(date:)` returns a day's step intervals **local-first**: it reads the day's on-device steps (local midnight→midnight in the device time zone) with **no** API round-trip when that data is already synced locally. Steps live in their own `EnginePacket` table (steps / distance / calories / active-seconds columns), **not** the vitals' `PPGResult`, so there is **no** awake/asleep tag — each point is a per-interval activity reading. Only when the day predates local sync (no local steps for the window) does it fall back to the API, backfill the intervals locally (server rows marked already-uploaded), and rebuild — so a subsequent call for the same day is served entirely from the device.

The returned `SB_StepsDataPoints` computes the day totals and hourly buckets on the fly. Unlike the vitals aggregates these are **non-optional** (steps are counts, not a distribution) and default to `0`; use `points.isEmpty` to distinguish "no data on device" from a genuine zero-step day. Locally-synced points are per-minute, server-backfilled points per-hour; both aggregate identically.

```swift
public func getStepsPoints(date: Date) async throws -> SB_StepsDataPoints

public struct SB_StepsDataPoints: Codable, Equatable, Sendable {
    public let points: [SB_StepsDataPoint]
    // Computed on the fly from `points`; non-optional, 0 when there are no points.
    public var totalSteps: Int
    public var totalDistanceMeters: Float
    public var totalCalories: Float
    public var totalActiveSeconds: Int
    public var hourlyBuckets: [SB_StepsHourBucket]  // one per hour with points (gaps omitted)
}

public struct SB_StepsDataPoint: Codable, Equatable, Sendable {
    public let epoch: Int64          // ms
    public let steps: Int
    public let distanceMeters: Float
    public let calories: Float       // kcal, after the backend's per-minute round(steps/10) cap
    public let activeSeconds: Int
}

public struct SB_StepsHourBucket: Codable, Equatable, Sendable {
    public let hour: Int             // local hour of day 0…23
    public let steps: Int
    public let distanceMeters: Float
    public let calories: Float
    public let activeSeconds: Int
}
```

`throws` only on the server-backfill path (e.g. `SB_AuthError.missingAuthToken` when signed out); the pure-local path never touches the network.

#### Local-first Calories points

`getCaloriesPoints(date:)` is the calories sibling of `getStepsPoints(date:)`: it returns a day's calorie intervals **local-first**, reading them from the same on-device `EnginePacket` rows as steps (so there is **no** awake/asleep tag). It faithfully recreates the server's per-`PhysicalStats`-row calorie model — each interval's `totalStepCalories` is the **active** calories the band measured, split into a **step** and a **workout** part (`active = step + workout`). The band never reports the split on device, so it is reconstructed: on a locally-synced day from the day's **activities**, with each activity minute's calories **recomputed from HR** using the server's own per-minute model, and on a backfilled day from the server calories graph's authoritative per-hour split. Only when the day predates local sync does it fall back to the API — **one shared steps + calories backfill** (server rows marked already-uploaded) — then rebuild, so a subsequent call for the same day is served entirely from the device.

The calculation always runs **on device**. The SDK reaches the network only for *inputs* it does not hold, never for a server-computed calorie figure — which is why the number is reproducible offline once the inputs are cached. Two inputs are fetched and cached on demand (SB-2016):

- **The day's activity list.** Activity windows used to come only from recordings made on *this device since the last sign-out*, so a workout recorded on another phone — or before a logout or reinstall — was invisible and its calories silently read as `0`. The day's activity list is now fetched once from the server and cached on device, then merged with the local recordings (the local copy wins where both describe the same activity, since only it knows the pauses). A completed past day's cached list is final; today's is refreshed at most every 15 minutes, and a recording made on this device appears immediately without any refresh.
- **The HR those activities need.** When an activity window holds no on-device HR at all — the normal case for a workout recorded elsewhere — the day's HR is pulled into the local store through the same backfill the HR read uses.

The derived per-minute attribution is kept in its own table and joined against the packets at read time. **The band's packets are never rewritten**: sensor data is not overwritten with a derived value, which is also what keeps a server-authored split distinguishable from a computed one. The attribution is re-derived from its inputs on every read, so it can never serve a stale answer.

Two known divergences from the server on an activity that was **not** recorded on this device, both of them limits of what the phone can ask for rather than defects in the model:

- **HR density.** The server scores workout minutes from a per-second trace (`activity_biometrics`) that this app uploads but that has **no read endpoint**. The densest HR the phone can fetch back is the ~2-minute PPG trace behind the daily HR graph, so a minute with no sample in it is left **unscored** rather than filled in from a neighbour — a synthesized sample would be a number nobody measured. A remote activity can therefore read low, in proportion to how much of its HR is missing. Adding a read endpoint for the per-second trace is what would close this.
- **Pauses.** `WorkoutDetail` carries a `pause_segments` field that the server never populates for a workout, so a remote activity's pauses are not knowable and its HR is fed to the model unfiltered. A *paused* remote activity therefore reads slightly high. An activity recorded on this device has its pauses exactly, and an activity with no pause has nothing to exclude.

Both the dashboard calories tile and the calories detail screen read the same `SB_CaloriesDataPoints` instance — the tile takes `totalActiveCalories`, the detail screen builds its metric list from the same value — so the two cannot disagree.

The returned `SB_CaloriesDataPoints` computes the five day totals and hourly buckets on the fly, plus a day-level `restingCalories` (the user's BMR over the elapsed part of the day — full BMR for a completed past day, `BMR × elapsed/86400` for today, `0` when weight/height are unknown). `totalCalories = totalActiveCalories + restingCalories`; `totalActiveCalories` drives the calories ring. These aggregates are **non-optional** and default to `0`; use `points.isEmpty && restingCalories == 0` to distinguish "no data on device" from a genuine zero-calorie day. Locally-synced points are per-minute, server-backfilled points per-hour; both aggregate identically. (Ported to match Android's local-first calories, SB-1663.)

```swift
public func getCaloriesPoints(date: Date) async throws -> SB_CaloriesDataPoints

public struct SB_CaloriesDataPoints: Codable, Equatable, Sendable {
    public let points: [SB_CaloriesDataPoint]
    public let restingCalories: Float       // kcal, day-level BMR over the elapsed day
    // Computed on the fly from `points`; non-optional, 0 when there are no points.
    public var totalStepCalories: Float     // server "Steps" tile
    public var totalWorkoutCalories: Float  // server "Workout" tile
    public var totalActiveCalories: Float   // server "Active" tile = step + workout; drives the ring
    public var totalCalories: Float         // server "Total" tile = active + resting
    public var hourlyBuckets: [SB_CaloriesHourBucket]  // one per hour with points (gaps omitted)
}

public struct SB_CaloriesDataPoint: Codable, Equatable, Sendable {
    public let epoch: Int64          // ms
    public let stepCalories: Float   // kcal (server: totalStepCalories − workoutStepCalories)
    public let workoutCalories: Float // kcal
    public var activeCalories: Float // step + workout
}

public struct SB_CaloriesHourBucket: Codable, Equatable, Sendable {
    public let hour: Int             // local hour of day 0…23
    public let stepCalories: Float
    public let workoutCalories: Float
    public var activeCalories: Float // step + workout
}
```

`throws` only on the server-backfill path (e.g. `SB_AuthError.missingAuthToken` when signed out); the pure-local path never touches the network.

### 7.4 Sleep reads

```swift
public func fetchSleepDetail(endDate: Date, endTimestamp: Int64, forceRemote: Bool = false)                     async throws -> SB_SleepDetailDay
public func fetchSleepAggregation(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)      async throws -> SB_SleepDetailAggregated
```

#### Local-first sleep detail

`getSleepDetail(date:sessionEndTimestamp:)` is the sleep member of the local-first family — same contract as the vitals reads, but sleep is stored on-device as **sessions** (the on-device sleep-session rows) rather than a per-epoch timeseries, so instead of a bespoke points container it returns the **same `SB_SleepDetailDay`** `fetchSleepDetail` returns. The sleep-detail screen renders it unchanged. Two paths:

- **On-device day** (a device-recorded session with stages exists): the detail is **rebuilt entirely from the local row** — no API round-trip — with all the server-parity math below. A row is only surfaced once it has **settled with the server** and if its window is well-formed (positive `start`→`end` and positive `onset`→`wakeUp`); a not-yet-uploaded sleep is deliberately withheld so the local list matches server-first session-for-session, and a degenerate row — the sleep detector can persist one with `start == end` and a `wakeUp` *before* its `onset`, which the server rejects and never stores — is dropped rather than rendered as a 0-minute session.
- **Old day** (no on-device sleep — it predates local sync): a **server-backed read**, like the vitals do — it fetches the day's server sleep, persists **every** session's window locally (marked already-uploaded; there may be several sleeps in a day, and the windows let the vitals reads tag against them), and returns the chosen session's **full server `SB_SleepDetailDay`** (server stages / score / factors / penalties / biometrics / disturbances). So old days show the real sleep rather than an empty shell.

`nil` when neither the device nor the server has sleep for the day.

A session is attributed to the day it **wakes up** — it may start the previous evening (or be a nap fully inside the day), but a session that starts in the day and wakes the next belongs to the next day, so an overnight sleep isn't double-counted on both days. Without `sessionEndTimestamp` the day's **longest** session (most time asleep) is surfaced.

The returned `SB_SleepDetailDay` is populated with what the device stores, **recomputed to match server-first exactly** (the server re-derives its stage metrics after upload, and the iOS row never even stores its own per-stage totals — those columns are always `0` and the server fills them in from the timestamped stages):

- **stage metrics** — the per-epoch stages are clamped to `[sleepOnset, wakeUp]` and re-counted (server `UpdateSleepDerivedMetricsUsingTimestampedStages`), so the leading sleep-latency awake and any trailing awake are excluded. Each stage's minutes are the epoch count divided by the device's epochs-per-minute with **integer truncation** (server `int32(count / multiplier)`), matching the server to the minute. This drives the four legend percentages (largest-remainder rounding, including the server's quirk that a sub-1% bucket is never bumped to 1), the per-stage duration tiles, `sleepTimeSec` = (light + deep + rem) × 60, and the in-window arousal count. The stage-timeline `stages.stages` intervals are likewise the in-window epochs;
- **`sleepOnset` / `wakeUpTime` / `timezone`** (the device's current TZ offset in minutes — the same value the upload path stamps);
- **biometrics from the on-device PPG over the sleep window, each reproduced the server's way**: **`restingHr`** (header — `CalculateRestingBPM`: mean of the 5 lowest lower-fence-outlier-free BPM), the **Average HR** tile (median of the same outlier-free BPM) and the **Nocturnal HRV** tile (`CalculateRestingHRV`: the residual-outlier-free OLS HRV-vs-time line evaluated at the last epoch, also mirrored into `restingHrv`). Each is `0`/omitted when there is too little data. As on the server these are **rounded to whole numbers for display** (`util.Round`) while the score is computed from the raw values — hosts render them with truncating formatters, so an unrounded value would read one lower than server-first;
- **`metrics`** — the locally-derivable tiles, in the server's tile order with the server's labels: **Total Time in Bed** (= wakeUp − onset + 1 min), **Total Awake**, **Light**, **Deep**, **REM Sleep** (`.duration`), **Nocturnal HRV** (ms), **Average HR** (bpm), **Awakenings** (count), **Sleep Latency** (= onset − start), then the two editable `.timeTz` tiles **Sleep Onset** + **Wake up Time** — mirroring the only two tiles the server marks editable. The Nocturnal HRV + Average HR tiles are attached only to the day's **main** (longest) sleep, matching the server's `sl.MainSleep` guard, so a nap carries neither;
- **the sleep score + contributing factors + penalties** (`sleepScore` / `scoreFactors` / `scorePenalty`), computed locally to match the server's `CalculateSleepMainScore`: `score = max(1, goalAchieved × efficiency × 100 − penalties)`. Factors = **Total Sleep** (vs the user's sleep goal), **Deep** (or **Deep And REM**), **Efficiency**; penalties (points > 0 only) = **Awakenings**, **Restlessness** (from the arm disturbances), **Latency**, and **Elevated Avg Heart Rate**. Every input is on-device: the **sleep goal** comes from the SDK's own cache, which the SDK keeps warm itself by refreshing goals on sign-in / auto-login (the same fire-and-forget refresh it does for white-label settings) and on every `fetchGoals()` / `updateGoals(...)` — so the local read path never pulls it over the network, and it only falls back to the server's 7 h default before the first successful refresh. And the HR penalty's **30-day resting-HR baseline** is recomputed from the last 30 nights' own sleep + PPG history, so the HR penalty is simply **omitted when there isn't enough history** (server parity; e.g. right after a fresh login). If the night has no resting HR at all, no score is produced and the header falls back to the empty "--" ring.

Everything else the server owns and the local row does not hold is left empty and simply doesn't render: **bedtime recommendations**, **accounting**, **positions**, **apnea / breathing**, **bathroom breaks**, **survey** and the **temperature graph**. A **server-backfilled** window row (persisted for vitals tagging on a day that predated local sync) has no stages and is never rebuilt into a detail.

`getSleepSessions(date:)` returns the day's sessions for the detail screen's multi-session grid — local-first, else the server's list for an old day, sorted by start. Key each session by `SB_SleepItem.endTimestamp` (its wake-up epoch) and pass it back as `getSleepDetail(date:sessionEndTimestamp:)`, or to the graph reads, to load that session.

```swift
public func getSleepDetail(date: Date, sessionEndTimestamp: Int64? = nil) async throws -> SB_SleepDetailDay?
public func getSleepSessions(date: Date) async throws -> [SB_SleepItem]

// The session's biometric-graph timeseries (HR / HRV / RR) for the sleep-detail charts.
// The session is identified by its wake-up epoch (`SB_SleepItem.endTimestamp`, or
// `SB_SleepDetailDay.wakeUpTime` from getSleepDetail).
public func getSleepHR(sessionEndTimestamp: Int64) async throws -> [SB_TimeValuePoint]
public func getSleepHRV(sessionEndTimestamp: Int64) async throws -> [SB_TimeValuePoint]
public func getSleepRR(sessionEndTimestamp: Int64) async throws -> [SB_TimeValuePoint]
```

`getSleepHR` / `getSleepHRV` / `getSleepRR` return the session's per-epoch metric over its `[onset, wakeUp]` window, time-ordered with **real-epoch** timestamps (the convention the sleep biometric chart's bucketing expects), with each metric's server-parity outlier handling applied (HR **lower fence only**, so high spikes are kept; HRV a **two-sided** drop on the residuals of a least-squares fit, which removes the spikes; RR **unfiltered**, rounded to 1 dp). Local-first: read from the on-device PPG; if the day predates local sync (no on-device sleep) each falls back to the server sleep detail's matching graph — hence `async throws`. A device-recorded session whose PPG is simply missing returns empty rather than reaching the network. A host wraps each list in an `SB_SleepBiometricGraph` (points + mean average) to feed the same biometric chart the server path draws; there is no local SpO2 (that card stays hidden).

`getSleepArmDisturbances(sessionEndTimestamp:)` returns the session's arm-restlessness severity timeline for the disturbance chart — **fully local**, so it never `throws`: bucketed from the on-device activity packets' motion value over `[onset, wakeUp]` with the server's fixed thresholds (`≤250000 none / ≤750000 mild / ≤1250000 moderate / else severe`), first + last forced `.none` (the awake bookends). It returns a colour-free `SB_SleepDisturbanceLevel` per epoch — the SDK deliberately does **not** return colours, so the host owns the palette (and its theming). `.none` points are included so the host can compute the level distribution for the legend; hosts typically drop them from the drawn series (server parity). No server fallback — the arm series is only ever local; empty when the session has no activity packets on device. (Leg / snoring disturbance graphs are dead on the server, so only the arm series is exposed.)

It is `async` with nothing to await, purely so the store read happens off the caller's actor (a `@MainActor` view model never does the fetch on the main thread) — matching Android's `suspend` signature.

```swift
public func getSleepArmDisturbances(sessionEndTimestamp: Int64) async -> [SB_SleepDisturbancePoint]

public enum SB_SleepDisturbanceLevel: Int32, Codable, Equatable, Sendable, CaseIterable {
    case none = 0, mild = 1, moderate = 2, severe = 3
}

public struct SB_SleepDisturbancePoint: Codable, Equatable, Sendable {
    public var timestamp: Int64                    // ms, real epoch
    public var timezone: Int32                     // device TZ offset in minutes
    public var level: SB_SleepDisturbanceLevel
}
```

`getSleepDetail` / `getSleepSessions` / the three graph reads `throw` only on the server-backed path (e.g. `SB_AuthError.missingAuthToken` when signed out); the pure-local path never touches the network. (Ported to match Android's local-first sleep, SB-1677/SB-1678.)

### 7.5 Insights — personal + population + feedback

```swift
public func fetchNewInsights() async throws -> SB_NewInsights
public func fetchPopulationInsightsMetricList() async throws -> SB_PopulationInsightsFilterList
public func fetchPopulationInsights(
    ageStart: Int32, ageEnd: Int32,
    gender: SB_PopulationGender, metricType: SB_PopulationMetricType
) async throws -> (histogram: SB_PopulationInsightsHistogram?, radarChart: SB_PopulationInsightsRadarChart?)
public func submitInsightsFeedback(insightId: Int64, feedback: SB_InsightFeedback) async throws
```

### 7.6 User profile

```swift
public func updateUserProfile(_ profile: SB_UserProfileUpdate) async throws -> SB_UpdateUserProfileOutcome
public func refreshUser() async throws
public func uploadUserPhoto(imageData: Data) async throws -> String?
public func deleteUserPhoto() async throws
```

> **`location` is a full-replace field.** `SB_UserProfileUpdate.location` and `SB_UserProfile.location`
> name the same value — the user's location (city / country). It maps to a wire field historically
> named `zipcode`. `updateUserProfile` replaces the whole profile, so read the current value from
> `sensorBio.userProfile?.location` and pass it back in on every update; sending `""` (or omitting it)
> overwrites the stored value on the server.

### 7.7 Goals

Steps / calories / sleep are the customer-facing goal surface. `SB_Goals` is returned with those three targets/currents public; its workout / routine-goal members are Sensr-Bio-only and absent from the binary. It is `Equatable, Sendable`.

```swift
public func fetchGoals() async throws -> SB_Goals
public func updateGoals(steps: Int, calories: Int, sleep: Int) async throws -> SB_UpdateGoalsOutcome
```

Both cache the **sleep** target locally as a side effect (SB-1678), so the local-first sleep score can read the user's goal without a network round-trip. The SDK also refreshes goals itself on sign-in / account creation / auto-login (fire-and-forget, alongside the white-label refresh), so the cache is warm without the host having to call `fetchGoals()` at all — a host that never did would otherwise have left the local score scoring against the 7 h default. Nothing else about their behaviour changes, and the cache is only ever written with a non-zero goal.

### 7.8 Sleep writes

```swift
public func fetchSleepSessions(date: Date) async throws -> [SB_SleepItem]
public func addSleepSession(onset: Date, wakeUp: Date) async throws
public func modifySleepSession(onset: Date, wakeUp: Date, endTimestamp: Int64, date: Date) async throws
public func deleteSleepSession(endTimestamp: Int64, date: Date) async throws
public func reprocessSleep(endDate: Int32, endTimestamp: Int64) async throws
```

### 7.9 Workouts & activities

```swift
public func fetchActivityList() async throws -> SB_ActivityRecordingList
public func fetchWorkoutRecordingInfo() async throws -> SB_WorkoutRecordingInfo
public func fetchWorkoutSummary(date: Date, granularity: SB_SummaryGranularity, workoutType: SB_WorkoutType? = nil) async throws -> [SB_WorkoutItem]
public func fetchWorkoutDetail(workoutTime: Date) async throws -> SB_WorkoutDetail?
public func fetchWorkoutTimeline(date: Date, searchTerm: String = "", filterType: SB_WorkoutEntryType = .all) async throws -> SB_WorkoutTimelineResult
public func workoutTimelineUpdates(for date: Date) -> AsyncThrowingStream<SB_WorkoutTimelineResult, Error>
public func modifyWorkout(action: SB_ModifyAction, date: Date, workoutTime: Date, name: String?) async throws -> SB_ModifyOutcome
public func fetchMeditationGraph(date: Date, sessionTimestamp: Int64) async throws -> SB_MeditationGraph
```

**Timeline first-page cache (SB-1958).** The workout reads are otherwise uncached — they're navigation-driven — with one exception: the timeline's **first page**. `workoutTimelineUpdates(for:)` is the stale→fresh stream for it, so the timeline paints the last-known page on cold launch instead of a skeleton, then swaps in the authoritative fetch.

Only the plain page-1 read is cached (`workout.timeline.page1`): no cursor, no search term, `.down`. A cursor is a server-side handle on a query that has moved on, and a searched result is a query whose answer has to come from the server — caching either would explode the key space and serve stale answers, so `fetchWorkoutTimeline` passes those straight through. `fetchWorkoutTimeline` for the cacheable shape also gains the usual bad-internet fallback: on a failed fetch it returns the last-known page rather than throwing.

Page 1 is always "today", so the cache never *replaces* the network read the way a final past-date entry does (see [Caching](#caching)) — the value is the pre-yield paint and the offline fallback, not a skipped round trip.

The cached copy has its **pagination cursor stripped**. A restored cursor would page the host into a window the server no longer recognises; with it empty, a host gating its infinite-scroll loader on `cursor != nil` simply has paging unavailable for the moment before the authoritative page lands, rather than wrong.

### 7.10 Spot-check & recording metadata

```swift
public func fetchSpotCheckDetails(id: String) async throws -> SB_SpotCheckDetails?
public func fetchRecordingMetaInfo(_ type: SB_RecordingMetaType) async throws -> [SB_RecordingSessionMeta]
public func deleteRecordingMeta(id: String, name: String, type: SB_RecordingMetaType) async throws
```

### 7.11 Surveys & questionnaires

Brief surveys are the real sleep / workout / meditation survey responses the device collects; they stay on the public surface.

```swift
public func submitBriefSurvey(_ survey: SB_BriefSurvey) async throws -> String
```

**Await it before refetching.** The submit suspends until the survey lands server-side. If your survey UI refetches anything on dismissal, do that *after* this returns — otherwise the refetch races the upload, goes out before the survey exists, and the dependent UI stays stale until some later fetch. This was fire-and-forget before SB-1835, and every caller had exactly that race.

**A throw means "not landed yet", not "lost."** On failure the SDK persists the survey to its retry queue (waits for connectivity, survives relaunch) *before* rethrowing. So the survey will still land; treat the error as retry-in-progress rather than a discarded response, and gate your submit button while the call is in flight so a double-tap can't send twice.

**You usually don't need to refetch at all.** `UploadBriefSurvey` stores the answers and links the returned id onto the sleep record — it recomputes nothing, and the response carries only the id. So the survey you submitted, with `id` set to the returned value, *is* the new server state: assign it into your displayed model and skip the round-trip entirely. Whatever you have cached on disk still holds the pre-submit payload, so reconcile that in the background rather than making the user wait on it.

**Keep the returned id.** A submit whose `survey.id` is nil creates a *new* survey server-side instead of updating the existing one. If a user can edit the same survey twice in one session and your second submit reuses a copy that never had the id stamped on it, you silently duplicate rather than update.

Android's equivalent is `suspend (SB_BriefSurvey) -> String` and iOS now matches it. Android's own caller currently discards the id and refetches on dismissal instead, so it still pays the round-trip iOS no longer needs — worth aligning.

### 7.12 Devices, services & global state

```swift
public func updateUserDeviceInfo(macAddress: String, metadata: [String: String], unlinkDevice: Bool)
public func refreshGlobalState() async throws -> SB_OrgMembership
public func refreshUserAppSettings() async throws -> SB_UserAppSettings
public func fetchDailyStats(startDate: Int32, days: Int32, metrics: [String]) async throws -> [SB_DailyStats]
```

---

## 8. Top-Level Symbols & Namespaces

### 8.1 Logging

```swift
public enum LogLevel { case verbose, debug, info, warning, error }

extension SB_SDK {
    public static var log: AnyPublisher<(LogLevel, String, String, String, Int), Never>
}
```

Subscribe `SB_SDK.log` to forward SDK log entries into your own logging pipeline (Crashlytics, OSLog, custom file sink, etc.).

### 8.2 Environment

```swift
extension SB_SDK {
    public enum Environment {
        case staging
        case production
    }
}
```

### 8.3 Constants namespace

```swift
public enum SDKConstants {
    public static let SDKLicenseKey: String
    public static let RIGHT: Int
    public static let LEFT: Int
    public static let MaxWalkingPace: Int
    public static let firmwareUpdateReconnectDelay: TimeInterval
    public static let HRM_SAMPLING_INTERVAL_DEFAULT: Int

    public enum DefaultUserMetrics {
        public static let Age: Int32
        public static let Height: Float
        public static let RHR: Int32
        public static let RunStride: Int32
        public static let Sex: Int32
        public static let WalkStride: Int32
        public static let Weight: Float
    }
}
```

`DefaultUserMetrics.Sex` is in the SDK's **storage** convention — `0` male, `1`
female, `2` undisclosed — the same numbering `SB_UserProfile.sex` persists. Note
this is *not* the bioedge C numbering (`USER_SEX_MALE = 1`, `GENDER_MALE = 1`),
which counts the same three cases from one; conflating the two silently shifts
every user by one case (SB-1735).

### 8.4 Globals namespace

```swift
public enum SDKGlobals {
    public static let defaultPPGDuration: Int
    public static let noOfDaysToSavePPGAndActivityPackets: Int
    public static func getUserAge(birthday: DateComponents) -> Int?
    public static func calcBMR(male: Bool, weight: Double, height: Double, age: Int) -> Double
    public static func calcCFF(age: Int, rhr: Int) -> Double
}

public var gblIsMetric: Bool { get set }
```

### 8.5 Dependency-injection container

```swift
public struct Injectable<T> {
    public let wrappedValue: T
    public init()
}

public final class Container: @unchecked Sendable {
    public static let shared: Container
    public func register<T>(_ type: T.Type, instance: T)
    public func resolve<T>(_ type: T.Type) -> T?
    public func resolve<T>(_ type: T.Type) -> T
}
```

### 8.6 Diagnostic logger

```swift
public class SB_FXCLogging: NSObject {
    public enum InfoType: String { … }
    public enum LEVEL { … }
    public var minLevel: LEVEL
    public var prefix: String
    public func verbose(_ value: String?, …)
    public func debug(_ value: String?, …)
    public func info(_ value: String?, …)
    public func warning(_ value: String?, …)
    public func error(_ value: String?, …)
    public func alwaysLog(_ value: String?, …)
    public func fullLogURL() -> URL?
}
```

---

## 9. Putting it together — minimal example

```swift
import SwiftUI
import Combine
import SensorBioSDK

@main
struct DemoApp: App {
    init() {
        SB_SDK.environment = .production
        sensorBio.hydrateSession()
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

final class HomeViewModel: ObservableObject {
    @Published var dashboard: SB_DashboardData?
    @Published var connected: Bool = false
    @Published var paired: SB_PairedDeviceState?
    private var bag = Set<AnyCancellable>()

    init() {
        sensorBio.$connected
            .receive(on: DispatchQueue.main)
            .assign(to: &$connected)
        sensorBio.$pairedDevice
            .receive(on: DispatchQueue.main)
            .assign(to: &$paired)
    }

    // `registerUser` is register-OR-login: the first call for a given userId
    // registers, later calls sign the same user back in. `sdkToken` is a fresh
    // single-use token from your backend — one per call, never cached.
    func register(userId: String, sdkToken: String) async {
        do {
            switch try await sensorBio.registerUser(userId: userId, sdkToken: sdkToken) {
            case .success:
                await refreshDashboard()
            case .failure(let errorCode):
                print("register failed: \(errorCode)")
            }
        } catch { print(error) }
    }

    func refreshDashboard() async {
        do {
            dashboard = try await sensorBio.fetchDashboardData(
                date: .now,
                tzOffset: Int32(TimeZone.current.secondsFromGMT() / 60)
            )
        } catch { print(error) }
    }

    func discoverAndPair() {
        sensorBio.$pairingState
            .receive(on: DispatchQueue.main)
            .sink { state in
                if case .scanning(let devices) = state { print("found", devices.count) }
                if case .paired(let device) = state { print("paired", device.macAddress) }
            }
            .store(in: &bag)
        sensorBio.beginPairing()
    }
}
```

