# SensorBioSDK — Binary Distribution

Customer-facing binary distribution of the Sensr-Bio iOS SDK. This repository contains:

- **`SensorBio/`** — the three `.xcframework` files + the binary podspec that wires them into your app
- **`SDK_INTERFACE.md`** — the public API reference
- **`ExampleApp/`** — a reference SwiftUI integration you can build + run

## What ships

| File | Size | Contents |
|------|------|----------|
| `SensorBio/SensorBioSDK.xcframework` | 120 MB | The customer-facing Swift API — auth, dashboard / sleep / activity / biometric reads, recording orchestration, upload pipeline. Bundles the on-device DSP (HRV / sleep / activity computation) and SwiftProtobuf-compiled wire types. |
| `SensorBio/SensorBioBTSDK.xcframework` | 20 MB | The Sensr-Bio BLE pairing + sync pipeline. Talks to Sensr-Bio wearables over CoreBluetooth. Linked transitively — you don't call into it directly. |
| `SensorBio/LibFXC.xcframework` | 400 KB | Philips proprietary FXC sleep-staging engine. Linked transitively from `SensorBioBTSDK`. |
| `SensorBioSDK.podspec` (repo root) | — | Umbrella binary podspec — vendors the three xcframeworks above and declares the third-party CocoaPods that have to come from CocoaPods trunk. |

All three xcframeworks are iOS-only (device + arm64 simulator). They cannot run on macOS or Intel Mac simulators.

## Requirements

- **Xcode 16.3+** (Swift 6.1 toolchain)
- **iOS 18+** deployment target
- **CocoaPods 1.16+** — `sudo gem install cocoapods` or `brew install cocoapods`

## Integrating into your app

### 1. Add SensorBioSDK to your `Podfile`

If your `Podfile` doesn't exist yet, create one. The minimum looks like:

```ruby
platform :ios, '18.0'

target 'YourApp' do
  use_frameworks!

  pod 'SensorBioSDK',
    :git => 'git@github.com:GetSensr-io/mobile_sensorbio_sdk_ios_binary.git',
    :tag => 'v2.3.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Required: SensorBioSDK is iOS 18+; transitive pods default lower
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']     = '18.0'
      # Required: abseil (pulled in transitively by gRPC-Core) needs C++17
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD']    = 'c++17'
      config.build_settings['CLANG_CXX_LIBRARY']              = 'libc++'
      # Required: SensorBioSDK.xcframework was built with library-evolution
      # mode, so its Job subclasses reference SwiftQueue's `Job.onRetry` via
      # Swift method descriptors. The transitive pods (SwiftQueue, etc.) must
      # also be built with library-evolution for those descriptors to exist.
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
```

CocoaPods clones the binary repo at the pinned tag, finds the umbrella `SensorBioSDK.podspec` at the root, and links the three xcframeworks from `SensorBio/`. No source code is shipped; no manual file copy.

The single `pod 'SensorBioSDK'` line transitively brings:

- The 3 SensorBio xcframeworks (via `vendored_frameworks` inside the podspec)
- `gRPC-ProtoRPC` (which transitively brings gRPC-Core + abseil + BoringSSL-GRPC + the ObjC Protobuf runtime)
- `SwiftProtobuf` (Swift wire-type runtime)
- `SwiftKeychainWrapper` + `KeychainAccess` (keychain helpers)
- `SwiftQueue` (persistent job-queue runtime)
- `CocoaMQTT` (MQTT client for the license-key broker)

### 2. Run `pod install`

```bash
pod install
```

Open `YourApp.xcworkspace` (not `.xcodeproj`) in Xcode going forward.

### 3. Use the SDK

The customer-facing entry point is a top-level `sensorBio` accessor (the singleton `SB_SDK.shared`). The framework module is `SensorBioSDK`; the singleton class inside it is `SB_SDK`.

```swift
import SwiftUI
import SensorBioSDK

@main
struct YourApp: App {
    init() {
        SB_SDK.environment = .production
        SB_SDK.bootstrapKeychain()
        SB_SDK.runDefaultsMigratorIfNeeded()
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// Anywhere in your app — `registerUser` is register-or-login for a user your
// app has already authenticated by its own means:
func startSensorBioSession(userId: String) async throws {
    switch try await sensorBio.registerUser(userId: userId) {
    case .success(let session):    routeToHome(session)
    case .failure(let errorCode):  showError(errorCode)
    }
}
```

There is no email/password sign-in in the shipped SDK — `signIn` and
`createAccount` are first-party-only and compile-stripped from this binary.
`registerUser` needs `SB_SDK.sdkKeyCredentials` set first (see
[`SDK_INTERFACE.md`](./SDK_INTERFACE.md) § 4), or it fails with
`sdkKeyCredentialsNotSet`.

See **[`SDK_INTERFACE.md`](./SDK_INTERFACE.md)** for the full public surface.

## Reference integration

**[`ExampleApp/`](./ExampleApp)** is a minimal SwiftUI app demonstrating the integration pattern. From inside that directory: `pod install`, then open `ExampleApp.xcworkspace`. It hits a dev backend and pairs against any Sensr-Bio wearable.

## Updating

When a new SDK version drops:

1. Bump the `:tag` in your `Podfile` to the new version (`:tag => 'vX.Y.Z'`).
2. `pod update SensorBioSDK`.
3. Open the workspace, rebuild.

There are no files to copy by hand — CocoaPods clones this repo at the tag and
links the xcframeworks out of it.

`SDK_INTERFACE.md` documents any breaking changes per release.

## Release notes

> **An earlier, different `v2.3.0` was published and withdrawn on September 9, 2026.**
> That build linked gRPC inside the framework and could not resolve the API host —
> every RPC failed with `UNAVAILABLE ("empty address list")` — and its tag was deleted.
> The `v2.3.0` below is a **new build, cut on September 10, 2026**, and does not contain
> that change. If you installed the withdrawn one, run `pod cache clean SensorBioSDK`
> and re-install to pick up the replacement.

### v2.3.0 — September 10, 2026

- **Detected activities are now stored and offered rather than uploaded automatically.** New API: `detectedActivities()`, `detectedActivitiesPublisher`, `confirmDetectedActivity(startTsMillis:activityName:)` and `dismissDetectedActivity(startTsMillis:)` — show your user the activity the band detected and upload only what they confirm. The surface matches the Android SDK.
- **Register on a single-use token instead of putting your SDK Key on the device.** Your backend exchanges your organization SDK Key (`sbsk_…`) for a short-lived, single-use `sdk_token` (`sbst_…`), and your app passes it to `registerUser(userId:sdkToken:)` — or you set `SB_SDK.sdkTokenProvider` and let the SDK ask for one when it needs it. **No change is required to upgrade**: the existing org-key path still works. `SDK_INTERFACE.md` §5 documents the exchange endpoint in full, with Node and Go reference implementations.
- **New `reauthenticationRequired` event.** It fires when an authenticated call has no stored credential to send, so you can route the user to sign-in. Such a call is now refused rather than sent without credentials and failing opaquely.
- Packet upload has exactly one trigger — the processed sync — and the drain itself is hardened. Fewer redundant uploads, and raw sync no longer pulls on a trickle of queued packets.
- Fixed: the sensor-config tracker cleared the wrong preferences store, and the `Codable` preference helpers ignored the store they were called on.


### v0.4.0 — May 22, 2026

- SDK now owns biometric, meditation, and activity recording orchestration end-to-end — host app awaits one async call (`recordDetailedBiometrics`, `recordMeditation`, `recordActivity`) and the SDK manages BLE start/stop, the timer, post-stop sync, session build, and submission.
- In-flight recordings persist across app kill and resume (or auto-finalize) on relaunch. New surface: `activeRecording`, `awaitActiveRecordingCompletion()`, `cancelCurrentRecording()`. See `SDK_INTERFACE.md` §5.3.
- **Breaking:** public-surface rename `spotCheck*` → `biometricRecord*` (`recordSpotCheck` → `recordDetailedBiometrics`, `SB_SpotCheck*` types → `SB_BiometricRecord*`). Update call sites.
- One-shot migration of legacy host-app UserDefaults + Keychain on first SDK launch — signed-in users and paired devices survive the upgrade from older host-app builds where these were app-side.
- SensrV1 hardware now appears in pair-scan results alongside V2 / V2.5 / V3.
- Stable cache keys for sleep-detail and dashboard endpoints (eliminates spurious cache misses).

## Support

For integration help, contact support@sensorbio.com.
