# mobile_sensorbio_sdk_ios_binary

Binary (XCFramework) distribution of [`mobile_sensorbio_sdk_ios`](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios) — the Sensor Bio iOS SDK. Each tagged release wraps a specific source version as a set of precompiled `.xcframework`s, fronted by a single `.binaryTarget`-based `Package.swift` product.

- **[SDK_INTERFACE.md](SDK_INTERFACE.md)** — customer-facing API reference. Every public symbol available to your app today, tier-marked (✅ Supported / 🚧 WIP) so you know what's ready to build production code against.
- **[`Examples/SDKExample/`](Examples/SDKExample/)** — reference consumer that exercises the customer-facing surface end-to-end (account creation → sign in → pair device → BLE connect → sync packets → dashboard / activity / sleep reads). Open `SDKExample.xcodeproj` in Xcode and run on a device; SPM resolves this same repo at the version you check out.

## Consumption

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [.iOS(.v18)],
    dependencies: [
        .package(
            url: "https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary.git",
            from: "0.1.0"
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
)
```

Then in Swift:

```swift
import SensorBioSDK

SB_SDK.environment = .staging
let version = SB_SDK.shared.sdkVersion
```

The single `SensorBioSDK` product transitively pulls in the BT SDK + eight public Swift packages (SwiftProtobuf, grpc-swift-2, grpc-swift-protobuf, grpc-swift-nio-transport, SwiftKeychainWrapper, KeychainAccess, SwiftQueue, CocoaMQTT). You don't need to declare any of those yourself.

## Versioning

Binary release tags mirror the source repo's tags exactly — `v0.1.0` here wraps `v0.1.0` in [`mobile_sensorbio_sdk_ios`](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios). To find out which source commit a binary release contains, look up the same tag in the source repo.

## Platform support

- iOS 18.0+ (device `arm64`, simulator `arm64` + `x86_64`)

## What's inside

The umbrella `SensorBioSDK` product is one Swift-only wrapper target plus five `.binaryTarget`s:

- `SensorBioSDK.xcframework` — public API surface
- `SensrProtos.xcframework` — generated protobuf + gRPC client types
- `BioedgeAPI.xcframework` — proprietary C engine code
- `FXCBridge.xcframework` — umbrella over LibFXC's C headers
- `LibFXC.xcframework` — Philips's prebuilt binary, passed through

Customers only `import SensorBioSDK`; the other four modules are linked but considered SDK internals.

## Building a new release

One command from the source repo: `./scripts/release.sh vX.Y.Z`. Validates the version arg against `Resources/SDKVersion.plist`, validates both repos clean + on `main` + in sync with `origin`, builds the five xcframeworks (`scripts/build-xcframework.sh`), zips + checksums them, rewrites this repo's `Package.swift` with the new `releaseTag` constant + checksums, commits + pushes the binary repo, tags both repos, and creates the GitHub Release with the five zips attached. Idempotent / resumable — re-running after a partial failure picks up where it left off.
