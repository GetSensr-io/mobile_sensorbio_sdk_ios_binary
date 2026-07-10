import SwiftUI
import Combine
import OSLog
import SensorBioSDK

private let sdkLog = Logger(subsystem: "com.sensorbio.noomapp", category: "SDK")

@main
struct NoomApp: App {
    @State private var dateContext = AppDateContext()
    @State private var logSubscription: AnyCancellable? = NoomApp.wireSDKLogging()

    init() {
        // Internal TestFlight builds retain an explicit environment switch,
        // but every fresh install defaults to production.
        UserDefaults.standard.register(defaults: ["envIsDev": false])
        let isDev = UserDefaults.standard.bool(forKey: "envIsDev")
        SB_SDK.environment = isDev ? .staging : .production
        sensorBio.hydrateSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dateContext)
        }
    }

    /// The SDK's `libLog` publishes to a Combine subject (`SB_SDK.log`)
    /// and does not write to OSLog itself — customer apps must subscribe and
    /// route to whatever logging destination they want. The Noom App
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
