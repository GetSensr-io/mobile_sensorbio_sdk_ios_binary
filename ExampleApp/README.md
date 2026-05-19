# ExampleApp

Reference SwiftUI integration of `SensorBioSDK` consumed as a binary CocoaPod from `../SensorBio/SensorBioSDK.podspec`.

This is what you'd build in your own app, modulo the UI. The pieces that matter:

- **`project.yml`** — xcodegen spec. iOS 18 deployment target, Swift 6.1, `CLANG_CXX_LANGUAGE_STANDARD = c++17`, `FX_PLATFORM_UNIX=1` preprocessor define.
- **`Podfile`** — single `pod 'SensorBioSDK', :podspec => '../SensorBio/SensorBioSDK.podspec'` line that vendors the 3 xcframeworks and transitively brings the third-party pods.
- **`ExampleApp/Info.plist`** — BLE permission strings + `bluetooth-central` background mode.
- **`ExampleApp/ExampleAppApp.swift`** — `@main` with the required init pattern: `SensorBioSDK.environment` → `bootstrapKeychain()` → `runDefaultsMigratorIfNeeded()` → `registerBGTasks()`.
- **`ExampleApp/ContentView.swift`** — minimal sign-in form; exercises the `signIn` RPC path through gRPC-Core.

## Building

```bash
# From this directory:
xcodegen generate     # produces ExampleApp.xcodeproj
pod install           # produces ExampleApp.xcworkspace + Pods/
open ExampleApp.xcworkspace
```

Then build + run on a connected iPhone (iOS 18+). Bluetooth + signing have to be configured for the device.

## Common pitfalls

- **Opening `.xcodeproj` instead of `.xcworkspace`** — Xcode builds without the pods and you get "no such module 'SensorBioSDK'". Always open the workspace.
- **Skipping `pod install` after pulling new xcframeworks** — CocoaPods caches per-podspec metadata; `pod install` re-hashes the vendored xcframeworks.
- **Building on an Intel-Mac simulator** — won't work. LibFXC has no x86_64 slice; the SDK is iOS device + arm64-sim only.
