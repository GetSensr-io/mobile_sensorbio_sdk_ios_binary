import SwiftUI
import Combine
import OSLog
import SensorBioSDK

private let sdkLog = Logger(subsystem: "com.sensorbio.noomapp", category: "SDK")

@main
struct NoomApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dateContext = AppDateContext()
    @State private var sleepProcessing = SleepProcessingCoordinator()
    @State private var logSubscription: AnyCancellable? = NoomApp.wireSDKLogging()

    init() {
        #if DEBUG
        // Local QA can switch environments without changing source.
        UserDefaults.standard.register(defaults: ["envIsDev": false])
        let isDev = UserDefaults.standard.bool(forKey: "envIsDev")
        SB_SDK.environment = isDev ? .staging : .production
        #else
        // Distributed builds are locked to production. Never persist a staging
        // override into TestFlight or App Store authentication/health flows.
        UserDefaults.standard.removeObject(forKey: "envIsDev")
        SB_SDK.environment = .production
        #endif
        // SDK v0.13 requires its keychain namespace and legacy defaults to be
        // prepared before any authentication call or session hydration.
        SB_SDK.bootstrapKeychain()
        SB_SDK.runDefaultsMigratorIfNeeded()
        sensorBio.hydrateSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dateContext)
                .environment(sleepProcessing)
                .onChange(of: dateContext.selectedDate, initial: true) { _, date in
                    sleepProcessing.selectDate(date)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    sleepProcessing.setForeground(phase == .active)
                }
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
            switch level {
            case .verbose, .debug:
                sdkLog.debug("\(prefix, privacy: .public) \(message, privacy: .private(mask: .hash))")
            case .info:
                sdkLog.info("\(prefix, privacy: .public) \(message, privacy: .private(mask: .hash))")
            case .warning:
                sdkLog.warning("\(prefix, privacy: .public) \(message, privacy: .private(mask: .hash))")
            case .error:
                sdkLog.error("\(prefix, privacy: .public) \(message, privacy: .private(mask: .hash))")
            @unknown default:
                sdkLog.debug("\(prefix, privacy: .public) \(message, privacy: .private(mask: .hash))")
            }
        }
    }
}
