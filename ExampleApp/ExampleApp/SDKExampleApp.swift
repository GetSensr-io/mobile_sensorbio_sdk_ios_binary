import SwiftUI
import Combine
import OSLog
import SensorBioSDK

private let sdkLog = Logger(subsystem: "com.sensorbio.sdkexample", category: "SDK")

@main
struct SDKExampleApp: App {
    @State private var dateContext = AppDateContext()
    @State private var logSubscription: AnyCancellable? = SDKExampleApp.wireSDKLogging()

    init() {
        // Environment toggle (Staging / Prod) lives on the signed-out
        // home; the user's choice persists via UserDefaults under
        // "envIsDev" and is read here on cold launch. Defaults to
        // Staging for SDK dogfooding. Note: changing environment after
        // the first RPC does not currently rebuild the gRPC client —
        // the toggle takes full effect on next launch.
        UserDefaults.standard.register(defaults: ["envIsDev": true])
        let isDev = UserDefaults.standard.bool(forKey: "envIsDev")
        SB_SDK.environment = isDev ? .staging : .production

        // Nothing else to configure. The SDK remembers which organization a
        // session belongs to, so a cold launch into a restored session needs
        // no credentials from the host — and the organization SDK Key is
        // never on the device to re-supply in the first place (SB-2095).
        //
        // What used to be here: a restore of `SB_SDK.sdkKeyCredentials` read
        // back out of UserDefaults, including the raw SDK Key, because every
        // authenticated call presented it. That is gone.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dateContext)
        }
    }

    /// The SDK's `libLog` publishes to a Combine subject (`SB_SDK.log`)
    /// and does not write to OSLog itself — customer apps must subscribe and
    /// route to whatever logging destination they want. The SDK Example
    /// routes everything to `os.Logger` so `idevicesyslog` / Xcode → Devices
    /// can capture the SDK's lifecycle for debugging.
    private static func wireSDKLogging() -> AnyCancellable {
        SB_SDK.log.sink { (level, message, file, function, line) in
            let basename = (file as NSString).lastPathComponent
            let prefix = "[\(basename):\(line) \(function)]"
            let composed = "\(prefix) \(message)"
            switch level {
            case .verbose, .debug:
                sdkLog.debug("\(composed, privacy: .public)")
            case .info:
                sdkLog.info("\(composed, privacy: .public)")
            case .warning:
                sdkLog.warning("\(composed, privacy: .public)")
            case .error:
                sdkLog.error("\(composed, privacy: .public)")
            @unknown default:
                sdkLog.debug("\(composed, privacy: .public)")
            }
        }
    }
}
