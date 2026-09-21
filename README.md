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

Both are iOS-only. Each ships a device slice (arm64) and a fat simulator
slice (arm64 + x86_64), so they run on Apple-silicon and Intel simulators
alike — including hosted simulator services such as Appetize. They cannot run
on macOS.

> Releases **3.0.0 through 3.2.0** shipped an arm64-only simulator slice.
> Building those for an x86_64 simulator fails with `unsupported Swift
> architecture`. Use 3.2.1 or later.

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

choose **Exact Version** `3.2.1`, and add the `SensorBioSDK` library to your app target.

Or, if your app is itself a Swift package:

```swift
dependencies: [
    .package(
        url: "https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary.git",
        exact: "3.2.1"
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

### v3.2.1 — September 21, 2026

Packaging only. No API change and no behaviour change — if 3.2.0 builds and runs
for you, 3.2.1 is a drop-in replacement. It fixes two defects present in every
3.x release:

- **App Store and TestFlight uploads are no longer rejected.**
  `SensorBioSDK.framework` shipped without `CFBundleShortVersionString` in its
  `Info.plist`, so App Store Connect refused the whole IPA with
  **ITMS-90057 — "missing bundle version"**, naming our framework inside your
  app's `Frameworks/` directory. This blocked App Store submission as well as
  TestFlight, and there was no fix on your side short of repackaging our binary.
  The framework now carries both `CFBundleShortVersionString` and
  `CFBundleVersion`.
- **The simulator slice is now fat (arm64 + x86_64).** It was arm64-only, so
  building for an Intel simulator failed with
  `unsupported Swift architecture` in `SensorBioSDK-Swift.h` while emitting the
  module. This affected Intel Macs and, more commonly, hosted simulator services
  such as **Appetize** used for demos and review builds. Sleep staging is fully
  present on x86_64 — nothing is stubbed out — though a simulator still has no
  Bluetooth, so it cannot sync a wearable.

Both are now verified against the built artifact on every release, so neither can
regress silently.

### v3.2.0 — September 20, 2026

- **Brief surveys can now be submitted without waiting on the network, and without
  being lost if the recording hasn't reached the server yet.** `queueBriefSurvey(_:)`
  writes the answers to the SDK's own store and returns immediately, so your survey
  sheet can dismiss the moment the user taps Submit — there is nothing to await and
  no spinner to gate. The SDK then sends it once the recording it belongs to is known
  to have landed. This closes a real hole: a survey sent before its recording arrives
  has nothing to attach to, and the server accepts it, returns an empty id, and the
  answers are orphaned with nothing on screen to say so.
- **A queued survey shows up in your UI before it is sent.** Every read that returns
  a survey — `fetchWorkoutDetail`, `fetchMeditationGraph`, `fetchSleepDetail`,
  `sleepDetailUpdates`, `localWorkoutDetail`, `localMeditationGraph` — merges in what
  this device holds, with a not-yet-sent answer taking precedence over the server's
  copy until it lands. So there is nothing to stamp onto your model and nothing to
  refetch after a submit.
- **Editing a survey twice no longer risks a duplicate.** The stored row keeps the
  server's id across a screen teardown and a relaunch, so a second answer updates the
  existing survey instead of creating a new one.
- **`dismissBriefSurvey(type:timestampMillis:)` and
  `briefSurveyWasHandled(timestampMillis:)` record "asked and skipped"** so you don't
  re-offer a survey the user declined. Keep this out of your own `UserDefaults` — these
  rows are cleared on sign-out along with everything else, which a defaults key is not.
- **New `SB_SurveyError.notLinked`** distinguishes "the server accepted the call but
  attached the survey to nothing" from a transport failure. It is not a lost survey;
  the SDK re-sends once the record is confirmed. Don't stamp the empty id onto your model.
- **`submitBriefSurvey(_:)` is unchanged and still works**, but is now the discouraged
  path — it sends immediately with no gate and no local record, so it has the orphaning
  race described above. Prefer `queueBriefSurvey(_:)` unless the survey has no recording
  to wait on.
- **White-label settings survive a cold, offline launch.** The last fetched snapshot is
  persisted and restored during SDK init, so a signed-in user's install publishes its
  real settings from launch instead of falling back to the stock defaults. Settings are
  `nil` only on a fresh install or after sign-out.
- **A sleep the server has permanently rejected is no longer retried forever.** A
  rejection that will never succeed is now recognised as final instead of being requeued
  on every sync.
- **Sleep processing no longer over-fetches.** The Philips/FXC fetch is bounded to the
  sleep actually being processed rather than pulling an unbounded window.

### v3.1.1 — September 14, 2026

- **Heart rate is taken from the band's own heart-rate channel rather than derived from
  beat-to-beat intervals.** The derived figure could disagree with what the band itself
  reported; they now agree because there is only one source.
- Repins the bundled BLE SDK to v9.1.115 and guards against a missing resource bundle.

### v3.1.0 — September 14, 2026

- **Fixes account creation and password reset on a fresh install.** Checking
  whether an e-mail is available, requesting a password reset and completing
  one were all being sent down the authenticated path, so on a device with no
  stored session they were refused before they left the app: an activation code
  would verify and then the e-mail step failed immediately. Which calls need a
  session is now taken from the server's own list, so a call cannot be
  misclassified. If your app implements its own sign-up or forgot-password
  screens, they work again with no change on your side.
- **`reauthenticationRequired` is only sent when there was a session to lose.**
  It previously fired on any authenticated call made without a credential,
  including before the user had ever signed in — so a host that turns the event
  into a sign-out could sign out an account that was never signed in, during
  sign-up. The call itself still throws `SB_AuthError.missingAuthToken`
  whenever a credential is missing; only the event narrowed.
- **A data store that cannot be opened no longer deletes your user's history or
  crashes at launch.** A relaunch before the device's first unlock after a
  reboot cannot read the store files; the SDK used to delete and rebuild, then
  trap when the rebuild failed too. Deleting is now limited to genuine schema
  incompatibilities. Any other failure runs that one launch on an in-memory
  store and reopens the real one next launch, and band data is not acknowledged
  while the store is temporary, so nothing is lost.

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
