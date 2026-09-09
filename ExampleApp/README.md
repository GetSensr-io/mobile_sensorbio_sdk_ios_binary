# ExampleApp

Reference SwiftUI integration of `SensorBioSDK` consumed as a binary CocoaPod from the umbrella podspec at the repo root (`../SensorBioSDK.podspec`).

This is what you'd build in your own app, modulo the UI. The pieces that matter:

- **`project.yml`** — xcodegen spec. iOS 18 deployment target, `CLANG_CXX_LANGUAGE_STANDARD = c++17`, `FX_PLATFORM_UNIX=1` preprocessor define.
- **`Podfile`** — single `pod 'SensorBioSDK', :path => '..'` line that vendors the 3 xcframeworks and transitively brings the third-party pods. (Customer apps use `:git`/`:tag` instead of `:path` — see `../README.md`.)
- **`ExampleApp/Info.plist`** — BLE permission strings + `bluetooth-central` background mode.
- **`ExampleApp/SDKExampleApp.swift`** — `@main` entry point: sets `SB_SDK.environment` (Staging/Prod, persisted via `UserDefaults`) on init and routes the SDK's `SB_SDK.log` Combine stream to `os.Logger`.
- **`ExampleApp/RegisterView.swift`** / **`RegisterFormState.swift`** — the `registerUser(userId:…)` flow: the SDK-key-gated, register-or-login entry point that is how a customer integration bootstraps a user. There is no email/password path in the SDK's customer surface.

Everything in this app is built against the SDK's **public** surface only — no internal or SPI-gated API — so it compiles against exactly what the shipped xcframeworks expose.

## Building

```bash
# From this directory:
xcodegen generate     # produces ExampleApp.xcodeproj (or use the committed one)
pod install           # produces ExampleApp.xcworkspace + Pods/
open ExampleApp.xcworkspace
```

Then build + run on a connected iPhone (iOS 18+). Bluetooth + signing have to be configured for the device.

## Common pitfalls

- **Opening `.xcodeproj` instead of `.xcworkspace`** — Xcode builds without the pods and you get "no such module 'SensorBioSDK'". Always open the workspace.
- **Skipping `pod install` after pulling new xcframeworks** — CocoaPods caches per-podspec metadata; `pod install` re-hashes the vendored xcframeworks.
- **Building on an Intel-Mac simulator** — won't work. LibFXC has no x86_64 slice; the SDK is iOS device + arm64-sim only.
