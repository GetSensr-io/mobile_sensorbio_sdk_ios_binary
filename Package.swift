// swift-tools-version: 6.0
//
//  SensorBioSDK — binary distribution
//
//  Add this package to your app and you are done. It declares NO third-party
//  dependencies, and that is deliberate: grpc-swift, SwiftNIO, SwiftProtobuf
//  and everything else the SDK uses are compiled inside the xcframework with
//  their symbols hidden. Nothing here can collide with a library you already
//  use — including Firebase, which brings its own gRPC.
//
//  Do not add a grpc-swift (or any other) dependency here to "match" ours.
//  A second copy of those symbols in the same app is the failure this
//  packaging exists to prevent.
//
//  ── Why the frameworks are URLs and not files in this repo ────────────────
//
//  They are attached to the GitHub release for each version. Xcode downloads
//  and verifies them against the checksums below on first resolve.
//
//  Not a style choice: each slice of the SDK framework is ~102 MB, over
//  GitHub's hard 100 MB per-file limit, so committing it is not possible.
//  It is also how this stays maintainable — the artifacts would otherwise add
//  ~170 MB to this repo's history on every single release.
//
//  GENERATED. `scripts/build-xcframeworks.sh` in the SDK repo rewrites the
//  version and both checksums. Do not hand-edit them: a checksum that does
//  not match the asset fails every customer's build with a diagnostic that
//  does not mention this file.
//
import PackageDescription

let version = "3.0.0"
let releaseBase = "https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary/releases/download"

let package = Package(
    name: "SensorBioSDK",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "SensorBioSDK", targets: ["SensorBioSDKLink"])
    ],
    targets: [
        // The SDK itself. The target name IS the module name you import.
        .binaryTarget(
            name: "SensorBioSDK",
            url: "\(releaseBase)/v\(version)/SensorBioSDK.xcframework.zip",
            checksum: "ca94ed00c7755e15305463c96f7755701c2f79a455ca626ed28573203fdb0ad7"
        ),
        // Philips signal-processing library. Ships separately because it is a
        // dynamic library and cannot be absorbed into the static SDK the way
        // every other dependency is.
        .binaryTarget(
            name: "LibFXC",
            url: "\(releaseBase)/v\(version)/LibFXC.xcframework.zip",
            checksum: "b777f7078ee9f1bd2bcae6e570422ff91c1a399fce1ff51bc7b3dc1cd049543c"
        ),
        // Link carrier. A `binaryTarget` cannot express dependencies or
        // linker settings on its own, so the product points at this instead
        // and it pulls both binaries in.
        .target(
            name: "SensorBioSDKLink",
            dependencies: ["SensorBioSDK", "LibFXC"],
            path: "Sources/SensorBioSDKLink"
        )
    ]
)
