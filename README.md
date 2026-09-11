# SensorBioSDK — Binary Distribution

Customer-facing binary distribution of the Sensr-Bio iOS SDK. This repository contains:

- **`Package.swift`** — the Swift Package you add to your app
- **`SDK_INTERFACE.md`** — the public API reference
- **`ExampleApp/`** — a reference SwiftUI integration you can build and run

## What ships

The frameworks are **attached to each GitHub release**, not stored in this
repository. Xcode downloads them on first resolve and verifies them against
the checksums in `Package.swift`; you do not fetch them yourself.

| Artifact | Contents |
|---|---|
| `SensorBioSDK.xcframework` | The SDK. Auth, dashboard / sleep / activity / biometric reads, recording orchestration, the upload pipeline, the BLE pairing and sync engine, and the on-device DSP (HRV / sleep / activity computation). |
| `LibFXC.xcframework` | Philips proprietary FXC sleep-staging engine. Linked transitively — you never call into it. |

Both are iOS-only (device + arm64 simulator). They cannot run on macOS or on
Intel Mac simulators.

`import SensorBioSDK` is the only import your app needs.

## Requirements

- **Xcode 16.3+** (Swift 6.1 toolchain)
- **iOS 18+** deployment target
- **Bluetooth + Background Modes capabilities**, so the SDK can stay connected to the wearable and finish syncs while your app is backgrounded

## Integrating into your app

### 1. Add the package

In Xcode: **File → Add Package Dependencies…**, enter

```
https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary.git
```

choose **Exact Version** `3.0.1`, and add the `SensorBioSDK` library to your app target.

Or, if your app is itself a Swift package:

```swift
dependencies: [
    .package(
        url: "https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary.git",
        exact: "3.0.1"
    )
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SensorBioSDK", package: "mobile_sensorbio_sdk_ios_binary")
        ]
    )
]
```

That is the whole integration. There is no build-settings block to copy, no
`post_install` hook, and nothing to add to a `Podfile`.

### 2. There are no other dependencies to add

The SDK declares **no third-party packages**, and it does not need you to
declare any either. Everything it uses is compiled inside
`SensorBioSDK.xcframework`.

This is worth stating plainly because it is the opposite of the usual advice:
if a symbol appears to be missing, **do not add a package to satisfy it** — a
second copy of a library the SDK already contains is far more likely to break
your build than to fix it. Tell us instead: support@sensorbio.com.

The SDK coexists with anything else in your app, including apps that use
Firebase or Firestore.

### 3. Configure it at launch

```swift
import SwiftUI
import SensorBioSDK

@main
struct YourApp: App {
    init() {
        SB_SDK.environment = .production
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 4. Register a user

Registration needs one endpoint on **your own server**. Your organization's
SDK Key (`sbsk_…`) is long-lived and org-wide — whoever holds it can mint
tokens for any of your users — so your server keeps it and exchanges it for a
single-use `sdk_token` (`sbst_…`) worth one register-or-login, for one user,
for a few minutes.

Your server calls `POST /sdk/v1/token` with `Authorization: SDKKey sbsk_…` and
returns the `sdk_token` and `organization_id`. Your app passes both straight to
the SDK and registers:

```swift
let minted = try await YourBackend.fetchSensorBioToken()

SB_SDK.sdkCredentials = SB_SDKCredentials(
    organizationId: minted.organizationId,
    sdkToken: minted.sdkToken
)

let outcome = try await sensorBio.registerUser(userId: yourUserId)
```

That is the whole flow. **The SDK Key never reaches the device**, and there is
nothing else to configure — no separate org credential, no build settings, and
nothing to re-supply at launch. The organization id is remembered for you, so
an app relaunching into a restored session sets nothing.

`registerUser` also takes optional demographics and an activation code
(`birthday:`, `sex:`, `heightCm:`, `weightKg:`, `imperialUnits:`,
`activationCode:`). The first call for a given `userId` registers; later calls
log the same user back in.

Tokens are single use and expire in minutes. Get a fresh one per registration
and never cache one — the SDK clears `sdkCredentials` as it spends the token,
so a replay cannot happen by accident.

**[`SDK_INTERFACE.md` §5](./SDK_INTERFACE.md)** is the guide for whoever builds
that endpoint: the exchange contract, reference implementations, the error
table, and key rotation.

#### When a session ends

If a session dies beyond recovery — its refresh token expired after 60 days of
inactivity, or the SDK Key it was signed under was revoked — the SDK surfaces
`SB_AuthError.refreshTokenExpired`. Treat it as a sign-out: fetch fresh
credentials, set `sdkCredentials`, and call `registerUser` again with the same
`userId`. It logs the same user back into the same data.

The SDK deliberately does not do this behind your back. Rebuilding a session
needs a freshly minted token, the SDK cannot mint one, and holding on to
something that could is what used to put the organization key on devices.

### 5. Use the SDK

The entry point is the top-level `sensorBio` accessor (the singleton
`SB_SDK.shared`):

```swift
let dashboard = try await sensorBio.fetchDashboardData(
    date: Date(),
    tzOffset: Int32(TimeZone.current.secondsFromGMT() / 60)
)
```

See **[`SDK_INTERFACE.md`](./SDK_INTERFACE.md)** for the full public surface.

## Reference integration

**[`ExampleApp/`](./ExampleApp)** is a minimal SwiftUI app demonstrating the
whole pattern end to end. Open `ExampleApp.xcodeproj` and run it on a device.

It stands in for your backend in one file,
[`SDKTokenExchange.swift`](./ExampleApp/ExampleApp/SDKTokenExchange.swift),
which performs the SDK-Key → SDK-token exchange in the app so the example can
run without a server. **That file is the one part of the example you should
not copy** — its header explains why, and it is deliberately isolated so the
rest of the app shows the shape your app should actually have.

## Updating

1. In Xcode, **File → Packages → Update to Latest Package Versions**, or raise
   the pinned version in your `Package.swift`.
2. Rebuild.

`SDK_INTERFACE.md` documents breaking changes per release.

## Release notes

### v3.0.1 — September 11, 2026

- **Fixes duplicate-symbol link errors if your app also links SwiftProtobuf,
  gRPC, SwiftNIO or BoringSSL.** 3.0.0 left every symbol of the libraries
  compiled inside the framework visible to your linker, so it saw two copies of
  each and refused to link — thousands of errors. Those symbols are now hidden;
  the SDK still uses them internally. Nothing changes in your code or your
  package declaration.
- **`SensorBioSDK.xcframework` is a dynamic framework again** rather than a
  static one, which is what makes hiding the symbols possible. Xcode embeds and
  signs it for you; there is nothing to configure.
- **The download is roughly a third of the size** — 69 MB unzipped, down from
  215 MB.
- If you worked around the 3.0.0 link errors by forcing the framework dynamic
  yourself, remove that workaround. It caused
  `JSONEncodingError.missingFieldNames` at runtime and is no longer needed.
- You may still see `objc: Class _TtC13SwiftProtobuf… is implemented in both`
  warnings in the console if your app links SwiftProtobuf too. They are
  expected and harmless: Objective-C registers classes by name regardless of
  symbol visibility, and no SDK API exposes those types, so the two copies
  never exchange objects.

### v3.0.0

- **Integration moves from CocoaPods to Swift Package Manager.** This is the
  breaking change in this release; the Swift API is unchanged. Remove the
  `pod 'SensorBioSDK'` line and its `post_install` block, and add the package
  as described above.
- **The SDK no longer brings any third-party dependencies into your project.**
  It previously required SwiftProtobuf, SwiftKeychainWrapper, KeychainAccess,
  SwiftQueue and CocoaMQTT to be resolved alongside it. All of them are now
  compiled inside the framework, along with its gRPC stack.
- **Fixes a crash for apps that use Firebase or Firestore.** Two gRPC
  implementations in one process could bind to each other's internals, and the
  app would die within seconds of the first Firestore request. The SDK now
  carries its own transport privately, so there is nothing left to collide.
- **Two xcframeworks instead of three.** `SensorBioBTSDK.xcframework` is now
  linked inside `SensorBioSDK.xcframework`; delete your copy of it.
- **The organization SDK Key no longer goes on the device.** `registerUser`
  authenticated with a single-use token, but every call *after* it presented
  the raw key, so apps had to hold one — which defeated the token exchange.
  Authenticated calls now use the session's own access token.
  `SB_SDKKeyCredentials` and `SB_SDK.sdkKeyCredentials` are removed; set
  `SB_SDK.sdkCredentials` with the `organization_id` and `sdk_token` your
  exchange returns, and call `registerUser(userId:)`.
- `sensorBio.sdkVersion` reports the real version. It previously returned
  `"UNKNOWN"` in every customer app.

## Support

For integration help, contact support@sensorbio.com.
