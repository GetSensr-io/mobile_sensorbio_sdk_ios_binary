import SwiftUI
import SensorBioSDK

struct ContentView: View {
    @State private var session: SB_Session? = sensorBio.session
    #if DEBUG
    @AppStorage("envIsDev") private var envIsDev: Bool = false
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if let session, isLiveAuthRoute(qaRoute) {
                MainTabView(session: session)
            } else if let qaRoute {
                NoomQAHost(route: qaRoute)
            } else if let session {
                MainTabView(session: session)
            } else {
                signedOut
            }
            #else
            if let session {
                MainTabView(session: session)
            } else {
                signedOut
            }
            #endif
        }
        .onReceive(sensorBio.$session) { session = $0 }
        #if DEBUG
        .onChange(of: envIsDev) { _, newValue in
            SB_SDK.environment = newValue ? .staging : .production
            sensorBio.hydrateSession()
        }
        #endif
    }

    #if DEBUG
    private var qaRoute: String? {
        ProcessInfo.processInfo.environment["NOOM_QA_ROUTE"]
    }

    private func isLiveAuthRoute(_ route: String?) -> Bool {
        guard let route else { return false }
        return ["signin", "sign_in", "signup"].contains(route)
    }
    #endif

    private var signedOut: some View {
        NavigationStack {
            NoomSignedOutView()
        }
    }
}

struct NoomSignedOutView: View {
    #if DEBUG
    @AppStorage("envIsDev") private var envIsDev: Bool = false
    #endif

    var body: some View {
        NoomScreen {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    NoomLogoPlate()
                    Spacer()
                    NoomPill(title: "Weight Care", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Build habits that fit your body today.").noomSerifTitle(size: 46)
                    // Updated text with superscript asterisk and footnote comment
                    Text("Noom pairs behavior change with sleep, recovery, and movement signals from Noom Band when data is available.").noomBody()
                }

                NoomCard {
                    VStack(alignment: .leading, spacing: 14) {
                        NoomPill(title: "Noom Band ready", color: NoomTheme.red)
                        Text("Sleep, recovery, and movement signals help shape a calmer daily plan.").noomBody()
                        HStack(spacing: 10) {
                            NoomMetricTile(label: "Sleep", value: "Sync", caption: "After setup")
                            NoomMetricTile(label: "Recovery", value: "Sync", caption: "After setup")
                        }
                    }
                }

                #if DEBUG
                NoomCard {
                    Toggle("Use staging SDK environment", isOn: $envIsDev)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(NoomTheme.logoBlack)
                }
                #endif

                VStack(spacing: 12) {
                    NavigationLink {
                        SignInView()
                    } label: {
                        Text("Sign in")
                    }
                    .buttonStyle(NoomPrimaryButtonStyle())

                    NavigationLink {
                        SignUpView()
                    } label: {
                        Text("Create account")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(NoomTheme.logoBlack)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white, in: Capsule())
                            .overlay { Capsule().stroke(NoomTheme.ink.opacity(0.10), lineWidth: 1) }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Removed top‑center NOOM logo to keep only the left‑aligned logo in the signed‑out view.
        // The safeAreaInset that added a centered logo at the top has been eliminated.
        // This preserves the layout; the headline now aligns under the left‑aligned logo.

    }
}

#Preview {
    ContentView()
}

#if DEBUG
private struct NoomQAHost: View {
    let route: String
    @State private var dateContext = AppDateContext()
    @State private var path: [NoomQADestination] = []
    @State private var didSetInitialDestination = false

    private var session: SB_Session {
        SB_Session(userId: "preview-member", email: "test@example.com", username: "Noom Member", photoURL: nil, imperialUnits: true)
    }

    var body: some View {
        Group {
            switch route {
            case "signedout_home":
                signedOutStack()
            case "signin", "sign_in":
                signedOutStack(initial: .signIn)
            case "signup":
                signedOutStack(initial: .signUp)
            case "main_default":
                MainTabView(session: session)
            case "dashboard_empty", "dashboard_default":
                NavigationStack { DashboardView(session: session) }
            case "insights_empty", "insights_default":
                NavigationStack { InsightsView() }
            case "pair_setup":
                NavigationStack { NoomBandSetupEntryView() }
            case "pair_scanning":
                PairDeviceView()
            case "profile_no_device":
                NavigationStack { ProfileView(session: session) }
            case "band_never_paired":
                NavigationStack { NoomBandStateQAView(state: .neverPaired) }
            case "band_connecting":
                NavigationStack { NoomBandStateQAView(state: .connecting) }
            case "band_connected":
                NavigationStack { NoomBandStateQAView(state: .connected) }
            case "band_disconnected":
                NavigationStack { NoomBandStateQAView(state: .pairedDisconnected) }
            case "band_error":
                NavigationStack { NoomBandStateQAView(state: .error("Noom Band could not connect. Keep it nearby and try again.")) }
            case "progress", "progress_signals":
                NavigationStack { NoomProgressSignalsView() }
            case "sleep_recovery":
                sleepRecoveryStack()
            case "sleep_detail":
                sleepRecoveryStack(initial: .sleepDetail)
            case "recovery_detail":
                sleepRecoveryStack(initial: .recoveryDetail)
            case "steps_detail":
                NavigationStack { StepsDetailView() }
            case "calories_detail":
                NavigationStack { CaloriesDetailView() }
            case "hr_detail":
                NavigationStack { HRDetailView() }
            case "hrv_detail":
                NavigationStack { HRVDetailView() }
            case "rr_detail":
                NavigationStack { RRDetailView() }
            default:
                Text("This screen is not available.")
                    .padding()
            }
        }
        .environment(dateContext)
    }

    private func signedOutStack(initial: NoomQADestination? = nil) -> some View {
        NavigationStack(path: $path) {
            NoomSignedOutView()
                .navigationDestination(for: NoomQADestination.self) { destination in
                    switch destination {
                    case .signIn:
                        SignInView()
                    case .signUp:
                        SignUpView()
                    case .sleepDetail:
                        SleepDetailView()
                    case .recoveryDetail:
                        RecoveryDetailView()
                    }
                }
        }
        .onAppear { setInitialDestination(initial) }
    }

    private func sleepRecoveryStack(initial: NoomQADestination? = nil) -> some View {
        NavigationStack(path: $path) {
            NoomSleepRecoveryView()
                .navigationDestination(for: NoomQADestination.self) { destination in
                    switch destination {
                    case .sleepDetail:
                        SleepDetailView()
                    case .recoveryDetail:
                        RecoveryDetailView()
                    case .signIn:
                        SignInView()
                    case .signUp:
                        SignUpView()
                    }
                }
        }
        .onAppear { setInitialDestination(initial) }
    }

    private func setInitialDestination(_ destination: NoomQADestination?) {
        guard let destination, !didSetInitialDestination, path.isEmpty else { return }
        didSetInitialDestination = true
        path = [destination]
    }
}

private struct NoomBandStateQAView: View {
    let state: NoomBandConnectionState

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Noom Band") {
                NoomPill(title: state.title, color: state.isLiveReady ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
            }
            NoomCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(state.title).noomSerifTitle(size: 30)
                    Text(state.detail).noomBody()
                    Text(state.callToAction)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
        .navigationTitle("Noom Band")
    }
}

private enum NoomQADestination: Hashable {
    case signIn
    case signUp
    case sleepDetail
    case recoveryDetail
}
#endif
