import SwiftUI
import Foundation
import Observation
import SensorBioSDK
import Combine

enum NoomSleepHistory {
    private static func recordedSleepKey(for userID: String?) -> String? {
        guard let userID, !userID.isEmpty else { return nil }
        let account = Data(userID.utf8).base64EncodedString()
        return "noomHasRecordedSleep.\(account)"
    }

    static func hasRecordedSleep(for userID: String?) -> Bool {
        guard let key = recordedSleepKey(for: userID) else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func recordSleep(for userID: String?) {
        guard let key = recordedSleepKey(for: userID) else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct MainTabView: View {
    let session: SB_Session
    @State private var dashboard = DashboardState()
    @State private var productLoop = ProductLoopStore()

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(session: session, dashboard: dashboard, productLoop: productLoop)
            }
                .tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }

            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "sparkles") }

            NavigationStack { NoomProgressSignalsView() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            NavigationStack { SleepHomeView(userID: session.userId) }
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
        }
        .tint(NoomTheme.red)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(NoomTheme.warmSurface, for: .tabBar)
    }
}

struct SleepHomeView: View {
    let userID: String
    @Environment(AppDateContext.self) private var dateContext
    @State private var state = SleepHomeState()
    @State private var haveDevice = sensorBio.haveDevice
    @State private var connected = sensorBio.connected
    @State private var postSyncReloadTask: Task<Void, Never>?

    var body: some View {
        @Bindable var ctx = dateContext
        NoomScreen {
            NoomTopBar(label: "Sleep & Recovery") {
                NoomPill(
                    title: state.syncLabel,
                    color: state.isFresh ? NoomTheme.mint : NoomTheme.rose,
                    foreground: NoomTheme.logoBlack
                )
            }

            NoomDayNavigator(selection: $ctx.selectedDate)

            Text("Last night, in context").noomSerifTitle(size: 36)
            Text("Your latest Noom Band sleep and recovery signals, with the details one tap away.").noomBody()

            if state.isLoading && state.dailySleep == nil {
                loadingCard
            } else if let detail = state.dailySleep {
                sleepHeroSummary(detail)
                atAGlanceMetrics(detail)
                sleepStagesPreview(detail)
                recoveryFactorsPreview(detail)
            } else {
                noSessionCard
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dateContext.selectedDate) { await state.load(date: dateContext.selectedDate, userID: userID) }
        .refreshable { await state.load(date: dateContext.selectedDate, userID: userID, forceRemote: true) }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.sleepStored.merge(with: sensorBio.sleepUploaded)) { _ in
            schedulePostSyncReload()
        }
        .onReceive(sensorBio.syncCompleted) { result in
            guard result?.acknowledge == true else {
                postSyncReloadTask?.cancel()
                return
            }
            schedulePostSyncReload()
        }
        .onDisappear { postSyncReloadTask?.cancel() }
    }

    private func schedulePostSyncReload() {
        postSyncReloadTask?.cancel()
        postSyncReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await state.load(date: dateContext.selectedDate, userID: userID, forceRemote: true)
        }
    }

    private var loadingCard: some View {
        NoomLoadingExperience(
            title: "Waking up your sleep story",
            detail: "Gathering last night's stages and recovery signals.",
            systemImage: "moon.stars.fill",
            accent: NoomTheme.metricPurple
        )
    }

    private var noSessionCard: some View {
        VStack(spacing: 12) {
            if shouldShowFirstNight {
                NoomFirstNightCard(bandReady: bandReadyForTonight)
            } else {
                NoomEmptyStateCard(
                    title: state.errorMessage == nil ? "No sleep session for this date" : "Sleep unavailable",
                    message: state.errorMessage ?? "No completed sleep was returned for the selected date. Try another day or sync Noom Band again.",
                    systemImage: state.errorMessage == nil ? "moon.zzz.fill" : "exclamationmark.triangle.fill"
                )
            }
            if !bandReadyForTonight {
                NavigationLink { NoomBandSetupEntryView() } label: {
                    Label(haveDevice ? "Bring Noom Band online" : "Set up Noom Band", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NoomSecondaryButtonStyle())
            }
        }
    }

    private var bandReadyForTonight: Bool { haveDevice && connected }

    private var shouldShowFirstNight: Bool {
        Calendar.current.isDateInToday(dateContext.selectedDate) &&
        !NoomSleepHistory.hasRecordedSleep(for: userID) &&
        state.errorMessage == nil
    }

    private func sleepHeroSummary(_ detail: SB_SleepDetailDay) -> some View {
        let score = Int(detail.sleepScore.score)
        return NavigationLink { SleepDetailView() } label: {
            NoomCard(fill: NoomTheme.ink, padding: 22) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sleep score")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                        Text("\(MetricFormatting.humanNumber(score))")
                            .font(.system(size: 58, weight: .bold, design: .serif))
                            .tracking(-2)
                            .foregroundStyle(.white)
                        Text(readinessLabel(score))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(hoursMinutes(seconds: Int(detail.sleepTimeSec))) asleep")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.78))
                        Label("Open sleep details", systemImage: "chevron.right")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(NoomTheme.rose)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(NoomTheme.red)
                        .frame(width: 62, height: 62)
                        .background(.white.opacity(0.12), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sleep score \(score), \(readinessLabel(score)). \(hoursMinutes(seconds: Int(detail.sleepTimeSec))) asleep. Open sleep details.")
    }

    private func atAGlanceMetrics(_ detail: SB_SleepDetailDay) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink { SleepDetailView() } label: {
                NoomMetricTile(label: "Total sleep", value: hoursMinutes(seconds: Int(detail.sleepTimeSec)), caption: "Last night", minHeight: 98)
            }
            .buttonStyle(.plain)
            NavigationLink { SleepDetailView() } label: {
                NoomMetricTile(label: "Resting HR", value: "\(MetricFormatting.humanNumber(Int(detail.restingHr))) bpm", caption: "Overnight", minHeight: 98)
            }
            .buttonStyle(.plain)
            NavigationLink { RecoveryDetailView() } label: {
                NoomMetricTile(label: "HRV", value: "\(MetricFormatting.humanNumber(Int(detail.restingHrv))) ms", caption: "Recovery signal", minHeight: 98)
            }
            .buttonStyle(.plain)
            if let recoveryScore = state.recoveryScore {
                NavigationLink { RecoveryDetailView() } label: {
                    NoomMetricTile(label: "Recovery", value: MetricFormatting.humanNumber(recoveryScore), caption: "Today", minHeight: 98)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { RecoveryDetailView() } label: {
                    NoomMetricTile(label: "Recovery", value: "Open", caption: "Details", minHeight: 98)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sleepStagesPreview(_ detail: SB_SleepDetailDay) -> some View {
        NavigationLink { SleepDetailView() } label: {
            NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last night’s sleep").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.logoBlack)
                            Text("A quick view of returned stage coverage").noomBody()
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(NoomTheme.muted)
                    }
                    SleepHubStageBand(stages: stageSlices(detail.stages))
                        .frame(height: 20)
                    HStack(spacing: 8) {
                        stageValue("Awake", detail.stages.awakePercentage)
                        stageValue("Deep", detail.stages.deepPercentage)
                        stageValue("REM", detail.stages.remPercentage)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Last night’s sleep stages. Awake \(detail.stages.awakePercentage) percent, deep \(detail.stages.deepPercentage) percent, REM \(detail.stages.remPercentage) percent. Open sleep details.")
    }

    private func recoveryFactorsPreview(_ detail: SB_SleepDetailDay) -> some View {
        let factors = state.recoveryFactors.isEmpty ? detail.scoreFactors.map { SleepHubFactor(title: $0.title, detail: $0.description) } : state.recoveryFactors
        return NavigationLink { RecoveryDetailView() } label: {
            NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What shaped recovery").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.logoBlack)
                            Text("Returned factors from your latest available readout").noomBody()
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(NoomTheme.muted)
                    }
                    if factors.isEmpty {
                        Text("Recovery factors will appear when the latest sync returns them.").noomBody()
                    } else {
                        ForEach(factors.prefix(2)) { factor in
                            SleepHubFactorRow(title: factor.title.isEmpty ? "Recovery factor" : factor.title, detail: factor.detail)
                        }
                    }
                    Text("Open recovery details").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.ink)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What shaped recovery. Open recovery details.")
    }

    private func stageValue(_ label: String, _ value: Int32) -> some View {
        Text("\(label) \(MetricFormatting.humanNumber(Int(value)))%")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(NoomTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageSlices(_ stages: SB_SleepStages) -> [SleepHubStageSlice] {
        [
            SleepHubStageSlice(label: "Awake", percentage: Double(stages.awakePercentage), color: NoomTheme.red),
            SleepHubStageSlice(label: "Light", percentage: Double(stages.lightPercentage), color: Color(hex: 0x98C7B2)),
            SleepHubStageSlice(label: "Deep", percentage: Double(stages.deepPercentage), color: NoomTheme.ink),
            SleepHubStageSlice(label: "REM", percentage: Double(stages.remPercentage), color: Color(hex: 0xBFDACD))
        ]
    }

    private func readinessLabel(_ score: Int) -> String {
        switch score {
        case 80...: return "Restorative night"
        case 65..<80: return "A steady night"
        default: return "A lighter night"
        }
    }

    private func hoursMinutes(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// Friendly first-use state shared by Today, Sleep, and Sleep detail.
/// It explains the short path to value instead of presenting an empty score.
struct NoomFirstNightCard: View {
    var title: String = "Tonight is night one"
    var message: String? = nil
    var bandReady: Bool = sensorBio.haveDevice && sensorBio.connected

    private let steps = [
        FirstNightStep(icon: "watch.analog", title: "Wear your band", detail: "Keep it snug overnight"),
        FirstNightStep(icon: "sunrise.fill", title: "Wake & sync", detail: "Noom updates automatically"),
        FirstNightStep(icon: "sparkles", title: "Meet your sleep story", detail: "See sleep and Body Status")
    ]

    var body: some View {
        NoomCard(fill: Color.white.opacity(0.88), padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle().fill(NoomTheme.metricPurple.opacity(0.16))
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(NoomTheme.metricPurple)
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NoomTheme.red)
                            .offset(x: 25, y: -23)
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 7) {
                        NoomPill(
                            title: bandReady ? "Band ready" : "One night to begin",
                            color: bandReady ? NoomTheme.mint : NoomTheme.rose,
                            foreground: NoomTheme.logoBlack
                        )
                        Text(title).noomSerifTitle(size: 28)
                        Text(message ?? "No score yet—and that’s expected. One comfortable night gives Noom the first signals for your morning story.")
                            .noomBody()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(index == 0 ? NoomTheme.rose : NoomTheme.mint.opacity(0.72))
                                Image(systemName: step.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(NoomTheme.logoBlack)
                            }
                            .frame(width: 38, height: 38)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(NoomTheme.logoBlack)
                                Text(step.detail).noomBody()
                            }
                            Spacer(minLength: 0)
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(NoomTheme.muted)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct FirstNightStep {
    let icon: String
    let title: String
    let detail: String
}

@MainActor
@Observable
final class SleepHomeState {
    var dailySleep: SB_SleepDetailDay?
    var dailyRecovery: SB_DailyRecoveryTrending?
    var isLoading = false
    var errorMessage: String?

    var recoveryScore: Int? {
        guard let graph = dailyRecovery?.graph else { return nil }
        return Int(graph.goalItem.item.value)
    }

    var recoveryFactors: [SleepHubFactor] {
        guard let factors = dailyRecovery?.graph?.scoreFactors else { return [] }
        return factors.map { SleepHubFactor(title: $0.title, detail: $0.description) }
    }

    var isFresh: Bool {
        Calendar.current.isDateInToday(sensorBio.lastSyncd)
    }

    var syncLabel: String {
        isFresh ? "Synced today" : "Sync needed"
    }

    private var activeRequestID: UUID?

    @MainActor
    func load(date: Date, userID: String, forceRemote: Bool = false) async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        defer {
            if activeRequestID == requestID { isLoading = false }
        }

        var nextSleep: SB_SleepDetailDay?
        var nextRecovery: SB_DailyRecoveryTrending?
        var nextError: String?
        let tzOffset = Int32(TimeZone.current.secondsFromGMT(for: date))

        do {
            let dashboard = try await sensorBio.fetchDashboardData(date: date, tzOffset: tzOffset, forceRemote: forceRemote)
            if let session = dashboard.sleeps.first {
                NoomSleepHistory.recordSleep(for: userID)
                let endDate = Date(timeIntervalSince1970: TimeInterval(session.endTimestamp) / 1000)
                nextSleep = try await sensorBio.fetchSleepDetail(endDate: endDate, endTimestamp: Int64(session.endTimestamp), forceRemote: forceRemote)
            }
        } catch is CancellationError {
            return
        } catch {
            nextError = "Connect and sync Noom Band to load your sleep summary."
        }

        if !Task.isCancelled {
            nextRecovery = try? await sensorBio.fetchDailyRecovery(date: date, forceRemote: forceRemote)
        }

        guard activeRequestID == requestID, !Task.isCancelled else { return }
        dailySleep = nextSleep
        dailyRecovery = nextRecovery
        errorMessage = nextError
    }
}

struct SleepHubFactor: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct SleepHubFactorRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoomTheme.red)
                .frame(width: 28, height: 28)
                .background(NoomTheme.rose, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(NoomTheme.logoBlack)
                Text(detail.isEmpty ? "This is part of your latest recovery readout." : detail).noomBody()
            }
        }
    }
}

private struct SleepHubStageSlice: Identifiable {
    let id = UUID()
    let label: String
    let percentage: Double
    let color: Color
}

private struct SleepHubStageBand: View {
    let stages: [SleepHubStageSlice]

    private var total: Double { max(stages.map(\.percentage).reduce(0, +), 1) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(stages) { stage in
                    stage.color
                        .frame(width: max(4, proxy.size.width * CGFloat(max(stage.percentage, 0) / total)))
                        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.32)).frame(height: 2) }
                        .accessibilityLabel("\(stage.label), \(Int(stage.percentage)) percent")
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct NoomFirstNightPreviewView: View {
    let title: String

    var body: some View {
        NoomScreen {
            NoomTopBar(label: title) {
                NoomPill(title: "Preview", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
            }
            NoomDayNavigator(selection: .constant(Date()))
            NoomFirstNightCard(bandReady: true)
            NoomDashboardMetricTile(
                label: "Sleep",
                value: "—",
                unit: nil,
                caption: "Your sleep story starts tonight",
                systemImage: "moon.stars.fill",
                accent: NoomTheme.metricPurple,
                minHeight: 132,
                prominent: true
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SleepHubPreviewView: View {
    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Sleep & Recovery") { NoomPill(title: "Preview sample", color: NoomTheme.rose, foreground: NoomTheme.logoBlack) }
            Text("Last night, in context").noomSerifTitle(size: 36)
            Text("Synthetic development data for layout review. It is not a personal health result.").noomBody()
            NoomCard(fill: NoomTheme.ink, padding: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sleep score").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.66))
                        Text("82").font(.system(size: 58, weight: .bold, design: .serif)).foregroundStyle(.white)
                        Text("Restorative night").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("7h 34m asleep").font(.system(size: 14)).foregroundStyle(.white.opacity(0.78))
                        Label("Open sleep details", systemImage: "chevron.right").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.rose)
                    }
                    Spacer()
                    Image(systemName: "moon.stars.fill").font(.system(size: 31, weight: .semibold)).foregroundStyle(NoomTheme.red).frame(width: 62, height: 62).background(.white.opacity(0.12), in: Circle())
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NoomMetricTile(label: "Total sleep", value: "7h 34m", caption: "Last night", minHeight: 98)
                NoomMetricTile(label: "Resting HR", value: "58 bpm", caption: "Overnight", minHeight: 98)
                NoomMetricTile(label: "HRV", value: "42 ms", caption: "Recovery signal", minHeight: 98)
                NoomMetricTile(label: "Recovery", value: "76", caption: "Today", minHeight: 98)
            }
            NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Last night’s sleep").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.logoBlack)
                        Spacer()
                        Label("Details", systemImage: "chevron.right").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.ink)
                    }
                    SleepHubStageBand(stages: [
                        SleepHubStageSlice(label: "Awake", percentage: 8, color: NoomTheme.red),
                        SleepHubStageSlice(label: "Light", percentage: 48, color: Color(hex: 0x98C7B2)),
                        SleepHubStageSlice(label: "Deep", percentage: 22, color: NoomTheme.ink),
                        SleepHubStageSlice(label: "REM", percentage: 22, color: Color(hex: 0xBFDACD))
                    ])
                    .frame(height: 20)
                    Text("Awake 8% · Deep 22% · REM 22%").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.muted)
                }
            }
            NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What shaped recovery").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.logoBlack)
                    SleepHubFactorRow(title: "Consistent bedtime", detail: "Your wind-down window helped protect deep sleep.")
                    Text("Open recovery details").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(NoomTheme.ink)
                }
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

/// Compact, always-visible Band status beside the dashboard profile control.
/// Mobbin Fitbit pattern: keep sync feedback in the dashboard header. Apple HIG:
/// use determinate progress when an accurate percentage exists and keep its
/// location stable while the operation is active.
enum NoomBandSyncIssue: Equatable {
    case deviceUpload
    case dashboardRefresh
}

struct BandBatteryBadge: View {
    let isApplyingSyncUpdate: Bool
    let showsSyncUpdated: Bool
    let syncIssue: NoomBandSyncIssue?

    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var battery: Int? = sensorBio.batteryLevel
    @State private var charging: Bool? = sensorBio.charging
    @State private var syncing: Bool = sensorBio.deviceSyncing
    @State private var percentSynced: Int = sensorBio.percentSynced

    var body: some View {
        Group {
            if haveDevice {
                statusContent
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(connected ? NoomTheme.logoBlack : NoomTheme.muted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(statusBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityStatus)
                    .animation(.snappy, value: syncing)
                    .animation(.snappy, value: isApplyingSyncUpdate)
                    .animation(.snappy, value: showsSyncUpdated)
                    .animation(.snappy, value: syncIssue)
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$batteryLevel) { battery = $0 }
        .onReceive(sensorBio.$charging) { charging = $0 }
        .onReceive(sensorBio.$deviceSyncing) { syncing = $0 }
        .onReceive(sensorBio.$percentSynced) { percentSynced = $0 }
    }

    @ViewBuilder
    private var statusContent: some View {
        if syncing {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: syncing)
                    Text("\(clampedProgress)%")
                        .monospacedDigit()
                }
                ProgressView(value: Double(clampedProgress), total: 100)
                    .progressViewStyle(.linear)
                    .tint(NoomTheme.red)
            }
            .frame(width: 64)
        } else if isApplyingSyncUpdate {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini).tint(NoomTheme.red)
                Text("Updating")
            }
        } else if showsSyncUpdated {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NoomTheme.metricGreen)
                Text("Updated")
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: batteryIcon())
                    if connected {
                        Text(battery.map { "\($0)%" } ?? "Live")
                        if charging == true { Image(systemName: "bolt.fill") }
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        Text("Offline")
                    }
                }
                if let issue = syncIssue {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(issue == .deviceUpload ? "Sync issue" : "Data issue")
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.red)
                }
            }
        }
    }

    private var clampedProgress: Int { min(max(percentSynced, 0), 100) }

    private var statusBackground: Color {
        if syncing || isApplyingSyncUpdate { return NoomTheme.mint.opacity(0.78) }
        if showsSyncUpdated { return NoomTheme.mint.opacity(0.52) }
        if syncIssue != nil { return NoomTheme.rose.opacity(0.82) }
        return connected ? NoomTheme.red.opacity(0.12) : NoomTheme.softLine.opacity(0.72)
    }

    private var accessibilityStatus: String {
        if syncing { return "Noom Band syncing, \(clampedProgress) percent" }
        if isApplyingSyncUpdate { return "Sync finished. Updating today's dashboard" }
        if showsSyncUpdated { return "Dashboard updated with the latest Noom Band data" }
        let connectionStatus: String
        if connected, let battery {
            connectionStatus = "Noom Band connected, battery \(battery) percent"
        } else if connected {
            connectionStatus = "Noom Band connected"
        } else {
            connectionStatus = "Noom Band not connected"
        }
        guard let syncIssue else { return connectionStatus }
        let issueStatus = syncIssue == .deviceUpload
            ? "Latest data sync failed"
            : "Latest dashboard update failed"
        return "\(connectionStatus). \(issueStatus)"
    }

    private func batteryIcon() -> String {
        guard let battery else { return "battery.0percent" }
        switch battery {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// A deliberate entry point for the SDK-owned live recording flows.
/// Spot check is a fixed, guided biometrics capture; activity is open-ended.
struct RecordActivityView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case spotCheck = "Spot check"
        case activity = "Activity"
        var id: Self { self }
    }

    @State private var mode: Mode = .spotCheck
    @State private var activityName = "Walk"
    @State private var recordingState: SB_RecordingState = sensorBio.recordingState
    @State private var canFinalize = sensorBio.canFinalize
    @State private var isPaused = sensorBio.isRecordingPaused
    @State private var completionMessage: String?
    @State private var recordingTask: Task<Void, Never>?

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Record") {
                NoomPill(title: sensorBio.connected ? "Band connected" : (sensorBio.haveDevice ? "Band disconnected" : "Band needed"), color: sensorBio.connected ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
            }
            Text(isActive ? "Recording" : "Record a session")
                .noomSerifTitle(size: 38)
            Text(isActive ? recordingDetail : "Choose a guided spot check or an open-ended activity. The band handles capture, sync, and submission.")
                .noomBody()

            if isActive {
                activeRecordingCard
            } else {
                Picker("Recording type", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .activity {
                    Picker("Activity", selection: $activityName) {
                        ForEach(["Walk", "Run", "Cycle", "Strength", "Other"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                NoomCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode == .spotCheck ? "One-minute body check" : "Live activity")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(mode == .spotCheck ? "Stay still while the band captures a short biometrics sample." : "Start when you begin. Pause or finish when you are done.")
                            .noomBody()
                        Text(mode == .spotCheck ? "Requires at least 30 seconds and valid signal." : "Runs until you choose Finish.")
                            .font(.footnote)
                            .foregroundStyle(NoomTheme.muted)
                    }
                }

                Button(action: startRecording) {
                    Label(mode == .spotCheck ? "Start spot check" : "Start activity", systemImage: mode == .spotCheck ? "waveform.path.ecg" : "figure.run")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NoomTheme.red)
                .disabled(!sensorBio.connected || recordingTask != nil)

                if !sensorBio.connected {
                    NavigationLink { NoomBandSetupEntryView() } label: {
                        Label(sensorBio.haveDevice ? "Reconnect Noom Band" : "Set up Noom Band", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Text(sensorBio.haveDevice ? "Your paired band is disconnected. Reconnect it before starting a recording." : "Set up and connect a Noom Band before starting a recording.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let completionMessage {
                NoomCard {
                    Label(completionMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NoomTheme.logoBlack)
                }
            }
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(sensorBio.$recordingState) { recordingState = $0 }
        .onReceive(sensorBio.$canFinalize) { canFinalize = $0 }
        .onReceive(sensorBio.$isRecordingPaused) { isPaused = $0 }
        .onAppear { resumePersistedRecordingIfNeeded() }
        .onDisappear { recordingTask?.cancel() }
    }

    @ViewBuilder
    private var activeRecordingCard: some View {
        NoomCard {
            VStack(spacing: 16) {
                Text(timerText)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(isPaused ? "Paused" : recordingDetail)
                    .noomBody()
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    if mode == .activity, !isFinalizing {
                        Button(isPaused ? "Resume" : "Pause") {
                            if isPaused { sensorBio.resumeRecording() } else { sensorBio.pauseRecording() }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Finish") { sensorBio.finishCurrentRecording() }
                        .buttonStyle(.borderedProminent)
                        .tint(NoomTheme.red)
                        .disabled(!canFinalize || isFinalizing)
                }
                if !canFinalize && !isFinalizing {
                    Text("Finish becomes available after the minimum duration and a valid heart-rate sample.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var isActive: Bool {
        if case .idle = recordingState { return false }
        return true
    }

    private var isFinalizing: Bool {
        if case .finalizing = recordingState { return true }
        return false
    }

    private var elapsed: TimeInterval {
        if case let .recording(value, _) = recordingState { return value }
        return 0
    }

    private var timerText: String {
        let seconds = Int(elapsed.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var recordingDetail: String {
        switch recordingState {
        case let .recording(_, target):
            return target == nil ? "Activity is recording" : "Spot check is recording"
        case let .finalizing(phase):
            return "Finishing: \(phase.rawValue)"
        case .idle:
            return ""
        @unknown default:
            return "Recording status unavailable"
        }
    }

    private func startRecording() {
        completionMessage = nil
        recordingTask = Task {
            do {
                switch mode {
                case .spotCheck:
                    try await sensorBio.recordDetailedBiometrics(duration: 60, minDuration: 30)
                case .activity:
                    try await sensorBio.recordActivity(activityName: activityName, minDuration: 30)
                }
                completionMessage = "Recording saved and queued for sync."
            } catch is CancellationError {
                return
            } catch {
                completionMessage = error.localizedDescription
            }
            recordingTask = nil
        }
    }

    private func resumePersistedRecordingIfNeeded() {
        guard sensorBio.activeRecording != nil, recordingTask == nil else { return }
        recordingTask = Task {
            do {
                try await sensorBio.awaitActiveRecordingCompletion()
                completionMessage = "Recording saved and queued for sync."
            } catch is CancellationError {
                return
            } catch {
                completionMessage = error.localizedDescription
            }
            recordingTask = nil
        }
    }
}
