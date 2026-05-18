# mobile_sensorbio_sdk_ios_binary

Binary (XCFramework) distribution of [`mobile_sensorbio_sdk_ios`](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios) — the Sensor Bio iOS SDK. Each tagged release wraps a specific source version as a set of precompiled `.xcframework`s, fronted by a single `.binaryTarget`-based `Package.swift` product.

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

See [`scripts/build-xcframework.sh`](https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios/blob/main/scripts/build-xcframework.sh) in the source repo. End-to-end, a new release is:

1. Tag the source repo (`mobile_sensorbio_sdk_ios`) at the new version, e.g. `v0.1.1`.
2. Run `scripts/build-xcframework.sh` from the source repo. The script produces five `.xcframework`s in `build/output/`.
3. Zip each `.xcframework`, compute its SHA-256, upload all five zips to a new GitHub Release here.
4. Update [`Package.swift`](Package.swift) with the new tag's `releaseTag` constant + the five new checksums; commit + push; tag this repo at the matching version.

A driver `scripts/release.sh` on the source repo that automates steps 2–4 is planned for Phase 6.15d of the library extraction roadmap.
