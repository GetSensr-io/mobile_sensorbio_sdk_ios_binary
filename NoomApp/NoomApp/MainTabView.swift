import SwiftUI
import Foundation
import Observation
import SensorBioSDK
import Combine

struct MainTabView: View {
    let session: SB_Session
    @State private var dashboard = DashboardState()
    @State private var productLoop = ProductLoopStore()

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(session: session, dashboard: dashboard, productLoop: productLoop)
            }
                .tabItem { Label("Home", systemImage: "circle.grid.2x2.fill") }

            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "sparkles") }

            NavigationStack { NoomProgressSignalsView() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            NavigationStack { SleepHomeView() }
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
        }
        .tint(NoomTheme.red)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(NoomTheme.warmSurface, for: .tabBar)
    }
}

struct SleepHomeView: View {
    @Environment(AppDateContext.self) private var dateContext
    @Environment(SleepProcessingCoordinator.self) private var sleepProcessing
    @State private var recoveryState = SleepRecoveryHomeState()
    @State private var haveDevice = sensorBio.haveDevice
    @State private var connected = sensorBio.connected

    var body: some View {
        @Bindable var ctx = dateContext
        NoomScreen {
            NoomTopBar(label: "Sleep & Recovery") {
                NoomPill(
                    title: sleepSyncLabel,
                    color: sleepProcessing.freshness == .fresh ? NoomTheme.mint : NoomTheme.rose,
                    foreground: NoomTheme.logoBlack
                )
            }

            NoomDayNavigator(selection: $ctx.selectedDate)

            Text("Last night, in context").noomSerifTitle(size: 36)
            Text("Your latest Noom Band sleep and recovery signals, with the details one tap away.").noomBody()

            if sleepProcessing.allSessions.count > 1 {
                SleepSessionPicker(
                    sessions: sleepProcessing.allSessions,
                    selectedIdentity: sleepProcessing.selectedSession?.identity,
                    selectionReason: sleepProcessing.selectionReason,
                    onSelect: sleepProcessing.selectSession
                )
            }

            if shouldShowSleepProcessingBanner {
                SleepProcessingBanner(
                    phase: sleepProcessing.phase,
                    transportState: sleepProcessing.transport,
                    freshness: sleepProcessing.freshness,
                    selectedDate: dateContext.selectedDate,
                    sourceDate: sleepProcessing.sourceDate,
                    canRetry: sleepProcessing.canRetry,
                    retryAction: sleepProcessing.retry
                )
            }

            if sleepProcessing.transport == .loading && sleepProcessing.displaySnapshot == nil {
                loadingCard
            } else if let snapshot = sleepProcessing.displaySnapshot,
                      snapshot.outcome == .processedSuccessfully {
                completedSourceLabel(snapshot)
                sleepHeroSummary(snapshot.detail)
                atAGlanceMetrics(snapshot.detail)
                sleepStagesPreview(snapshot.detail)
                recoveryFactorsPreview(snapshot.detail)
            } else {
                noSessionCard
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dateContext.selectedDate) {
            await recoveryState.load(date: dateContext.selectedDate)
        }
        .refreshable {
            sleepProcessing.refresh(forceRemote: true)
            await recoveryState.load(date: dateContext.selectedDate, forceRemote: true)
        }
        .onChange(of: sleepProcessing.lastCompleted?.sessionIdentity) { _, _ in
            Task {
                await recoveryState.load(
                    date: dateContext.selectedDate,
                    forceRemote: true
                )
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
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
                    title: sleepEmptyTitle,
                    message: sleepEmptyMessage,
                    systemImage: sleepProcessing.transport == .failed
                        ? "exclamationmark.triangle.fill"
                        : "moon.zzz.fill"
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
        sleepProcessing.lastCompleted == nil &&
        sleepProcessing.allSessions.isEmpty &&
        sleepProcessing.phase == .idle &&
        sleepProcessing.transport != .failed
    }

    private var shouldShowSleepProcessingBanner: Bool {
        switch sleepProcessing.phase {
        case .idle, .ready:
            return sleepProcessing.transport == .failed || sleepProcessing.freshness == .stale
        case .detected, .stored, .uploaded, .processing, .calibrating,
             .retryableError, .tooShort:
            return true
        }
    }

    private var sleepSyncLabel: String {
        if sleepProcessing.phase == .processing || sleepProcessing.phase == .calibrating {
            return "Processing"
        }
        switch sleepProcessing.freshness {
        case .fresh: return "Sleep current"
        case .stale: return "Saved result"
        case .unknown: return "Checking sleep"
        }
    }

    private var sleepEmptyTitle: String {
        if sleepProcessing.transport == .failed { return "Sleep refresh unavailable" }
        if sleepProcessing.phase == .tooShort { return "Session was too short" }
        if sleepProcessing.phase == .retryableError { return "Sleep analysis needs a retry" }
        return "No sleep session for this date"
    }

    private var sleepEmptyMessage: String {
        if sleepProcessing.transport == .failed {
            return "No completed result was replaced. Connect and retry when Noom Band and the network are available."
        }
        if sleepProcessing.phase == .tooShort {
            return "The returned session was too short for a complete sleep analysis."
        }
        if sleepProcessing.phase == .retryableError {
            return "The SDK returned a processing error. Retry checks the same selected session without inventing a score."
        }
        return "No completed sleep was returned for the selected date. Try another day or sync Noom Band again."
    }

    @ViewBuilder
    private func completedSourceLabel(_ snapshot: SleepAtomicSnapshot) -> some View {
        if let sourceDate = sleepProcessing.sourceDate,
           !Calendar.current.isDate(sourceDate, inSameDayAs: dateContext.selectedDate) {
            NoomStateBanner(
                title: "Showing last completed sleep",
                detail: "This result is from \(sourceDate.formatted(.dateTime.month(.wide).day())). The selected date is still processing.",
                systemImage: "clock.arrow.circlepath",
                tint: NoomTheme.metricPurple
            )
            .accessibilityIdentifier("sleep.sourceDate")
        }
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
            if let recoveryScore = recoveryState.recoveryScore {
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
        let factors = recoveryState.recoveryFactors.isEmpty
            ? detail.scoreFactors.map { SleepHubFactor(title: $0.title, detail: $0.description) }
            : recoveryState.recoveryFactors
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
final class SleepRecoveryHomeState {
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

    private var activeRequestID: UUID?

    func load(date: Date, forceRemote: Bool = false) async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        defer {
            if activeRequestID == requestID { isLoading = false }
        }

        do {
            let recovery = try await sensorBio.fetchDailyRecovery(
                date: date,
                forceRemote: forceRemote
            )
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            dailyRecovery = recovery
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = "Recovery details are temporarily unavailable."
        }
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
                if syncIssue == .dashboardRefresh {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Data issue")
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
        if syncIssue == .dashboardRefresh { return NoomTheme.rose.opacity(0.82) }
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
        guard syncIssue == .dashboardRefresh else { return connectionStatus }
        return "\(connectionStatus). Latest dashboard update failed"
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