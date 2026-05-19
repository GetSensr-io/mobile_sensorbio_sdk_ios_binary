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
| `SensorBio/SensorBioSDK.podspec` | — | Umbrella binary podspec — vendors the three xcframeworks above and declares the third-party CocoaPods that have to come from CocoaPods trunk. |

All three xcframeworks are iOS-only (device + arm64 simulator). They cannot run on macOS or Intel Mac simulators.

## Requirements

- **Xcode 16.3+** (Swift 6.1 toolchain)
- **iOS 18+** deployment target
- **CocoaPods 1.16+** — `sudo gem install cocoapods` or `brew install cocoapods`

## Integrating into your app

### 1. Copy the `SensorBio/` directory into your project root

Place it at the same level as your `.xcodeproj` / `.xcworkspace`. Don't drag the xcframeworks into Xcode manually — CocoaPods will wire them up.

```
your-app/
├── YourApp.xcodeproj
├── YourApp.xcworkspace      ← if you already use CocoaPods
├── Podfile                  ← may already exist
└── SensorBio/               ← <-- drop here, contents as-shipped
    ├── SensorBioSDK.xcframework/
    ├── SensorBioBTSDK.xcframework/
    ├── LibFXC.xcframework/
    └── SensorBioSDK.podspec
```

### 2. Add SensorBioSDK to your `Podfile`

If your `Podfile` doesn't exist yet, create one. The minimum looks like:

```ruby
platform :ios, '18.0'

target 'YourApp' do
  use_frameworks!

  pod 'SensorBioSDK', :podspec => './SensorBio/SensorBioSDK.podspec'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Required: SensorBioSDK is iOS 18+; transitive pods default lower
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']   = '18.0'
      # Required: abseil (pulled in transitively by gRPC-Core) needs C++17
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
      config.build_settings['CLANG_CXX_LIBRARY']           = 'libc++'
    end
  end
end
```

The single `pod 'SensorBioSDK'` line transitively brings:

- The 3 SensorBio xcframeworks (via `vendored_frameworks`)
- `gRPC-ProtoRPC` (which transitively brings gRPC-Core + abseil + BoringSSL-GRPC + the ObjC Protobuf runtime)
- `SwiftProtobuf` (Swift wire-type runtime)
- `SwiftKeychainWrapper` + `KeychainAccess` (keychain helpers)
- `SwiftQueue` (persistent job-queue runtime)
- `CocoaMQTT` (MQTT client for the license-key broker)

### 3. Run `pod install`

```bash
pod install
```

Open `YourApp.xcworkspace` (not `.xcodeproj`) in Xcode going forward.

### 4. Use the SDK

The customer-facing entry point is a top-level `sensorBio` accessor (the singleton `SensorBioSDK.shared`).

```swift
import SensorBioSDK

@main
struct YourApp: App {
    init() {
        SensorBioSDK.environment = .production
        SensorBioSDK.bootstrapKeychain()
        SensorBioSDK.runDefaultsMigratorIfNeeded()
        SensorBioSDK.registerBGTasks()
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

## Support

For integration help, contact engineering@sensr.ai.
