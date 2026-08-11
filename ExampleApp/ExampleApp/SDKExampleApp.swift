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

        // SDK-key mode: the SDK holds org_id/sdk_key in memory only, so on a
        // cold launch that hydrates a prior SDK-key session we must re-supply
        // them before the first authenticated call (dashboard fetch). We read
        // them from the same UserDefaults the register form persisted.
        let orgId = UserDefaults.standard.string(forKey: "register.orgId") ?? ""
        let sdkKey = UserDefaults.standard.string(forKey: "register.sdkKey") ?? ""
        if !orgId.isEmpty && !sdkKey.isEmpty {
            SB_SDK.sdkKeyCredentials = SB_SDKKeyCredentials(orgId: orgId, sdkKey: sdkKey)
        }
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
