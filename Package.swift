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
            checksum: "bd81872f47f4d24d7675388c6c4949637789eea3159ca4e0e097697504938649"
        ),
        // Philips signal-processing library. Ships separately because it is a
        // dynamic library and cannot be absorbed into the static SDK the way
        // every other dependency is.
        .binaryTarget(
            name: "LibFXC",
            url: "\(releaseBase)/v\(version)/LibFXC.xcframework.zip",
            checksum: "281b347a7c7055acb5c6739e1bd6ac1e14934cee305cca59a92f38d331b5f43c"
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
