# SensorBioSDK — Binary Distribution

Customer-facing binary distribution of the Sensr-Bio iOS SDK. This repository contains:

- **`SensorBio/`** — the three `.xcframework` files + the binary podspec that wires them into your app
- **`SDK_INTERFACE.md`** — the public API reference
- **`ExampleApp/`** — a reference SwiftUI integration you can build + run

## What ships

| File | Size | Contents |
|------|------|----------|
| `SensorBio/SensorBioSDK.xcframework` | 215 MB | The customer-facing Swift API — auth, dashboard / sleep / activity / biometric reads, recording orchestration, upload pipeline. Bundles the on-device DSP (HRV / sleep / activity computation) and SwiftProtobuf-compiled wire types. |
| `SensorBio/SensorBioBTSDK.xcframework` | 20 MB | The Sensr-Bio BLE pairing + sync pipeline. Talks to Sensr-Bio wearables over CoreBluetooth. Linked transitively — you don't call into it directly. |
| `SensorBio/LibFXC.xcframework` | 704 KB | Philips proprietary FXC sleep-staging engine. Linked transitively from `SensorBioBTSDK`. |
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
      # Retained, no longer load-bearing: this existed because abseil arrived
      # as a transitive pod and static-asserts C++17 on every translation
      # unit. abseil now lives inside the xcframework and your build compiles
      # no C++ of its own. Harmless to keep.
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
- `SwiftProtobuf` (Swift wire-type runtime)
- `SwiftKeychainWrapper` + `KeychainAccess` (keychain helpers)
- `SwiftQueue` (persistent job-queue runtime)
- `CocoaMQTT` (MQTT client for the license-key broker)

**No gRPC.** gRPC-Core, abseil and BoringSSL are linked inside
`SensorBioSDK.xcframework` with their symbols demoted to `private_extern`, so
they never enter your dependency graph and cannot collide with a gRPC your app
links for its own reasons. This matters most for Firestore users: Firebase
pins its own prebuilt gRPC via SPM, and two gRPC C-cores in one process
coalesce — gRPC's C symbols carry no version namespace the way abseil's
`absl::lts_YYYYMMDD` does — leaving one stack executing against the other's
objects. Do not add a gRPC pod to work around anything; there is nothing to
reconcile, and adding one brings the collision back.

You can confirm what you received:

```bash
nm -m SensorBio/SensorBioSDK.xcframework/ios-arm64/SensorBioSDK.framework/SensorBioSDK \
  | grep -vE 'non-external|private external' | grep -v '(undefined)' \
  | grep -oE '_[A-Za-z0-9_$.]+$' \
  | grep -iE 'grpc|absl|openssl' | grep -v '12SensorBioSDK'
```

That prints nothing. A plain `nm | grep grpc` shows thousands of hits and
means nothing — the code is there, it is simply unreachable by your linker.

### 2. Run `pod install`

```bash
pod install
```

Open `YourApp.xcworkspace` (not `.xcodeproj`) in Xcode going forward.

### 3. Use the SDK

The customer-facing entry point is a top-level `sensorBio` accessor (the singleton `SB_SDK.shared`). The framework module is `SensorBioSDK`; the singleton class inside it is `SB_SDK`.

```swift
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

// Anywhere in your app:
let result = try await sensorBio.signIn(email: email, password: password)
```

See **[`SDK_INTERFACE.md`](./SDK_INTERFACE.md)** for the full public surface.

## Reference integration

**[`ExampleApp/`](./ExampleApp)** is a minimal SwiftUI app demonstrating the integration pattern. From inside that directory: `pod install`, then open `ExampleApp.xcworkspace`. It hits a dev backend and pairs against any Sensr-Bio wearable.

## Updating

When a new SDK version drops:

1. Pull the latest tag of this repo.
2. Replace the three `.xcframework` directories in your project's `SensorBio/` with the new ones.
3. Bump the version pin in your `Podfile` if you reference a specific tag (`pod 'SensorBioSDK', :git => '...', :tag => 'vX.Y.Z'`).
4. `pod update SensorBioSDK`.
5. Open the workspace, rebuild.

`SDK_INTERFACE.md` documents any breaking changes per release.

## Release notes

### v0.4.0 — May 22, 2026

- SDK now owns biometric, meditation, and activity recording orchestration end-to-end — host app awaits one async call (`recordDetailedBiometrics`, `recordMeditation`, `recordActivity`) and the SDK manages BLE start/stop, the timer, post-stop sync, session build, and submission.
- In-flight recordings persist across app kill and resume (or auto-finalize) on relaunch. New surface: `activeRecording`, `awaitActiveRecordingCompletion()`, `cancelCurrentRecording()`. See `SDK_INTERFACE.md` §5.3.
- **Breaking:** public-surface rename `spotCheck*` → `biometricRecord*` (`recordSpotCheck` → `recordDetailedBiometrics`, `SB_SpotCheck*` types → `SB_BiometricRecord*`). Update call sites.
- One-shot migration of legacy host-app UserDefaults + Keychain on first SDK launch — signed-in users and paired devices survive the upgrade from older host-app builds where these were app-side.
- SensrV1 hardware now appears in pair-scan results alongside V2 / V2.5 / V3.
- Stable cache keys for sleep-detail and dashboard endpoints (eliminates spurious cache misses).

## Support

For integration help, contact support@sensorbio.com.
