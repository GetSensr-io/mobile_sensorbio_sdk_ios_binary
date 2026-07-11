# NoomApp

Reference SwiftUI integration of `SensorBioSDK` consumed as a binary CocoaPod from the umbrella podspec at the repo root (`../SensorBioSDK.podspec`).

This is what you'd build in your own app, modulo the UI. The pieces that matter:

- **`project.yml`** — xcodegen spec. iOS 18 deployment target, Swift 6.1, `CLANG_CXX_LANGUAGE_STANDARD = c++17`, `FX_PLATFORM_UNIX=1` preprocessor define.
- **`Podfile`** — single `pod 'SensorBioSDK', :path => '..'` line that vendors the 3 xcframeworks and transitively brings the third-party pods. (Customer apps use `:git`/`:tag` instead of `:path` — see `../README.md`.)
- **`NoomApp/Info.plist`** — BLE permission strings + `bluetooth-central` background mode. The SDK keeps the BLE connection alive and completes uploads from sync completion; no `BGTaskScheduler` registration is required.
- **`NoomApp/NoomApp.swift`** — `@main` entry point that chooses the SDK environment, hydrates the session, and routes SDK logs to `os.Logger`.
- **`NoomApp/ContentView.swift`** — NoomPlus authentication and app routing built on the public SDK surface.

## Building

```bash
# From this directory:
xcodegen generate     # produces NoomApp.xcodeproj
pod install           # produces NoomApp.xcworkspace + Pods/
open NoomApp.xcworkspace
```

Then build + run on a connected iPhone (iOS 18+). Bluetooth + signing have to be configured for the device.

## Common pitfalls

- **Opening `.xcodeproj` instead of `.xcworkspace`** — Xcode builds without the pods and you get "no such module 'SensorBioSDK'". Always open the workspace.
- **Skipping `pod install` after pulling new xcframeworks** — CocoaPods caches per-podspec metadata; `pod install` re-hashes the vendored xcframeworks.
- **Building on an Intel-Mac simulator** — won't work. LibFXC has no x86_64 slice; the SDK is iOS device + arm64-sim only.
