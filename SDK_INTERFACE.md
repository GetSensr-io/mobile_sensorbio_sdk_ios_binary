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
    :tag => 'v1.2.0'
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
| `latestDeviceEpochInMillis` | `Int64` | Epoch (ms) of the newest sensor packet synced from the device; advanced only from real packet timestamps (never wall-clock). Diagnostic (Developer Tools); recording finalize gates on the device bookend, not this |

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

// SDK-key auth (externally-authenticated, password-less users — SB-957).
// Configure `SB_SDK.sdkKeyCredentials` once (like `SB_SDK.environment`),
// then register with just the user identity — see §4.1.
public static var sdkKeyCredentials: SB_SDKKeyCredentials?   // host-supplied org creds; in-memory only, never persisted
public func registerUser(
    userId: String,
    email: String? = nil,
    birthday: DateComponents? = nil,
    sex: SB_Gender? = nil,
    heightCm: Float? = nil,
    weightKg: Float? = nil,
    imperialUnits: Bool = false,
    activationCode: String? = nil
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



Example:

`signIn` never throws for a login error: bad credentials surface as
`.passwordIncorrect` / `.unknownUsername`, and every other failure — a
transport-level gRPC error or a non-credential in-band server code — surfaces as
`.failed(code:)` carrying a typed `SB_ServiceErrorCode` (no raw gRPC message
string crosses the boundary). Map the code to your own localized copy:

```swift
do {
    switch try await sensorBio.signIn(email: email, password: password) {
    case .success:           routeToHome()
    case .passwordIncorrect,
         .unknownUsername:   showError("Incorrect username or password")
    case .failed(let code):
        switch code {
        case .unauthenticated:  showError("Incorrect username or password")
        case .permissionDenied: showError("No active device subscription — contact your administrator.")
        default:                showError("Something went wrong while signing in. (Error code: \(code.name))")
        }
    }
} catch {
    // Defensive only — `signIn` resolves login errors to `.failed(code:)`.
    showError("Something went wrong while signing in.")
}
```

> **`signOut()` side effects.** A successful sign-out disconnects any connected device, clears the paired-device state, nils out `pairedDevice` / `haveDevice` / `exerciseZoneAttributes`, and wipes the SDK's locally cached user data. `signOut()` is the **only** customer-facing way to clear SDK persistence — a wipe without a sign-out would leave in-memory `@Published` state and the BLE connection inconsistent with the cleared cache. Account-deletion flows should call `signOut()` after the delete-account call succeeds.

### 4.1 SDK-key registration (`registerUser`)

For third-party apps embedding the SDK, `registerUser` is a **register-or-login** entry point for users your app has already authenticated by its own means (your login, SSO, OAuth — the SDK doesn't care which). These users have **no** Sensor Bio email/password. On success the SDK persists the returned session and publishes `session` / `userProfile`, exactly like `signIn`.

**Configure your org credentials first.** The SDK reads your organization credentials from `SB_SDK.sdkKeyCredentials`, which you set **once** (like `SB_SDK.environment`) before registering. The SDK holds them **in memory only — it never persists them**, and it uses them on every authenticated call for the session (not just registration). Because they are not persisted, a host that relaunches into a **hydrated** session (restored from the keychain) **must set `sdkKeyCredentials` again at launch, before the first authenticated call** (e.g. in `App.init`, alongside `SB_SDK.environment`).

```swift
public struct SB_SDKKeyCredentials: Sendable, Equatable {
    public let orgId: String   // server-issued organization UUID (from your Sensor Bio dashboard)
    public let sdkKey: String  // server-issued SDK key; validated as active and belonging to orgId
    public init(orgId: String, sdkKey: String)
}

// e.g. in App.init, and again after a cold launch that hydrates a session:
SB_SDK.sdkKeyCredentials = SB_SDKKeyCredentials(orgId: orgId, sdkKey: sdkKey)
```

`registerUser` parameters:

- **`userId`** — your own stable identifier for the end-user (`client_sdk_user_id`). The first call for a given `userId` registers; subsequent calls log in. It is also recorded as the user's **username** (visible in the web dashboard).
- **`email`** *(optional)* — a contact email. Omitted if nil/empty; when supplied it is recorded on the backend as the user's contact email (never used as the login identity).
- **`birthday` / `sex` / `heightCm` / `weightKg` / `imperialUnits`** *(optional)* — demographics. **Any omitted value is filled with a dummy** before the request is sent: the platform requires height/weight/sex/birthday to compute higher-level metrics (recovery, calories, sleep scoring, …), so a user with none would break downstream processing. Pass real values when you have them.
- **`activationCode`** *(optional)* — redeems a device-subscription activation code during a first registration (same flow as `createAccount`).

> The org credentials come from `SB_SDK.sdkKeyCredentials`, **not** from parameters on `registerUser` — set them once (above) and pass only the user identity here. If `sdkKeyCredentials` is unset, `registerUser` returns `.failure(errorCode: "sdkKeyCredentialsNotSet")`.

```swift
// SB_SDK.sdkKeyCredentials must already be set (see above).
switch try await sensorBio.registerUser(userId: userId) {
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

---

## 5. BLE Device Control

### 5.1 Scan & connect

```swift
public func startScan()
public func stopScan()
public func connect(_ id: String, pairing: Bool = false)
public func disconnect(_ id: String? = nil)
public func removeDeviceFromPairedDevices(_ id: String)   // unpair: also clears the persisted paired-device store
public func persistPairedDevice(macAddress: String, name: String, type: SB_BluetoothDeviceType)
public func clearPairedDevice()
public internal(set) var isSigningOut: Bool               // true from signOut() until the next signIn/createAccount
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

The SDK owns paired-device persistence end-to-end — there is no app-built devices dictionary. On a successful pair the host calls `persistPairedDevice(macAddress:name:type:)`; the SDK serializes the identity to `devicesKey`, updates `pairedDevice`, and registers the device with the BLE layer. `clearPairedDevice()` wipes the paired snapshot (cancelled pair / pre-scan reset), and `removeDeviceFromPairedDevices(_:)` clears it on an explicit unpair; `signOut()` clears it too. `isSigningOut` is read-only state the SDK uses to gate BLE auto-reconnect across the signed-out window.

Static bootstrap accessor (callable before `SB_SDK.shared` initializes):

```swift
public static var persistedDevicesDictionary: [String: AnyObject]?      // persisted devices dict (devicesKey)
```

### 5.2 Device commands

```swift
public func userLED(red: Bool = false, green: Bool = false, blue: Bool = false,
                    blink: Bool = false, for seconds: Int) async throws
public func hapticMotor(pulse: Bool = false, intensity: Int, for seconds: Int) async throws
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

public func pauseRecording()                // freeze the timer + stop the device stream
public func resumeRecording()               // restart the device stream + resume the timer
```

`recordActivity(...)` is open-ended — it has no `duration:` parameter and runs until `finishCurrentRecording()` flips or the calling `Task` cancels. `recordingState` publishes `.recording(elapsed:, target: nil)` so countdown UIs render count-up format from the `nil` target.

**Pause / resume** (`recordActivity` + `recordMeditation`). `pauseRecording()` freezes the elapsed clock (`recordingState` holds its last `.recording(elapsed:, target:)` value and `canFinalize` stops advancing) and stops the device's manual PPG stream, so the paused span carries no biometric data. `resumeRecording()` restarts the stream and continues the clock. Both are no-ops outside an active recording; the device stop/start is a fire-and-forget BLE round-trip so the timer freezes/thaws instantly. Each paused window is submitted as the complement `activeWorkoutSegments` on the finished session, so downstream sees only the active spans.

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

**Upload is automatic too.** Every data type the device produces — biometrics, activity, steps, temperature, and **sleep** — is uploaded to the server by the SDK with no customer-side trigger. Uploads are driven off sync completion and a persistent, retrying job queue that survives app relaunches and waits for connectivity, so there is nothing to call and nothing to schedule. (Sleep upload previously exposed `SB_OnDeviceSleepDecoder.launchSleepUploadThread()`; that is removed — sleep is now handled internally like every other type.)

---

## 6. Server APIs (async/await)

Every method below is `async throws` on the `SB_SDK` facade. All return typed `SB_*` domain models; authentication is automatic once the user is signed in. Outcome-style methods (e.g. `signIn`, `updateGoals`) return discriminated enums rather than raw errors for common business cases.

**Caching (dashboard + detail reads).** These reads are disk-cache-backed. The policy has three cases:

- **Today** (any granularity) is always fetched fresh so the latest server data wins. The response is still cached, and on a network failure the last cached payload is returned — a cold relaunch with no connectivity shows stale "today" instead of a blank screen.
- **A past date** is served straight from the on-disk cache with no network call — *but only once that cache is final*, i.e. it was written after the date's own calendar day ended. An entry cached while the date was still "today" is provisional (the day was still accumulating — a late device sync, a sleep the server scores hours later), so the first time you open that day *after it has passed* the SDK refetches once to finalize it, then serves from cache thereafter. This is transparent to the caller: keep calling `fetch…` on load and the SDK decides whether a network hit is needed.
- **`forceRemote: true`** (pull-to-refresh) always fetches, regardless of the above.

**Stale-while-revalidate streams.** Each cache-backed read also has an `…Updates(…)` variant returning `AsyncThrowingStream<T, Error>` that **yields the last cached value first (if any), then the fresh server value** — consume it with `for try await v in …`. This replaces the older synchronous `cachedX(for:)` peeks (removed): the peek read the store on the caller's (main) thread; the stream reads off-main and non-blocking (SB-1546), so `for try await` inside a `@MainActor` Task both paints instantly *and* keeps the UI thread free. On a fetch failure with a cached value present, the cached value is delivered and the stream finishes (no throw); with nothing cached it throws. `fetch…` (single value) is retained for pull-to-refresh (`forceRemote: true`) and one-shot reads. The stream variants: `dashboardUpdates(for:tzOffset:)`, `dailyHRUpdates(for:)` / `rangeHRUpdates(for:granularity:)` (and the HRV / RR / SpO2 equivalents), `stepsUpdates(for:granularity:)`, `caloriesUpdates(for:granularity:)`, `dailyActivityDetailUpdates(for:granularity:)`, `dailyRecoveryUpdates(for:)` / `rangeRecoveryUpdates(for:granularity:)`, `sleepDetailUpdates(endDate:endTimestamp:)`, and `sleepAggregationUpdates(for:granularity:)`. Each takes a trailing `forceRemote: Bool = false`.

> **Non-blocking store access (SB-1546).** All SDK SwiftData reads/writes on the async path (`getSkinTemperature`, the cache reads/writes behind the streams, and the packet-upload queue ops) now suspend on the store's serial queue rather than blocking the calling thread. `getSkinTemperature(date:)` is therefore `async`.

> **`forceRemote` (pull-to-refresh).** Every cache-backed `fetch…` read takes a trailing `forceRemote: Bool = false`. When `true`, every cache shortcut is bypassed and the read always hits the network (still writing the fresh result to the cache, and still falling back to the cached payload on a network failure). Pass `forceRemote: true` from a user-initiated refresh. This is the escape hatch for data that changes after the fact — a device synced days later, or sleep/recovery **scores** the server finishes processing asynchronously after upload — on top of the automatic provisional-cache refetch described above.

### 6.1 Dashboard

```swift
public func fetchDashboardData(date: Date, tzOffset: Int32, forceRemote: Bool = false) async throws -> SB_DashboardData
```

### 6.2 Activity reads

```swift
public func fetchSteps(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)        async throws -> SB_StepsTrending
public func fetchCalories(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)     async throws -> SB_CaloriesTrending
public func fetchDailyActivityDetail(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false) async throws -> SB_DailyActivityDetail
public func fetchDailyRecovery(date: Date, forceRemote: Bool = false)                                 async throws -> SB_DailyRecoveryTrending
public func fetchRangeRecovery(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false) async throws -> SB_RecoveryRangeTrending
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

`fetchDailyRecovery` / `fetchRangeRecovery` return the recovery **score** (via `goalItem`) plus the sleep-derived context that fed it. Both trending wrappers also carry the signed-in user's `joinedDate` (sourced from the profile, not the recovery payload) so the app can describe the averaging window:

```swift
public struct SB_DailyRecoveryTrending: Codable, Equatable, Sendable {
    public var graph: SB_DailyRecoveryGraph?
    public var joinedDate: Date?             // from the user profile, nil if unknown
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

### 6.3 Biometric reads — HR / HRV / RR · SpO2 🚧 WIP

```swift
public func fetchDailyHR(date: Date, forceRemote: Bool = false)                                       async throws -> SB_HRDailyTrending
public func fetchRangeHR(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)      async throws -> SB_HRRangeTrending
public func fetchDailyHRV(date: Date, forceRemote: Bool = false)                                      async throws -> SB_HRVDailyTrending
public func fetchRangeHRV(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)     async throws -> SB_HRVRangeTrending
public func fetchDailyRR(date: Date, forceRemote: Bool = false)                                       async throws -> SB_RRDailyTrending
public func fetchRangeRR(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)      async throws -> SB_RRRangeTrending

// 🚧 WIP
public func fetchDailySpO2(date: Date, forceRemote: Bool = false)                                     async throws -> SB_SpO2DailyTrending
public func fetchRangeSpO2(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)    async throws -> SB_SpO2RangeTrending
```

### 6.4 Sleep reads

```swift
public func fetchSleepDetail(endDate: Date, endTimestamp: Int64, forceRemote: Bool = false)                     async throws -> SB_SleepDetailDay
public func fetchSleepAggregation(date: Date, granularity: SB_ViewGranularity, forceRemote: Bool = false)      async throws -> SB_SleepDetailAggregated
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

> **`location` is a full-replace field.** `SB_UserProfileUpdate.location` and `SB_UserProfile.location`
> name the same value — the user's location (city / country). It maps to a wire field historically
> named `zipcode`. `updateUserProfile` replaces the whole profile, so read the current value from
> `sensorBio.userProfile?.location` and pass it back in on every update; sending `""` (or omitting it)
> overwrites the stored value on the server.

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
    }

    func signIn(email: String, password: String) async {
        do {
            switch try await sensorBio.signIn(email: email, password: password) {
            case .success:
                await refreshDashboard()
            case .passwordIncorrect, .unknownUsername, .failed:
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

