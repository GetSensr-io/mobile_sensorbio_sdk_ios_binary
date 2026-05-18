// swift-tools-version: 6.1
import PackageDescription

let releaseTag = "v0.1.3"
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
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/lucas34/SwiftQueue.git", from: "6.0.2"),
        .package(url: "https://github.com/emqx/CocoaMQTT", from: "2.2.4")
    ],
    targets: [
        .binaryTarget(
            name: "SensorBioSDK",
            url: "\(releaseURL)/SensorBioSDK.xcframework.zip",
            checksum: "faea54917285f84234d87bca1d39caf839358ffdbe3086a81e9ab3b3110f51d2"
        ),
        .binaryTarget(
            name: "SensrProtos",
            url: "\(releaseURL)/SensrProtos.xcframework.zip",
            checksum: "10b20e0b7675e68d5221115118fa6315fdc053ab7f861d1b2bc0008333758195"
        ),
        .binaryTarget(
            name: "BioedgeAPI",
            url: "\(releaseURL)/BioedgeAPI.xcframework.zip",
            checksum: "d8f79c4d01576189a3f503c8dae475570268eb7a98e433a0246ba3e58b7f392e"
        ),
        .binaryTarget(
            name: "FXCBridge",
            url: "\(releaseURL)/FXCBridge.xcframework.zip",
            checksum: "352e18162fb8e73274bba01b12391e30680575985cf30025aef1a4755a3e500d"
        ),
        .binaryTarget(
            name: "LibFXC",
            url: "\(releaseURL)/LibFXC.xcframework.zip",
            checksum: "4a21f0c93b403c51b45606a2de8da1fa7fa46ec888b633c7e0ac428c144ac0cf"
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
