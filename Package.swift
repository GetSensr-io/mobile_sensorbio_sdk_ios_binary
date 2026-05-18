// swift-tools-version: 6.1
import PackageDescription

let releaseTag = "v0.1.2"
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
            checksum: "721eb28c18129e028a2469614a793618d38824ff968837464379bbc99d77df11"
        ),
        .binaryTarget(
            name: "SensrProtos",
            url: "\(releaseURL)/SensrProtos.xcframework.zip",
            checksum: "5834b82fffac36e993c60c3aee83e57a961037c9d73fb974cecf6168129ef50d"
        ),
        .binaryTarget(
            name: "BioedgeAPI",
            url: "\(releaseURL)/BioedgeAPI.xcframework.zip",
            checksum: "d59690b5a835779f96b02e0a30c2cb2a695ec383f8f1f284f1d763c9b9da5350"
        ),
        .binaryTarget(
            name: "FXCBridge",
            url: "\(releaseURL)/FXCBridge.xcframework.zip",
            checksum: "688571b090e5f608e4615d7ed8cead3b2dcd26e9977131e6090ec61bda6cfb30"
        ),
        .binaryTarget(
            name: "LibFXC",
            url: "\(releaseURL)/LibFXC.xcframework.zip",
            checksum: "7958c3f0db0730d705e810dcf4b72610e00642bc83920bcf2a4320cb6de54ad2"
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
