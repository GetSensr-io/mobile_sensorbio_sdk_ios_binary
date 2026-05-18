// swift-tools-version: 6.1
import PackageDescription

let releaseTag = "v0.1.1"
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
            checksum: "ecc64b520613a46d6a77c064299c0a244eee7ad1a614e055355964f078460de6"
        ),
        .binaryTarget(
            name: "SensrProtos",
            url: "\(releaseURL)/SensrProtos.xcframework.zip",
            checksum: "08ac2defd934cdc24551c5dc3a9dac634fe1d1b925bbb0ea63ba366abfaf237b"
        ),
        .binaryTarget(
            name: "BioedgeAPI",
            url: "\(releaseURL)/BioedgeAPI.xcframework.zip",
            checksum: "3af4bd5fea7eb9ec9a7829b125ce27f26784945106e6e35a9a87a44da424c5a8"
        ),
        .binaryTarget(
            name: "FXCBridge",
            url: "\(releaseURL)/FXCBridge.xcframework.zip",
            checksum: "20a321795608cff3e842c15e0966d0f72a7d4ac155170a60562e0fd593276ff8"
        ),
        .binaryTarget(
            name: "LibFXC",
            url: "\(releaseURL)/LibFXC.xcframework.zip",
            checksum: "5e5e8e2a54fa0c3d15748465278155a4369a104ec9b7084401263dd4a25a925e"
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
