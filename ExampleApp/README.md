# ExampleApp

Reference SwiftUI integration of `SensorBioSDK`, consuming the Swift Package at
the repo root.

This is what you'd build in your own app, modulo the UI. The pieces that matter:

- **`project.yml`** — xcodegen spec. iOS 18 deployment target, the
  `SensorBioSDK` package dependency, and the `FX_PLATFORM_UNIX=1` preprocessor
  define. Note what is *absent*: no build-settings block, and no other
  packages. The SDK brings everything it needs and declares nothing you have
  to resolve.
- **`ExampleApp/Info.plist`** — BLE permission strings + `bluetooth-central`
  background mode.
- **`ExampleApp/SDKExampleApp.swift`** — `@main` entry point: sets
  `SB_SDK.environment` (Staging/Prod, persisted via `UserDefaults`) on init,
  installs `SB_SDK.sdkTokenProvider` so the SDK can ask for a single-use token
  whenever it needs one, restores `SB_SDK.sdkKeyCredentials` for a hydrated
  session, and routes the SDK's `SB_SDK.log` Combine stream to `os.Logger`.
- **`ExampleApp/SDKTokenExchange.swift`** — the `POST /sdk/v1/token` exchange
  that turns your organization SDK Key into a single-use `sdk_token`, plus the
  `sdkTokenProvider` closure the SDK pulls when a session needs rebuilding.
  **In a real integration this belongs on your backend**: the SDK Key is
  long-lived and org-wide and should not be compiled into an app. The example
  does it in-app, in this one clearly-marked file, only so it can demonstrate
  the flow without a backend to ask — read the file's header before copying
  any of it.
- **`ExampleApp/RegisterView.swift`** / **`RegisterFormState.swift`** — the
  `registerUser(userId:sdkToken:)` flow: register-or-login on a single-use SDK
  token, which is how a customer integration bootstraps a user. The org id
  comes back from the token exchange, so nothing has to be typed but the key
  and your own user id. There is no email/password path in the SDK's customer
  surface.

Everything in this app is built against the SDK's **public** surface only — no
internal or SPI-gated API — so it compiles against exactly what the shipped
xcframeworks expose.

## Building

```bash
# From this directory:
xcodegen generate     # produces ExampleApp.xcodeproj (or use the committed one)
open ExampleApp.xcodeproj
```

Then build and run on a connected iPhone (iOS 18+). Bluetooth and signing have
to be configured for the device. Xcode resolves the package on first open;
there is no workspace and nothing to install.

## Common pitfalls

- **Building on an Intel-Mac simulator** — won't work. LibFXC has no x86_64
  slice; the SDK is iOS device + arm64-sim only.
- **Reusing an SDK token** — tokens are single use and expire in minutes. A
  spent one fails inside `registerUser` as an authentication error, far from
  its cause. Mint a fresh one per call.
- **Adding a package to fix a missing symbol** — the SDK contains its
  dependencies privately; adding your own copy is more likely to break the
  build than fix it. Contact support@sensorbio.com instead.
