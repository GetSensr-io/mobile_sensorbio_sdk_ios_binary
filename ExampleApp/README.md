# ExampleApp

Reference SwiftUI integration of `SensorBioSDK` consumed as a binary CocoaPod from the umbrella podspec at the repo root (`../SensorBioSDK.podspec`).

This is what you'd build in your own app, modulo the UI. The pieces that matter:

- **`project.yml`** — xcodegen spec. iOS 18 deployment target, `CLANG_CXX_LANGUAGE_STANDARD = c++17`, `FX_PLATFORM_UNIX=1` preprocessor define.
- **`Podfile`** — single `pod 'SensorBioSDK', :path => '..'` line that vendors the 3 xcframeworks and transitively brings the third-party pods. (Customer apps use `:git`/`:tag` instead of `:path` — see `../README.md`.)
- **`ExampleApp/Info.plist`** — BLE permission strings + `bluetooth-central` background mode.
- **`ExampleApp/SDKExampleApp.swift`** — `@main` entry point: sets `SB_SDK.environment` (Staging/Prod, persisted via `UserDefaults`) on init, installs `SB_SDK.sdkTokenProvider` so the SDK can ask for a single-use token whenever it needs one, and routes the SDK's `SB_SDK.log` Combine stream to `os.Logger`.
- **`ExampleApp/SDKTokenExchange.swift`** — the `POST /sdk/v1/token` exchange that turns your organization SDK Key into a single-use `sdk_token`, plus the `sdkTokenProvider` closure the SDK pulls when a session needs rebuilding. In a real integration this belongs on **your backend**: the SDK Key is long-lived and org-wide and must never reach a device. The example does it in-app, clearly marked, only so it can demonstrate the flow without a backend to ask — read the file's header before copying any of it.
- **`ExampleApp/RegisterView.swift`** / **`RegisterFormState.swift`** — the `registerUser(userId:sdkToken:)` flow: register-or-login on a single-use SDK token, which is how a customer integration bootstraps a user. The org id comes back from the token exchange, so nothing has to be typed but the key and your own user id. There is no email/password path in the SDK's customer surface.

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
