// swift-tools-version: 6.1
import PackageDescription

let releaseTag = "v0.1.0"
let releaseURL = "https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary/releases/download/\(releaseTag)"

let package = Package(
    name: "SensorBioSDK",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        // Single umbrella product the customer references. The `_SensorBioSDKLink`
        // wrapper target re-exports SensorBioSDK and lists every transitive SPM
        // dep so the customer's Package.swift only needs to declare one product.
        .library(name: "SensorBioSDK", targets: ["_SensorBioSDKLink"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.37.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.3.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.7.0"),
        .package(url: "https://github.com/GetSensr-io/mobile_bluetooth_sdk_ios_binary.git", from: "7.0.109"),
        .package(url: "https://github.com/jrendel/SwiftKeychainWrapper", from: "4.0.1"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", branch: "master"),
        .package(url: "https://github.com/lucas34/SwiftQueue.git", from: "6.0.2"),
        .package(url: "https://github.com/emqx/CocoaMQTT", from: "2.2.4")
    ],
    targets: [
        .binaryTarget(
            name: "SensorBioSDK",
            url: "\(releaseURL)/SensorBioSDK.xcframework.zip",
            checksum: "ad1e91e00dc8ca4487a70dbb4c3112c3e2b73f08e43d8ce7cc29d109b46ac4be"
        ),
        .binaryTarget(
            name: "SensrProtos",
            url: "\(releaseURL)/SensrProtos.xcframework.zip",
            checksum: "0b6fc87309c332e8c40a71e83ca89036782bfd5717fd790e758dbb2fa9a9cb44"
        ),
        .binaryTarget(
            name: "BioedgeAPI",
            url: "\(releaseURL)/BioedgeAPI.xcframework.zip",
            checksum: "ed82b07917cd2c5342792743676202dd94c7a2f68c75ea658fb08df366fa6e1d"
        ),
        .binaryTarget(
            name: "FXCBridge",
            url: "\(releaseURL)/FXCBridge.xcframework.zip",
            checksum: "e52bc54753f3e577206d2cd9fc234ec68647a16b09dc2962c1aa9523c49000e7"
        ),
        .binaryTarget(
            name: "LibFXC",
            url: "\(releaseURL)/LibFXC.xcframework.zip",
            checksum: "bd72768ea7c3684134dcfedd9ad2793114b645464eae8423b2933fa8a4b4ae3c"
        ),
        .target(
            name: "_SensorBioSDKLink",
            dependencies: [
                "SensorBioSDK",
                "SensrProtos",
                "BioedgeAPI",
                "FXCBridge",
                "LibFXC",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "SensorBioBTSDK", package: "mobile_bluetooth_sdk_ios_binary"),
                .product(name: "SwiftKeychainWrapper", package: "SwiftKeychainWrapper"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "SwiftQueue", package: "SwiftQueue"),
                .product(name: "CocoaMQTT", package: "CocoaMQTT")
            ],
            path: "Sources/_SensorBioSDKLink"
        )
    ]
)
