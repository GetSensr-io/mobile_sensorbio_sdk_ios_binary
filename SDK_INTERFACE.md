# SensorBioSDK — iOS Integration Guide

This document describes the **public** customer-facing surface of `SensorBioSDK` as it exists today. The SDK ships as a set of `.xcframework`s consumed via CocoaPods (see [README.md](./README.md) for integration); `import SensorBioSDK` is the only line a customer app needs.

> **Source of truth.** This file lives on `mobile_sensorbio_sdk_ios` `main` and tracks the latest public surface. A copy is synced into [`mobile_sensorbio_sdk_ios_binary`](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary/blob/main/SDK_INTERFACE.md) at each tagged binary release; customers pinning to a binary tag should read the copy in the binary repo for the surface that matches their pin. The SDK-repo version may include symbols not yet present in the most recent binary release.

> **Visibility note.** This document covers the customer-facing API surface only. SDK-internal symbols are filtered out of the binary framework's Swift interface and are not documented here.

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
    :tag => 'v0.3.2'
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

Then `pod install`, open `MyApp.xcworkspace`, and `import SensorBioSDK`. The `post_install` block bumps the deployment target to iOS 18 (SDK requires), forces C++17 (gRPC-Core's transitive abseil dependency requires), and turns on library-evolution mode (the SDK's SwiftQueue `Job` subclasses reference method descriptors that only exist when all transitive pods are also built BLFD).

The single `pod 'SensorBioSDK'` line vendors the three xcframeworks and transitively brings the third-party pods the SDK links against (gRPC-ProtoRPC → gRPC-Core + abseil + BoringSSL-GRPC + Protobuf; SwiftProtobuf; SwiftKeychainWrapper; KeychainAccess; SwiftQueue; CocoaMQTT). **Customers only import `SensorBioSDK`** — the BT SDK and LibFXC are linked transitively and have no user-callable surface.

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

**Pairing, connection & reachability**

| Property | Type | Description |
|---|---|---|
| `pairedDevice` | `SB_PairedDeviceState?` | Pre-connection device snapshot (name, type, macAddress) |
| `haveDevice` | `Bool` | A device is paired |
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
| `lastSyncStartEpoch` | `Double?` | Sync-window start timestamp |
| `lastSyncEndEpoch` | `Double?` | Sync-window end timestamp |

**Device telemetry**

| Property | Type | Description |
|---|---|---|
| `batteryLevel` | `Int?` | 0–100 |
| `charging` | `Bool?` | Device is on its charger |
| `worn` | `Bool?` | Device is being worn |
| `buttonTaps` | `Int?` | Last button-tap event (used during pairing) |

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
public var sdkVersion: String            // underlying BLE SDK version string
public var isAirplaneModeActive: Bool    // device is in airplane mode
public var isRawLoggingEnabled: Bool     // white-label raw-sensor-logging on
public var haveUnuploadedPackets: AnyPublisher<Bool, Never>
public var developmentLogStats: (storeURL: URL, enginePacketCount: Int)
```

### 3.4 Event streams (Combine subjects)

Subscribe via `sensorBio.<subject>.sink { … }`.

```swift
// Auth & pairing lifecycle
public let signOutComplete:             PassthroughSubject<Void, Never>
public let deviceDiscovered:            PassthroughSubject<SB_DiscoveredDevice, Never>
public let pairingConnection:           PassthroughSubject<String, Never>   // payload: macAddress
public let deviceDisconnected:          PassthroughSubject<String, Never>   // payload: macAddress
public let persistDeviceStateRequested: PassthroughSubject<Void, Never>     // SDK asks the app to call persistDeviceState(_:)
public let deviceConnected:             PassthroughSubject<Void, Never>     // low-level BLE connect
public let deviceFullyConfigured:       PassthroughSubject<Void, Never>     // post-configure
public let deviceLinkFailed:            PassthroughSubject<SB_DeviceLinkFailure, Never>  // server rejected the device-link (serial-enforced subscription)
public let subscriptionLost:            PassthroughSubject<Void, Never>     // an authenticated RPC was rejected for no active subscription — host should alert + force logout

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
public let biometricRecordProcessed:    PassthroughSubject<Void, Never>
public let sleepStored:                 PassthroughSubject<Void, Never>
public let sleepDetected:               PassthroughSubject<SB_DetectedSleep, Never>  // valid on-device sleep finalized (start/end epoch ms)
```


---

## 4. Authentication

```swift
// Sign-in / sign-up
public func signIn(email: String, password: String) async throws -> SB_SignInOutcome
public func createAccount(_ request: SB_CreateAccountRequest) async throws -> SB_CreateAccountOutcome
public func checkEmailAvailability(email: String) async throws -> SB_EmailAvailabilityOutcome
public func validateAccountRequirements(
    _ request: SB_ValidateAccountRequirementsRequest
) async throws -> SB_ValidateAccountRequirementsResult

// Session
public func hydrateSession()                                          // restore from keychain
public func signOut() async throws                                    // see side-effects note below
public func generateTemporaryAuthToken() async throws -> String?

// Password
public func requestPasswordReset(email: String) async throws -> SB_RequestPasswordResetOutcome
public func changePassword(currentPassword: String, newPassword: String) async throws -> SB_ChangePasswordOutcome

// Agreements (ToS / Health Data)
public func shouldRequestAgreement(type: SB_AgreementType) async throws -> SB_AgreementCheck
public func acceptAgreements(tosVersion: String, healthDataVersion: String) async throws
public func acceptCurrentAgreements() async throws
```

Example:

```swift
do {
    switch try await sensorBio.signIn(email: email, password: password) {
    case .success:           routeToHome()
    case .passwordIncorrect: showError("Incorrect password")
    case .unknownUsername:   showError("Unknown email")
    case .other(let msg):    showError(msg)
    }
} catch {
    showError(error.localizedDescription)
}
```

> **`signOut()` side effects.** A successful sign-out disconnects any connected device, clears the paired-device state, nils out `pairedDevice` / `haveDevice` / `exerciseZoneAttributes`, and wipes the SDK's locally cached user data. `signOut()` is the **only** customer-facing way to clear SDK persistence — a wipe without a sign-out would leave in-memory `@Published` state and the BLE connection inconsistent with the cleared cache. Account-deletion flows should call `signOut()` after the delete-account call succeeds.

---

## 5. BLE Device Control

### 5.1 Scan & connect

```swift
public func startScan()
public func stopScan()
public func connect(_ id: String, pairing: Bool = false)
public func disconnect(_ id: String? = nil)
public func removeDeviceFromPairedDevices(_ id: String)
public func persistDeviceState(_ devicesDictionary: [String: Any])
```

The pairing flow uses the typed `SB_DiscoveredDevice` payload:

```swift
sensorBio.deviceDiscovered
    .sink { (device: SB_DiscoveredDevice) in
        print("found", device.macAddress, device.name, device.rssi)
    }
    .store(in: &cancellables)

sensorBio.startScan()
// …user picks one…
sensorBio.connect(macAddress, pairing: true)

sensorBio.pairingConnection
    .sink { mac in print("paired", mac) }
    .store(in: &cancellables)
```

`persistDeviceState(_:)` is the matching write-back: the SDK emits `persistDeviceStateRequested` when the in-memory paired-device map should be persisted on the app side; the app responds by calling `persistDeviceState(_:)` with its serialized devices dictionary.

Static bootstrap + diagnostic accessors (callable before `SB_SDK.shared` initializes):

```swift
public static var persistedDevicesDictionary: [String: AnyObject]?      // persisted devices dict (devicesKey)
public static var migratedDevicesSnapshot: [String: AnyObject]?         // one-time pre-collapse copy; nil until captured
public static func captureLegacyDevicesSnapshotIfNeeded()              // call at launch before selecting/collapsing
```

`captureLegacyDevicesSnapshotIfNeeded()` is a diagnostic: on first launch it copies a genuine multi-device `devicesKey` (count > 1) into a never-overwritten key so the original set survives the app's first `persistDeviceState(_:)`, which collapses storage to a single `gblCurrentDevice` entry. `migratedDevicesSnapshot` reads it back. No-op for single-device or already-captured installs.

### 5.2 Device commands

```swift
public func userLED(red: Bool = false, green: Bool = false, blue: Bool = false,
                    blink: Bool = false, for seconds: Int) async throws
public func setAskForDeviceResponse(_ enable: Bool)
public func airplaneMode() async throws
public func reset()
public func updateFirmware(_ url: URL, delay: Int? = nil, size: Int? = nil) async throws
```

### 5.3 Recording

Recording is fully SDK-orchestrated — there is no low-level start/stop surface; the SDK owns the BLE session lifecycle end-to-end.

**High-level orchestrations.** Each runs a session end-to-end: BLE start/stop, timer (fixed-duration countdown or open-ended count-up), post-stop sync wait, session build, and submission. Three completion paths each: natural completion (countdown modes only) / early-finish-with-submit via `finishCurrentRecording()` / cancellation via `Task.cancel()`. Submission is automatic — there is no separate "submit" call.

```swift
public func recordDetailedBiometrics(
    duration: TimeInterval,
    minDuration: TimeInterval
) async throws

public func recordMeditation(
    duration: TimeInterval,
    minDuration: TimeInterval,
    sessionName: String? = nil,
    sessionNameAlreadyExists: Bool = false
) async throws

public func recordActivity(
    activityName: String,
    minDuration: TimeInterval
) async throws

public func finishCurrentRecording()        // signal: "user tapped End Recording"
```

`recordActivity(...)` is open-ended — it has no `duration:` parameter and runs until `finishCurrentRecording()` flips or the calling `Task` cancels. `recordingState` publishes `.recording(elapsed:, target: nil)` so countdown UIs render count-up format from the `nil` target.

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

**Persist + restore across app kill.** The SDK persists every in-flight `record*(...)` orchestration on entry and clears the envelope on every terminal path. If the host process is killed mid-recording, `SB_SDK.init()` re-publishes the matching `recordingState` synchronously on next launch and either resumes the countdown (fixed-duration, not expired), runs the auto-finalize path (fixed-duration, past expected end), or resumes the open-ended count-up (activity). Submission still flows automatically. Host viewmodels rebind via `awaitActiveRecordingCompletion()` — same `async throws` shape as the original `record*(...)` call.

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
    public var startDate: Date { get }
    public var endDate: Date? { get }               // nil for .activity
    public var isExpired: Bool { get }
}
```

### 5.4 Sync — automatic

Sync runs automatically once a paired device connects. No customer-side method call is required to trigger it; the SDK manages the sync lifecycle internally and emits state changes via the `@Published` `deviceSyncing` / `percentSynced` / `lastSyncd` properties (see §3.2).

---

## 6. Server APIs (async/await)

Every method below is `async throws` on the `SB_SDK` facade. All return typed `SB_*` domain models; authentication is automatic once the user is signed in. Outcome-style methods (e.g. `signIn`, `updateGoals`) return discriminated enums rather than raw errors for common business cases.

### 6.1 Dashboard

```swift
public func fetchDashboardData(date: Date, tzOffset: Int32) async throws -> SB_DashboardData
```

### 6.2 Activity reads

```swift
public func fetchSteps(date: Date, granularity: SB_ViewGranularity)        async throws -> SB_StepsTrending
public func fetchCalories(date: Date, granularity: SB_ViewGranularity)     async throws -> SB_CaloriesTrending
public func fetchDailyActivityDetail(date: Date, granularity: SB_ViewGranularity) async throws -> SB_DailyActivityDetail
public func fetchDailyRecovery(date: Date)                                 async throws -> SB_DailyRecoveryTrending
public func fetchRangeRecovery(date: Date, granularity: SB_ViewGranularity) async throws -> SB_RecoveryRangeTrending
```

`fetchDailyActivityDetail` returns the activity **score** plus a per-metric breakdown — steps, calories burned, distance, and active time — each carrying chart datapoints. The metrics reuse `SB_StepMetric` (switch on `metricType`: `.steps` / `.caloriesBurned` / `.distance` / `.totalDuration`):

```swift
public struct SB_DailyActivityDetail: Codable, Equatable, Sendable {
    public var score: SB_ActivityScore?
    public var metrics: [SB_StepMetric]
}

public struct SB_ActivityScore: Codable, Equatable, Sendable {
    public var score: Float
    public var diffVsBaseline: Float
    public var diffVsLastGranularityValue: Float
    public var scoreDescription: String
    public var colorHex: String              // server-suggested; app may ignore
    public var progressPercentage: Float     // 0–1 ring fill
}
```

### 6.3 Biometric reads — HR / HRV / RR · SpO2 🚧 WIP

```swift
public func fetchDailyHR(date: Date)                                       async throws -> SB_HRDailyTrending
public func fetchRangeHR(date: Date, granularity: SB_ViewGranularity)      async throws -> SB_HRRangeTrending
public func fetchDailyHRV(date: Date)                                      async throws -> SB_HRVDailyTrending
public func fetchRangeHRV(date: Date, granularity: SB_ViewGranularity)     async throws -> SB_HRVRangeTrending
public func fetchDailyRR(date: Date)                                       async throws -> SB_RRDailyTrending
public func fetchRangeRR(date: Date, granularity: SB_ViewGranularity)      async throws -> SB_RRRangeTrending

// 🚧 WIP
public func fetchDailySpO2(date: Date)                                     async throws -> SB_SpO2DailyTrending
public func fetchRangeSpO2(date: Date, granularity: SB_ViewGranularity)    async throws -> SB_SpO2RangeTrending
```

### 6.4 Sleep reads

```swift
public func fetchSleepDetail(endDate: Date, endTimestamp: Date)                     async throws -> SB_SleepDetailDay
public func fetchSleepAggregation(date: Date, granularity: SB_ViewGranularity)      async throws -> SB_SleepDetailAggregated
```

### 6.5 Insights — personal + population + feedback

```swift
public func fetchNewInsights() async throws -> SB_NewInsights
public func fetchPopulationInsightsMetricList() async throws -> SB_PopulationInsightsFilterList
public func fetchPopulationInsights(
    ageStart: Int32, ageEnd: Int32,
    gender: SB_PopulationGender, metricType: SB_PopulationMetricType
) async throws -> (histogram: SB_PopulationInsightsHistogram?, radarChart: SB_PopulationInsightsRadarChart?)
public func submitInsightsFeedback(insightId: Int64, feedback: SB_InsightFeedback) async throws
```

### 6.6 User profile

```swift
public func updateUserProfile(_ profile: SB_UserProfileUpdate) async throws -> SB_UpdateUserProfileOutcome
public func refreshUser() async throws
public func uploadUserPhoto(imageData: Data) async throws -> String?
public func deleteUserPhoto() async throws
```

### 6.7 Goals

Steps / calories / sleep are the customer-facing goal surface. `SB_Goals` is returned with those three targets/currents public; its workout / routine-goal members are Sensr-Bio-only and absent from the binary.

```swift
public func fetchGoals() async throws -> SB_Goals
public func updateGoals(steps: Int, calories: Int, sleep: Int) async throws -> SB_UpdateGoalsOutcome
```

### 6.8 Sleep writes

```swift
public func fetchSleepSessions(date: Date) async throws -> [SB_SleepItem]
public func addSleepSession(onset: Date, wakeUp: Date) async throws
public func modifySleepSession(onset: Date, wakeUp: Date, endTimestamp: Int64, date: Date) async throws
public func deleteSleepSession(endTimestamp: Int64, date: Date) async throws
public func reprocessSleep(endDate: Int32, endTimestamp: Int64) async throws
```

### 6.9 Workouts & activities

```swift
public func fetchActivityList() async throws -> SB_ActivityRecordingList
public func fetchWorkoutRecordingInfo() async throws -> SB_WorkoutRecordingInfo
public func fetchWorkoutSummary(date: Date, granularity: SB_SummaryGranularity, workoutType: SB_WorkoutType? = nil) async throws -> [SB_WorkoutItem]
public func fetchWorkoutDetail(workoutTime: Date) async throws -> SB_WorkoutDetail?
public func fetchWorkoutTimeline(date: Date, searchTerm: String = "", filterType: SB_WorkoutEntryType = .all) async throws -> SB_WorkoutTimelineResult
public func modifyWorkout(action: SB_ModifyAction, date: Date, workoutTime: Date, name: String?) async throws -> SB_ModifyOutcome
public func fetchMeditationGraph(date: Date, sessionTimestamp: Int64) async throws -> SB_MeditationGraph
```

### 6.10 Spot-check & recording metadata

```swift
public func fetchSpotCheckDetails(id: String) async throws -> SB_SpotCheckDetails?
public func fetchRecordingMetaInfo(_ type: SB_RecordingMetaType) async throws -> [SB_RecordingSessionMeta]
public func deleteRecordingMeta(id: String, name: String, type: SB_RecordingMetaType) async throws
```

### 6.11 Surveys & questionnaires

Brief surveys are the real sleep / workout / meditation survey responses the device collects; they stay on the public surface.

```swift
public func submitBriefSurvey(_ survey: SB_BriefSurvey)
public func manageNextSurvey()
```

### 6.12 Devices, services & global state

```swift
public func updateUserDeviceInfo(macAddress: String, metadata: [String: String], unlinkDevice: Bool)
public func refreshGlobalState() async throws -> SB_OrgMembership
public func refreshUserAppSettings() async throws -> SB_UserAppSettings
public func fetchDailyStats(startDate: Int32, days: Int32, metrics: [String]) async throws -> [SB_DailyStats]
```

---

## 7. Top-Level Symbols & Namespaces

### 7.1 Logging

```swift
public enum LogLevel { case verbose, debug, info, warning, error }

extension SB_SDK {
    public static var log: AnyPublisher<(LogLevel, String, String, String, Int), Never>
}
```

Subscribe `SB_SDK.log` to forward SDK log entries into your own logging pipeline (Crashlytics, OSLog, custom file sink, etc.).

### 7.2 Environment

```swift
extension SB_SDK {
    public enum Environment {
        case staging
        case production
    }
}
```

### 7.3 Constants namespace

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

### 7.4 Globals namespace

```swift
public enum SDKGlobals {
    public static let defaultPPGDuration: Int
    public static let noOfDaysToSavePPGAndActivityPackets: Int
    public static func getUserAge(birthday: DateComponents) -> Int
    public static func calcBMR(male: Bool, weight: Double, height: Double, age: Int) -> Double
    public static func calcCFF(age: Int, rhr: Int) -> Double
}

public var gblIsMetric: Bool { get set }
```

### 7.5 Dependency-injection container

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

### 7.6 Diagnostic logger

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

## 8. Putting it together — minimal example

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

        sensorBio.persistDeviceStateRequested
            .sink { _ in /* serialize + call sensorBio.persistDeviceState(...) */ }
            .store(in: &bag)
    }

    func signIn(email: String, password: String) async {
        do {
            switch try await sensorBio.signIn(email: email, password: password) {
            case .success:
                await refreshDashboard()
            case .passwordIncorrect, .unknownUsername, .other:
                break
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
        sensorBio.deviceDiscovered
            .sink { (d: SB_DiscoveredDevice) in print("found", d.macAddress) }
            .store(in: &bag)
        sensorBio.startScan()
    }
}
```

