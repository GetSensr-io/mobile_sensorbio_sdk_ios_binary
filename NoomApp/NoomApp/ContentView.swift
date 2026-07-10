import SwiftUI
import SensorBioSDK

struct ContentView: View {
    @State private var session: SB_Session? = sensorBio.session
    @AppStorage("envIsDev") private var envIsDev: Bool = false

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
        .onChange(of: envIsDev) { _, newValue in
            SB_SDK.environment = newValue ? .staging : .production
            sensorBio.hydrateSession()
        }
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
    @AppStorage("envIsDev") private var envIsDev: Bool = false

    var body: some View {
        NoomScreen(bottomPadding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NoomLogoPlate()
                    Spacer()
                    NoomPill(title: "Weight Care", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
                }

                NoomWelcomeCarousel()

                NoomCard(fill: Color.white.opacity(0.76), padding: 16) {
                    Toggle("Use staging SDK environment", isOn: $envIsDev)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(NoomTheme.logoBlack)
                }

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
    }
}

private struct NoomWelcomeCarousel: View {
    @State private var selectedSlide = 0

    private let slides = [
        NoomWelcomeSlide(
            id: 0,
            imageName: "WelcomeMorning",
            eyebrow: "MOVE",
            title: "Make more room for your day.",
            detail: "Build small routines around the life you already have."
        ),
        NoomWelcomeSlide(
            id: 1,
            imageName: "WelcomeKitchen",
            eyebrow: "EAT",
            title: "Food can feel simpler.",
            detail: "Learn the patterns that help you feel steady, not restricted."
        ),
        NoomWelcomeSlide(
            id: 2,
            imageName: "WelcomeEvening",
            eyebrow: "REST",
            title: "End the day on your side.",
            detail: "A calmer night can make tomorrow easier to meet."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabView(selection: $selectedSlide) {
                ForEach(slides) { slide in
                    NoomWelcomeSlideCard(slide: slide)
                        .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 420)

            HStack(spacing: 7) {
                ForEach(slides) { slide in
                    Capsule()
                        .fill(slide.id == selectedSlide ? NoomTheme.red : NoomTheme.softLine)
                        .frame(width: slide.id == selectedSlide ? 24 : 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Welcome carousel, page \(selectedSlide + 1) of \(slides.count)")
        }
    }
}

private struct NoomWelcomeSlide: Identifiable {
    let id: Int
    let imageName: String
    let eyebrow: String
    let title: String
    let detail: String
}

private struct NoomWelcomeSlideCard: View {
    let slide: NoomWelcomeSlide

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(slide.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, NoomTheme.logoBlack.opacity(0.16), NoomTheme.logoBlack.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(slide.eyebrow)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(NoomTheme.rose)
                Text(slide.title)
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .tracking(-1.1)
                    .foregroundStyle(.white)
                Text(slide.detail)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoomTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NoomTheme.cardRadius, style: .continuous)
                .stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slide.eyebrow). \(slide.title). \(slide.detail)")
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
            case "signin_preview", "sign_in_preview":
                NavigationStack { SignInView() }
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
            case "metric_baseline_preview":
                NavigationStack {
                    BaselineMetricDetail(
                        title: "Resting Heart Rate",
                        symbol: "heart.fill",
                        accent: .red,
                        date: .now,
                        value: 58,
                        valueText: "58",
                        unit: "bpm",
                        tone: .heartRate,
                        baseline: PersonalBaseline.make(currentValue: 58, historicalValues: [60, 59, 61, 58, 62, 60, 59, 61, 58, 60, 59, 61, 60, 58, 62, 59]),
                        readings: [
                            MetricReading(label: "Resting", value: "58 bpm"),
                            MetricReading(label: "Average", value: "67 bpm"),
                            MetricReading(label: "Low", value: "52 bpm"),
                            MetricReading(label: "High", value: "98 bpm")
                        ]
                    )
                }
            case "inflammation_preview":
                NavigationStack { InflammationSignalPreviewView() }
            case "record_activity":
                NavigationStack { RecordActivityView() }
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
