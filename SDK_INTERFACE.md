# SensorBioSDK — iOS Integration Guide

This document describes the **public** customer-facing surface of `SensorBioSDK` as it exists today. The SDK ships as a set of `.xcframework`s consumed via CocoaPods (see [README.md](./README.md) for integration); `import SensorBioSDK` is the only line a customer app needs.

> **Visibility note.** This document covers the customer-facing API surface only. SDK-internal symbols are filtered out of the binary framework's Swift interface and are not documented here.

---

## Stability & support tier

The SDK is in a guided rollout. **Not every public symbol below is ready for customer use yet.** A feature lands in the public surface as soon as the underlying machinery works, but it is only marked ✅ Supported once it has been wired into the bundled `ExampleApp` reference app and validated end-to-end.

- ✅ **Supported** — exercised by `ExampleApp`, safe to build production code against today.
- 🚧 **WIP** — present in the public surface (and listed in this doc for forward visibility) but not yet validated for customer use. Treat as preview; do not depend on the shape staying stable. Many of these symbols are not guaranteed to remain public — they currently exist on the public surface because they are consumed by internal applications, and may be tightened or removed before they are formally offered to customers.

### Quick map

| Area | Status | Notes |
|---|---|---|
| CocoaPods install, Info.plist, app launch | ✅ Supported | `SB_SDK.environment`, `SB_SDK.log` |
| Auth — sign in / sign up / sign out | ✅ Supported | `signIn`, `createAccount`, `signOut`, `hydrateSession` |
| Auth — agreements, password reset, password change, email check, temp tokens | ✅ Supported | |
| User profile updates / photo | ✅ Supported | |
| Goals fetch / update | ✅ Supported | |
| Pairing & connect | ✅ Supported | Scan, connect, disconnect, `userLED`, `setAskForDeviceResponse`, `persistDeviceState`, `removeDeviceFromPairedDevices` |
| Device commands beyond LED + device-response | ✅ Supported | airplane mode, reset, firmware update |
| Recording (biometric / activity / stop / finished-session) | 🚧 WIP | |
| Streaming biometric subjects (hr / hrv / rr / spo2 / snr / bbi / ppg / ecg) | ✅ Supported | |
| Dashboard | ✅ Supported | `fetchDashboardData` |
| Activity reads — steps / calories / recovery | ✅ Supported | |
| Biometric reads — daily + range HR / HRV / RR | ✅ Supported | |
| Biometric reads — SpO2 daily + range | 🚧 WIP | |
| Sleep reads — detail + aggregation | ✅ Supported | |
| Sleep writes — add / modify / delete / reprocess / email PDF | ✅ Supported | |
| Workouts — list / detail / timeline / modify / meditation | 🚧 WIP | |
| Spot-check details + result subject | 🚧 WIP | |
| Recording metadata endpoints | 🚧 WIP | |
| Routine metadata | 🚧 WIP | |
| Insights — personal + population reads | ✅ Supported | |
| Insights — feedback submission | 🚧 WIP | |
| Custom questionnaire + brief surveys | 🚧 WIP | |
| Devices endpoints (locked devices, update info, upload sync time) | 🚧 WIP | |
| Services endpoints (register push, refresh global state, refresh user settings) | 🚧 WIP | |
| Daily stats endpoint | 🚧 WIP | |
| White-label settings | 🚧 WIP | |
| `SleepDetectionDelegate` | 🚧 WIP | |
| Diagnostics publishers | ✅ Supported | `haveUnuploadedPackets`, `developmentLogStats`, `isRawLoggingEnabled` |
| DI `Container` / `@Injectable` | 🚧 WIP | Internal plumbing; no customer use case yet |
| `SDKConstants` / `SDKGlobals` | 🚧 WIP | Internal-only knobs today |

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

## 2. Lifecycle & Configuration — ✅ Supported

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

## 3. The `SB_SDK` Facade — ✅ Supported (core)

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

#### ✅ Supported

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

#### 🚧 WIP

The following `@Published` properties exist today and may be observed, but their data flow has not been validated for customer use yet — treat as preview:

`whiteLabelSettings`, `forceUserToUpdatePassword`, `forceUserToUpdateProfile`, `exerciseZoneAttributes`, `updateSuggested`, `updateRequired`, `deviceAirplaneModeOn`, `webAppCookie`, `lastSyncedTemp`.

### 3.3 Computed read-only properties

#### ✅ Supported

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

#### 🚧 WIP

```swift
public var isRecording: Bool
```

### 3.4 Event streams (Combine subjects)

Subscribe via `sensorBio.<subject>.sink { … }`.

#### ✅ Supported — auth, pairing & streaming biometrics

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
```

#### 🚧 WIP

```swift
public let spotCheckResult:             PassthroughSubject<SB_SpotCheckResult, Never>
public let spotCheckProcessed:          PassthroughSubject<Void, Never>
public let sleepStored:                 PassthroughSubject<Void, Never>
public let scheduledSurveyToPresent:    PassthroughSubject<SB_WhiteLabelScheduledSurveyTime, Never>
```

### 3.5 Delegate hooks — 🚧 WIP

```swift
public weak var sleepDetectionDelegate: SleepDetectionDelegate?

public protocol SleepDetectionDelegate: AnyObject {
    func detectedSleep(startEpochInms: Int64, endEpochms: Int64)
}
```

### 3.6 Recording control flags — 🚧 WIP

```swift
public var stopRecordingNow: Bool
public var deviceConnectedBackDuringActivityRecording: Int
public var deviceDisconnectedDuringActivityRecording: Int
public var checkIfActivityHRUploaded: Bool
public var shouldWaitForActivityHRToUpload: Bool
public var firmwareUpdated: Bool
```

---

## 4. Authentication — ✅ Supported

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

### 5.1 Scan & connect — ✅ Supported

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

### 5.2 Device commands — ✅ Supported

```swift
public func userLED(red: Bool = false, green: Bool = false, blue: Bool = false,
                    blink: Bool = false, for seconds: Int)
public func setAskForDeviceResponse(_ enable: Bool)
public func airplaneMode() async throws
public func reset()
public func updateFirmware(_ url: URL, delay: Int? = nil, size: Int? = nil) async throws
```

### 5.3 Recording — 🚧 WIP

```swift
public func startBiometricRecording() async throws   // HR + HRV + RR + SpO2 + ECG
public func startActivityRecording() async throws    // HR only
public func stopRecording() async throws
public func submitFinishedRecording(_ session: SB_FinishedRecordingSession)
```

### 5.4 Sync — ✅ Supported (automatic)

Sync runs automatically once a paired device connects. No customer-side method call is required to trigger it; the SDK manages the sync lifecycle internally and emits state changes via the `@Published` `deviceSyncing` / `percentSynced` / `lastSyncd` properties (see §3.2).

---

## 6. Server APIs (async/await)

Every method below is `async throws` on the `SB_SDK` facade. All return typed `SB_*` domain models; authentication is automatic once the user is signed in. Outcome-style methods (e.g. `signIn`, `updateGoals`) return discriminated enums rather than raw errors for common business cases.

### 6.1 Dashboard — ✅ Supported

```swift
public func fetchDashboardData(date: Date, tzOffset: Int32) async throws -> SB_DashboardData
```

### 6.2 Activity reads — ✅ Supported

```swift
public func fetchSteps(date: Date, granularity: SB_ViewGranularity)        async throws -> SB_StepsTrending
public func fetchCalories(date: Date, granularity: SB_ViewGranularity)     async throws -> SB_CaloriesTrending
public func fetchDailyRecovery(date: Date)                                 async throws -> SB_DailyRecoveryTrending
public func fetchRangeRecovery(date: Date, granularity: SB_ViewGranularity) async throws -> SB_RecoveryRangeTrending
```

### 6.3 Biometric reads — HR / HRV / RR ✅ Supported · SpO2 🚧 WIP

```swift
// ✅ Supported
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

### 6.4 Sleep reads — ✅ Supported

```swift
public func fetchSleepDetail(endDate: Date, endTimestamp: Date)                     async throws -> SB_SleepDetailDay
public func fetchSleepAggregation(date: Date, granularity: SB_ViewGranularity)      async throws -> SB_SleepDetailAggregated
```

### 6.5 Insights — personal + population ✅ Supported · feedback 🚧 WIP

```swift
// ✅ Supported
public func fetchNewInsights() async throws -> SB_NewInsights
public func fetchPopulationInsightsMetricList() async throws -> SB_PopulationInsightsFilterList
public func fetchPopulationInsights(
    ageStart: Int32, ageEnd: Int32,
    gender: SB_PopulationGender, metricType: SB_PopulationMetricType
) async throws -> (histogram: SB_PopulationInsightsHistogram?, radarChart: SB_PopulationInsightsRadarChart?)

// 🚧 WIP
public func submitInsightsFeedback(insightId: Int64, feedback: SB_InsightFeedback) async throws
```

### 6.6 User profile — ✅ Supported

```swift
public func updateUserProfile(_ profile: SB_UserProfileUpdate) async throws -> SB_UpdateUserProfileOutcome
public func refreshUser() async throws
public func uploadUserPhoto(imageData: Data) async throws -> String?
public func deleteUserPhoto() async throws
```

### 6.7 Goals — ✅ Supported

```swift
public func fetchGoals() async throws -> SB_Goals
public func updateGoals(steps: Int, calories: Int, maxHr: Int?, restingHr: Int?, vo2Max: Float?) async throws
```

### 6.8 Sleep writes — ✅ Supported

```swift
public func fetchSleepSessions(date: Date) async throws -> [SB_SleepItem]
public func addSleepSession(onset: Date, wakeUp: Date) async throws
public func modifySleepSession(onset: Date, wakeUp: Date, endTimestamp: Int64, date: Date) async throws
public func deleteSleepSession(endTimestamp: Int64, date: Date) async throws
public func reprocessSleep(endDate: Int32, endTimestamp: Int64) async throws
public func emailSleepReportPDF(date: Date, timestamp: Int64, email: String) async throws
```

### 6.9 Workouts & activities — 🚧 WIP

```swift
public func fetchActivityList() async throws -> SB_ActivityRecordingList
public func fetchWorkoutRecordingInfo() async throws -> SB_WorkoutRecordingInfo
public func fetchWorkoutSummary(date: Date, granularity: SB_SummaryGranularity, workoutType: SB_WorkoutType? = nil) async throws -> [SB_WorkoutItem]
public func fetchWorkoutDetail(workoutTime: Date) async throws -> SB_WorkoutDetail?
public func fetchWorkoutTimeline(date: Date, searchTerm: String = "", filterType: SB_WorkoutEntryType = .all) async throws -> SB_WorkoutTimelineResult
public func modifyWorkout(action: SB_ModifyAction, date: Date, workoutTime: Date, name: String?) async throws -> SB_ModifyOutcome
public func modifyActivityInWorkout(action: SB_ModifyAction, date: Date, startTime: Date, duration: Int32) async throws -> SB_ModifyOutcome
public func fetchMeditationGraph(date: Date, sessionTimestamp: Int64) async throws -> SB_MeditationGraph
```

### 6.10 Spot-check & recording metadata — 🚧 WIP

```swift
public func fetchSpotCheckDetails(id: String) async throws -> SB_SpotCheckDetails?
public func fetchRecordingMetaInfo(_ type: SB_RecordingMetaType) async throws -> [SB_RecordingSessionMeta]
public func deleteRecordingMeta(id: String, name: String, type: SB_RecordingMetaType) async throws
public func fetchRoutineMetadata() async throws -> SB_RoutineMetadata
```

### 6.11 Surveys & questionnaires — 🚧 WIP

```swift
public func fetchCustomQuestionnaire() async throws -> SB_CustomQuestionnaire?
public func submitCustomQuestionnaireAction(questionnaireId: String, action: SB_CustomQuestionnaireButtonAction) async throws
public func submitBriefSurvey(_ survey: SB_BriefSurvey)
public func manageNextSurvey()
```

### 6.12 Devices, services & global state — 🚧 WIP

```swift
public func fetchLockedDevices() async throws -> [String]
public func updateUserDeviceInfo(macAddress: String, metadata: [String: String], unlinkDevice: Bool)
public func uploadLastSyncTime(epoch: Int64, deviceId: String)
public func registerApp(pushToken: String, carrierName: String, deviceId: String) async throws
public func refreshGlobalState() async throws -> SB_OrgMembership
public func refreshUserAppSettings() async throws -> SB_UserAppSettings
public func fetchDailyStats(startDate: Int32, days: Int32, metrics: [String]) async throws -> [SB_DailyStats]
```

---

## 7. Top-Level Symbols & Namespaces

### 7.1 Logging — ✅ Supported

```swift
public enum LogLevel { case verbose, debug, info, warning, error }

extension SB_SDK {
    public static var log: AnyPublisher<(LogLevel, String, String, String, Int), Never>
}
```

Subscribe `SB_SDK.log` to forward SDK log entries into your own logging pipeline (Crashlytics, OSLog, custom file sink, etc.).

### 7.2 Environment — ✅ Supported

```swift
extension SB_SDK {
    public enum Environment {
        case staging
        case production
    }
}
```

### 7.3 Constants namespace — 🚧 WIP

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

### 7.4 Globals namespace — 🚧 WIP

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

### 7.5 Dependency-injection container — 🚧 WIP

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

### 7.6 Diagnostic logger — 🚧 WIP

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

## 8. Domain Types

The SDK ships ~170 public structs and ~65 public enums under `Sources/SensorBioSDK/Structs/` and `Sources/SensorBioSDK/Enums/`. The clusters below are tagged by the support tier of the SDK methods that consume them.

### 8.1 ✅ Supported clusters

These domain types are returned by, or accepted by, the ✅ Supported methods above and are stable for customer integration today.

- **Auth & session** — `SB_Session`, `SB_CreateAccountRequest`, `SB_SignInOutcome`, `SB_CreateAccountOutcome`, `SB_AuthError`, `SB_Gender`, `SB_EmailAvailabilityOutcome`, `SB_ChangePasswordOutcome`, `SB_RequestPasswordResetOutcome`, `SB_AgreementCheck`, `SB_AgreementType`, `SB_ValidateAccountRequirementsRequest`, `SB_ValidateAccountRequirementsResult`, `SB_AccountRequirementStatus`, `SB_SubscriptionDetails`, `SB_ResetPasswordCode`.
- **Device link outcomes** — `SB_DeviceLinkFailure`.
- **User profile & goals** — `SB_UserProfile`, `SB_UserProfileUpdate`, `SB_PhysicalStats`, `SB_CardioStats`, `SB_UnitType`, `SB_UpdateUserProfileOutcome`, `SB_Goals`, `SB_UpdateGoalsOutcome`.
- **Pairing & device** — `SB_DiscoveredDevice`, `SB_PairedDeviceState`, `SB_BluetoothDeviceType`, `SB_DeviceConnectionState`, `SB_NetworkStatus`.
- **Dashboard** — `SB_DashboardData`, `SB_DashboardItemActivity`, `SB_DashboardItemSleep`, `SB_DashboardItemRecovery`, `SB_DashboardCircularItem`, `SB_DashboardMetric`, `SB_DashboardMetricType`, `SB_DashboardMetricFooter`, `SB_DashboardItemRecoveryStage`, `SB_DashboardInsight`, `SB_DashboardSleepRecommendationCard`.
- **Reads — granularity & shared primitives** — `SB_ViewGranularity`, `SB_TimeValuePoint`, `SB_DateValuePoint`, `SB_BarGraph`, `SB_BarGraphDataPoint`, `SB_ValueUnitWrapper`, `SB_ValueUnitBlock`, `SB_RGBAColor`, `SB_Color`, `SB_LineColor`, `SB_HighLightZone`, `SB_Zone`.
- **Activity reads** — `SB_StepsTrending`, `SB_StepsGraph`, `SB_StepMetric`, `SB_StepMetricType`, `SB_CaloriesTrending`, `SB_CaloriesGraph`, `SB_CalorieMetric`, `SB_DailyRecoveryTrending`, `SB_DailyRecoveryGraph`, `SB_RecoveryRangeTrending`, `SB_RecoveryRangeGraph`, `SB_RecoveryScoreSection`, `SB_RecoveryScoreFactor`.
- **Biometric reads (HR/HRV/RR)** — `SB_HRDailyTrending`, `SB_HRRangeTrending`, `SB_HRDailyGraph`, `SB_HRRangeGraph`, `SB_HRVDailyTrending`, `SB_HRVRangeTrending`, `SB_HRVDailyGraph`, `SB_HRVRangeGraph`, `SB_RRDailyTrending`, `SB_RRRangeTrending`, `SB_RRDailyGraph`, `SB_RRRangeGraph`, `SB_HeartRateTimeValuePoint`, `SB_HRVTimeValuePoint`, `SB_HeartRateValueType`, `SB_HRVValueType`.
- **Sleep reads & writes** — `SB_SleepDetailDay`, `SB_SleepDetailAggregated`, `SB_SleepSession`, `SB_SleepItem`, `SB_SleepStages`, `SB_SleepStagesAggregated`, `SB_SleepStageInterval`, `SB_SleepSessionStage`, `SB_SleepBiometrics`, `SB_SleepBiometricGraph`, `SB_SleepDisturbances`, `SB_DisturbanceStage`, `SB_DisturbanceGraph`, `SB_SleepScore`, `SB_SleepScoreSection`, `SB_SleepScoreFactor`, `SB_SleepScorePenalty`, `SB_SleepStage`, `SB_SleepStatus`, `SB_SleepMetricValue`, `SB_SleepApneaInfo`, `SB_ApneaEvent`, `SB_SleepPosition`, `SB_SleepPositionInfo`, `SB_SleepPositionInterval`, `SB_SleepPositionState`, `SB_SleepDebtAggregatedGraph`, `SB_SleepDebtDateValuePointWrapper`, `SB_SleepBedtimeRecommendation`, `SB_SleepTrend`, `SB_SleepTrendChart`, `SB_SleepScoreProcessState`, `SB_SleepAccounting`, `SB_SleepAccountingItem`.
- **Insights** — `SB_NewInsights`, `SB_InsightItem`, `SB_InsightItemGroup`, `SB_InsightInfluencer`, `SB_InsightError`, `SB_PopulationInsightsFilterList`, `SB_PopulationInsightMetric`, `SB_PopulationInsightsHistogram`, `SB_PopulationInsightsRadarChart`, `SB_PopulationAgeGroup`, `SB_PopulationMetricType`, `SB_PopulationGender`, `SB_RadarChartPoint`, `SB_RadarPair`.

### 8.2 🚧 WIP clusters

- **Org / settings** — `SB_UserAppSettings`, `SB_OrgMembership`, `SB_OrganizationMemberStatus`, `SB_ExerciseZoneAttributes`.
- **SpO2 reads** — `SB_SpO2DailyTrending`, `SB_SpO2RangeTrending`, `SB_SpO2DailyGraph`, `SB_SpO2RangeGraph`.
- **Workouts / activities** — `SB_ActivityRecordingList`, `SB_ActivityTimeline`, `SB_ActivitySummary`, `SB_ActivitySummarySet`, `SB_ActiveWorkoutSegment`, `SB_WorkoutItem`, `SB_WorkoutDetail`, `SB_WorkoutSummaryMetric`, `SB_WorkoutTimelineResult`, `SB_WorkoutEntry`, `SB_WorkoutRecordingInfo`, `SB_WorkoutType`, `SB_WorkoutEntryType`, `SB_WorkoutMetricType`, `SB_WorkoutDetailValueType`, `SB_ModifyAction`, `SB_ModifyOutcome`, `SB_MeditationGraph`, `SB_OngoingWorkoutProgram`, `SB_ARDADetails`, `SB_ARDARunningTimeline`, `SB_ARDATrainingTypeMetrics`, `SB_HRMValues`, `SB_HRMExerciseZone`, `SB_HRMData`, `SB_HRMCategory`, `SB_HREffortZone`.
- **Recording & upload** — `SB_FinishedRecordingSession`, `SB_FinishedRecordingType`, `SB_RecordingSessionMeta`, `SB_RecordingMetaType`, `SB_RecordingState`, `SB_DailyStats`, `SB_DailyStatsResponse`.
- **Spot-check & live telemetry** — `SB_SpotCheckDetails`, `SB_SpotCheckMeasurements`, `SB_SpotCheckResult`, `SB_LiveMetric`.
- **Insights extras** — `SB_InsightFeedback`, `SB_ExperimentRecommendation`, `SB_RoutineMetadata`, `SB_RoutineGoal`.
- **Surveys / questionnaires / white-label** — `SB_WhiteLabelSettings`, `SB_WhiteLabelScheduledSurveyTime`, `SB_WhiteLabelRecordingSurveyInfo`, `SB_WhiteLabelDefaultSimpleCard`, `SB_WhiteLabelLinkButton`, `SB_WhiteLabelRecordingType`, `SB_LinkButtonAuthTokenType`, `SB_CustomQuestionnaire`, `SB_CustomQuestionnaireButton`, `SB_CustomQuestionnaireButtonStyle`, `SB_CustomQuestionnaireButtonAction`, `SB_BriefSurvey`, `SB_BriefSurveyQuestion`, `SB_BriefSurveyType`, `SB_BriefSurveyAnswer`.
- **Misc** — `SB_AnalyticsEvent`, `SB_NotificationElement`, `SB_NotificationElemType`, `SB_TimestampTZ`, `SB_TimeTzWrapper`, `SB_GPSData`, `SB_GPSPoint`, `SB_FormattedUnitValueMetric`, `SB_GraphHeaderTag`, `SB_HistogramPair`, `SB_PoincarePlotGraph`, `SB_PoincarePoint`, `SB_ValueWithBaselineInfoCard`, `SB_TimelineBlock`, `SB_TimeSegment`, `SB_WMYChart`, `SB_TimeValueStraightLine`, `SB_ValueType`, `SB_PageFetchDirection`, `SB_DeviceSyncStatus`, `SB_PedometerEngineDelegateType`, `SB_ServerActivityInfoKeys`, `SB_ServerWorkoutInfoKeys`, `SB_ServerMetaDataKeys`, `SB_ServerDeviceName`, `SB_MobileApplicationLogLevel`, `SB_MobileDashboardRefreshOption`, `SB_SummaryGranularity`.

---

## 9. Protocols

```swift
public protocol SleepDetectionDelegate: AnyObject {
    func detectedSleep(startEpochInms: Int64, endEpochms: Int64)
}
```

This is the **only** customer-facing protocol. It is currently 🚧 WIP.

---

## 10. Putting it together — minimal example (✅ Supported surface only)

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

---

## 11. Other library products you may see

If you inspect the SDK package and see library products other than `SensorBioSDK`, treat them as **internal build-graph dependencies**. They are not part of the customer API surface, and customer apps should never import them directly — `import SensorBioSDK` is always sufficient. All sensor-decoding, sleep-analysis, and packet-processing behavior is exposed through the public API documented above.
