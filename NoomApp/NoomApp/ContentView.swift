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
        GeometryReader { geometry in
            let adaptiveCarouselHeight = min(500, max(320, geometry.size.height * 0.52))
            NoomScreen(bottomPadding: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        NoomLogoPlate(compact: true)
                        Spacer()
                        NoomPill(title: "Weight Care", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
                    }

                    NoomWelcomeCarousel(height: adaptiveCarouselHeight)

                    #if DEBUG
                    NoomCard(fill: Color.white.opacity(0.76), padding: 16) {
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
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct NoomWelcomeCarousel: View {
    @State private var selectedSlide = 0
    let height: CGFloat

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
            .frame(height: height)

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
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image(slide.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text(slide.detail)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
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
                NavigationStack {
                    DashboardView(
                        session: session,
                        dashboard: DashboardState(),
                        productLoop: ProductLoopStore()
                    )
                }
            case "dashboard_metric_tiles_preview":
                NavigationStack { DashboardMetricTilesPreviewView() }
            case "loading_metric_preview":
                NavigationStack { NoomLoadingPreviewView(kind: .metric) }
            case "loading_dashboard_preview":
                NavigationStack { NoomLoadingPreviewView(kind: .dashboard) }
            case "loading_sleep_preview":
                NavigationStack { NoomLoadingPreviewView(kind: .sleep) }
            case "date_navigator_preview":
                NavigationStack { NoomDateNavigatorPreviewView() }
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
                metricDetailStack(initial: .metricBaseline)
            case "inflammation_preview":
                NavigationStack { InflammationSignalPreviewView() }
            case "inflammation_detail_preview":
                inflammationDetailPreview
            case "sleep_hub_preview":
                NavigationStack { SleepHubPreviewView() }
            case "sleep_empty_preview":
                NavigationStack { NoomFirstNightPreviewView(title: "Sleep") }
            case "dashboard_no_sleep_preview":
                NavigationStack { NoomFirstNightPreviewView(title: "Dashboard") }
            case "record_activity":
                NavigationStack { RecordActivityView() }
            case "steps_detail":
                metricDetailStack(initial: .stepsDetail)
            case "calories_detail":
                metricDetailStack(initial: .caloriesDetail)
            case "hr_detail":
                metricDetailStack(initial: .heartRateDetail)
            case "hrv_detail":
                metricDetailStack(initial: .hrvDetail)
            case "rr_detail":
                metricDetailStack(initial: .respiratoryRateDetail)
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
                    qaDestination(destination)
                }
        }
        .onAppear { setInitialDestination(initial) }
    }

    private func sleepRecoveryStack(initial: NoomQADestination? = nil) -> some View {
        NavigationStack(path: $path) {
            NoomSleepRecoveryView()
                .navigationDestination(for: NoomQADestination.self) { destination in
                    qaDestination(destination)
                }
        }
        .onAppear { setInitialDestination(initial) }
    }

    private func metricDetailStack(initial: NoomQADestination) -> some View {
        NavigationStack(path: $path) {
            NoomMetricPreviewHub()
                .navigationDestination(for: NoomQADestination.self) { destination in
                    qaDestination(destination)
                }
        }
        .onAppear { setInitialDestination(initial) }
    }

    @ViewBuilder
    private func qaDestination(_ destination: NoomQADestination) -> some View {
        switch destination {
        case .signIn:
            SignInView()
        case .signUp:
            SignUpView()
        case .sleepDetail:
            SleepDetailView()
        case .recoveryDetail:
            RecoveryDetailView()
        case .metricBaseline:
            metricBaselinePreview
        case .stepsDetail:
            metricPreview(for: .steps)
        case .caloriesDetail:
            metricPreview(for: .calories)
        case .heartRateDetail:
            metricPreview(for: .heartRate)
        case .hrvDetail:
            metricPreview(for: .hrv)
        case .respiratoryRateDetail:
            metricPreview(for: .respiratoryRate)
        }
    }

    private func metricPreview(for metric: NoomQAMetricPreview) -> some View {
        BaselineMetricDetail(
            title: metric.title,
            symbol: metric.symbol,
            accent: metric.accent,
            date: .now,
            value: metric.value,
            valueText: MetricFormatting.humanNumber(metric.value),
            unit: metric.unit,
            tone: metric.tone,
            baseline: PersonalBaseline.make(currentValue: metric.value, historicalValues: metric.history),
            readings: metric.readings,
            previewDisclosure: "Synthetic development data. Not a personal health result."
        )
    }

    private var inflammationDetailPreview: some View {
        let provider = MockInflammationSignalProvider()
        let completedDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        return NavigationStack {
            InflammationSignalDetailView(
                signal: MockInflammationSignalProvider().signal(for: completedDate),
                historicalValues: provider.trailingValues(before: completedDate)
            )
        }
    }

    private var metricBaselinePreview: some View {
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
            ],
            previewDisclosure: "Synthetic development data. Not a personal health result."
        )
    }

    private func setInitialDestination(_ destination: NoomQADestination?) {
        guard let destination, !didSetInitialDestination, path.isEmpty else { return }
        didSetInitialDestination = true
        path = [destination]
    }
}

private struct DashboardMetricTilesPreviewView: View {
    var body: some View {
        NoomScreen(spacing: 12, bottomPadding: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.logoBlack)
                Text("Friday, July 10")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
            }

            NoomDashboardMetricTile(
                label: "Sleep",
                value: "76",
                unit: "/100",
                caption: "6h 25m asleep",
                systemImage: "moon.stars.fill",
                accent: NoomTheme.metricPurple,
                minHeight: 132,
                prominent: true
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                NoomDashboardMetricTile(label: "Steps", value: "3,350", unit: nil, caption: "Average 2,709", systemImage: "figure.walk", accent: NoomTheme.metricGreen)
                NoomDashboardMetricTile(label: "Active Calories", value: "164", unit: "kcal", caption: "Average 337", systemImage: "flame.fill", accent: NoomTheme.metricAmber)
                NoomDashboardMetricTile(label: "Resting Heart Rate", value: "56", unit: "bpm", caption: "At baseline", systemImage: "heart.fill", accent: NoomTheme.red)
                NoomDashboardMetricTile(label: "Heart Rate Variability", value: "77", unit: "ms", caption: "+19 ms vs baseline", systemImage: "waveform.path.ecg", accent: NoomTheme.metricPurple)
                NoomDashboardMetricTile(label: "Respiratory Rate", value: "14", unit: "/min", caption: "+0.2 /min vs baseline", systemImage: "lungs.fill", accent: NoomTheme.metricBlue)
                NoomDashboardMetricTile(label: "Inflammation Signal", value: "74", unit: "/100", caption: "Sample overnight input", systemImage: "waveform.path.ecg.rectangle", accent: NoomTheme.red)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct NoomQAMetricPreview {
    let title: String
    let symbol: String
    let accent: Color
    let value: Double
    let unit: String
    let tone: BaselineDetailTone
    let history: [Double]
    let readings: [MetricReading]

    static let steps = NoomQAMetricPreview(
        title: "Steps",
        symbol: "figure.walk",
        accent: NoomTheme.red,
        value: 6_250,
        unit: "steps",
        tone: .activity,
        history: [5_880, 6_140, 5_720, 6_430, 6_080, 5_940, 6_520, 6_210, 5_830, 6_360, 6_010, 6_470, 5_900, 6_180, 6_340, 6_020],
        readings: [
            MetricReading(label: "Daily total", value: "6,250 steps"),
            MetricReading(label: "Source", value: "Synthetic preview")
        ]
    )

    static let calories = NoomQAMetricPreview(
        title: "Active Calories",
        symbol: "flame.fill",
        accent: .pink,
        value: 438,
        unit: "kcal",
        tone: .activity,
        history: [402, 451, 420, 467, 431, 446, 415, 472, 439, 458, 427, 463, 410, 449, 435, 470],
        readings: [
            MetricReading(label: "Active energy", value: "438 kcal"),
            MetricReading(label: "Source", value: "Synthetic preview")
        ]
    )

    static let heartRate = NoomQAMetricPreview(
        title: "Resting Heart Rate",
        symbol: "heart.fill",
        accent: .red,
        value: 58,
        unit: "bpm",
        tone: .heartRate,
        history: [60, 59, 61, 58, 62, 60, 59, 61, 58, 60, 59, 61, 60, 58, 62, 59],
        readings: [
            MetricReading(label: "Resting", value: "58 bpm"),
            MetricReading(label: "Average", value: "67 bpm"),
            MetricReading(label: "Low", value: "52 bpm"),
            MetricReading(label: "High", value: "98 bpm")
        ]
    )

    static let hrv = NoomQAMetricPreview(
        title: "Heart-rate Variability",
        symbol: "waveform.path.ecg",
        accent: .indigo,
        value: 46,
        unit: "ms",
        tone: .variability,
        history: [43, 47, 45, 49, 44, 48, 46, 50, 42, 47, 45, 49, 44, 48, 46, 51],
        readings: [
            MetricReading(label: "Nightly median", value: "46 ms"),
            MetricReading(label: "Source", value: "Synthetic preview")
        ]
    )

    static let respiratoryRate = NoomQAMetricPreview(
        title: "Respiratory Rate",
        symbol: "lungs.fill",
        accent: .teal,
        value: 14.8,
        unit: "breaths/min",
        tone: .respiratory,
        history: [14.5, 14.9, 14.6, 15.1, 14.7, 15.0, 14.8, 15.2, 14.4, 14.9, 14.6, 15.0, 14.7, 15.1, 14.8, 15.2],
        readings: [
            MetricReading(label: "Nightly median", value: "14.8 breaths/min"),
            MetricReading(label: "Source", value: "Synthetic preview")
        ]
    )
}

private struct NoomDateNavigatorPreviewView: View {
    @State private var granularity: SB_ViewGranularity = .day

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
            Spacer()
        }
        .noomBackground()
        .navigationTitle("Sleep & Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NoomLoadingPreviewView: View {
    enum Kind { case metric, dashboard, sleep }
    let kind: Kind

    var body: some View {
        NoomScreen {
            NoomTopBar(label: topLabel) { NoomPill(title: "Loading", color: NoomTheme.rose, foreground: NoomTheme.logoBlack) }
            NoomLoadingExperience(
                title: title,
                detail: detail,
                systemImage: systemImage,
                accent: accent
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topLabel: String {
        switch kind { case .metric: return "Resting Heart Rate"; case .dashboard: return "Dashboard"; case .sleep: return "Sleep" }
    }
    private var title: String {
        switch kind { case .metric: return "Listening for your rhythm"; case .dashboard: return "Bringing today into focus"; case .sleep: return "Waking up your sleep story" }
    }
    private var detail: String {
        switch kind { case .metric: return "Shaping your resting heart-rate story now."; case .dashboard: return "Gathering sleep, movement, and overnight signals."; case .sleep: return "Gathering last night's stages and recovery signals." }
    }
    private var systemImage: String {
        switch kind { case .metric: return "heart.fill"; case .dashboard: return "sun.max.fill"; case .sleep: return "moon.stars.fill" }
    }
    private var accent: Color {
        switch kind { case .metric, .dashboard: return NoomTheme.red; case .sleep: return NoomTheme.metricPurple }
    }
}

private struct NoomMetricPreviewHub: View {
    private let destinations: [(title: String, value: NoomQADestination)] = [
        ("Resting heart rate sample", .metricBaseline),
        ("Steps", .stepsDetail),
        ("Active calories", .caloriesDetail),
        ("Resting heart rate", .heartRateDetail),
        ("Heart-rate variability", .hrvDetail),
        ("Respiratory rate", .respiratoryRateDetail)
    ]

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Metric previews") {
                EmptyView()
            }
            NoomCard {
                VStack(spacing: 0) {
                    ForEach(Array(destinations.enumerated()), id: \.offset) { index, destination in
                        NavigationLink(value: destination.value) {
                            HStack {
                                Text(destination.title)
                                    .foregroundStyle(NoomTheme.logoBlack)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(NoomTheme.ink.opacity(0.55))
                            }
                            .frame(minHeight: 50)
                        }
                        if index < destinations.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationTitle("Metric previews")
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
    case metricBaseline
    case stepsDetail
    case caloriesDetail
    case heartRateDetail
    case hrvDetail
    case respiratoryRateDetail
}
#endif
