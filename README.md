# SensorBioSDK — Binary Distribution

Customer-facing binary distribution of the Sensr-Bio iOS SDK. This repository contains:

- **`SensorBio/`** — the three `.xcframework` files + the binary podspec that wires them into your app
- **`SDK_INTERFACE.md`** — the public API reference
- **`ExampleApp/`** — a reference SwiftUI integration you can build + run

## What ships

| File | Size | Contents |
|------|------|----------|
| `SensorBio/SensorBioSDK.xcframework` | 159 MB | The customer-facing Swift API — auth, dashboard / sleep / activity / biometric reads, recording orchestration, upload pipeline. Bundles the on-device DSP (HRV / sleep / activity computation) and SwiftProtobuf-compiled wire types. |
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
      # Required: the SDK is built with library evolution and extends types
      # from the pods below, so they must be built the same way.
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

        // Required. `org_id` is the `organization_id` the token exchange
        // returns; `sdk_token` is your organization SDK Key. The SDK holds
        // these in memory only and never persists them, so set them on every
        // launch — including a cold launch that hydrates a stored session,
        // before the first authenticated call.
        SB_SDK.sdkKeyCredentials = SB_SDKKeyCredentials(org_id: orgId, sdk_token: orgSDKKey)

        // Recommended. The SDK calls this when it needs a single-use
        // registration token: at `registerUser`, and again if a session dies
        // beyond recovery. It stores your closure, never a token. Throw to
        // refuse. Without it, pass `sdkToken:` to every `registerUser` call
        // and handle `SB_AuthError.refreshTokenExpired` yourself.
        SB_SDK.sdkTokenProvider = { try await yourBackend.mintSDKToken() }
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// `registerUser` is register-or-login for a user your app has already
// authenticated by its own means. First call for a `userId` registers;
// later ones log in.
func startSensorBioSession(userId: String) async throws {
    switch try await sensorBio.registerUser(userId: userId) {
    case .success(let session):    routeToHome(session)
    case .failure(let errorCode):  showError(errorCode)
    }
}
```

Those two properties are **complementary, not alternatives** — `sdkKeyCredentials`
identifies your organization on every authenticated call and is required
(`registerUser` fails with `sdkKeyCredentialsNotSet` without it), while
`sdkTokenProvider` supplies the short-lived, single-use token each registration
consumes. There is no email/password sign-in in the shipped SDK.

> **This part is changing.** `sdkKeyCredentials.sdk_token` currently holds your
> organization SDK Key, so the key has to be present in the app. We are removing
> that requirement — a coming release takes `org_id` plus the single-use token
> your backend mints and nothing else, so the key stays on your server. If you
> are integrating now, keep the key somewhere you can swap out easily; the
> change will be a small edit at this one call site, and the field's misleading
> name goes with it.

Your backend mints those single-use tokens by exchanging your SDK Key against
`POST /sdk/v1/token`; § 5 of [`SDK_INTERFACE.md`](./SDK_INTERFACE.md) covers the
endpoint, Node and Go implementations, and the errors it returns. `ExampleApp/`
mocks that exchange in-process so the SDK can be run without a backend — it is a
stand-in, not a pattern to copy.

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

Only notable releases are itemised here. Every published version is a tag in
this repo — `git tag --sort=v:refname` for the full list, and
[`SDK_INTERFACE.md`](./SDK_INTERFACE.md) always describes the surface of the
tag you have checked out.

### v2.3.0 — September 9, 2026

- **gRPC no longer enters your dependency graph.** gRPC-Core, abseil and BoringSSL are linked inside `SensorBioSDK.xcframework` with their symbols hidden, so they cannot collide with a gRPC your app links for its own reasons. If you use Firebase/Firestore, this fixes an EXC_BAD_ACCESS a few seconds after launch on the first Firestore request. Remove any gRPC pod you added to work around it — there is nothing left to reconcile.
- **`s.libraries = 'c++', 'z'`** is now declared by the podspec. gRPC-Core used to supply these transitively; nothing did once it left.
- **`sensorBio.sdkVersion` works.** It returned `"UNKNOWN"` in every previous binary release — it read a bundled resource that a statically linked framework never receives. It is compiled in now.
- **New: detected-activity API** — `detectedActivitiesPublisher`, `detectedActivities()`, `confirmDetectedActivity(startTsMillis:activityName:)`, `dismissDetectedActivity(startTsMillis:)`. Detected activities are stored and offered rather than auto-uploaded.
- **New: `SB_SDK.sdkTokenProvider`** — the SDK asks your backend for a single-use registration token instead of holding your SDK Key. See § 4.2 of `SDK_INTERFACE.md`.
- **Breaking:** `SB_SDKKeyCredentials.sdk_token` is now your organization **SDK Key**, exchanged for a single-use token at registration — not a server-issued token. An integration passing the previously documented value will stop working.
- Raw sync no longer pulls on a trickle of queued packets; packet-upload drain hardened; the processed sync is the only upload trigger.

### v0.4.0 — May 22, 2026

- SDK now owns biometric, meditation, and activity recording orchestration end-to-end — host app awaits one async call (`recordDetailedBiometrics`, `recordMeditation`, `recordActivity`) and the SDK manages BLE start/stop, the timer, post-stop sync, session build, and submission.
- In-flight recordings persist across app kill and resume (or auto-finalize) on relaunch. New surface: `activeRecording`, `awaitActiveRecordingCompletion()`, `cancelCurrentRecording()`. See `SDK_INTERFACE.md` §5.3.
- **Breaking:** public-surface rename `spotCheck*` → `biometricRecord*` (`recordSpotCheck` → `recordDetailedBiometrics`, `SB_SpotCheck*` types → `SB_BiometricRecord*`). Update call sites.
- One-shot migration of legacy host-app UserDefaults + Keychain on first SDK launch — signed-in users and paired devices survive the upgrade from older host-app builds where these were app-side.
- SensrV1 hardware now appears in pair-scan results alongside V2 / V2.5 / V3.
- Stable cache keys for sleep-detail and dashboard endpoints (eliminates spurious cache misses).

## Support

For integration help, contact support@sensorbio.com.
