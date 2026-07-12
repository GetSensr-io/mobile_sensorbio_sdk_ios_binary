import SwiftUI
import SensorBioSDK
import Combine

struct DashboardView: View {
    let session: SB_Session
    let dashboard: DashboardState
    let productLoop: ProductLoopStore

    @Environment(AppDateContext.self) private var dateContext
    @State private var postSyncRefreshTask: Task<Void, Never>?
    @State private var activeSyncRefreshID: UUID?
    @State private var lastSyncRefreshStartedAt: Date?
    @State private var isApplyingSyncUpdate = false
    @State private var showsSyncUpdated = false
    @State private var syncIssue: NoomBandSyncIssue?
    @State private var experimentDragOffset: CGFloat = 0
    @AppStorage("dismissedNoomExperimentKey") private var dismissedNoomExperimentKey = ""
    @State private var bandState = NoomBandConnectionState.live(
        paired: sensorBio.haveDevice,
        connected: sensorBio.connected
    )

    var body: some View {
        @Bindable var ctx = dateContext
        NoomScreen {
            HStack(alignment: .center, spacing: 12) {
                NoomLogoPlate(compact: true)
                    .accessibilityLabel("Noom plus")
                Spacer()
                HStack(spacing: 8) {
                    BandBatteryBadge(
                        isApplyingSyncUpdate: isApplyingSyncUpdate,
                        showsSyncUpdated: showsSyncUpdated,
                        syncIssue: syncIssue
                    )
                    NavigationLink {
                        ProfileView(session: session)
                    } label: {
                        ZStack {
                            Circle().fill(NoomTheme.ink).frame(width: 36, height: 36)
                            Text(initials(from: session.username))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile")
                }
            }

            NoomDayNavigator(selection: $ctx.selectedDate)

            if !bandState.isLiveReady {
                NavigationLink { NoomBandSetupEntryView() } label: {
                    NoomBandConnectionBanner(state: bandState)
                }
                .buttonStyle(.plain)
            }

            if dashboard.isLoading && dashboard.data == nil {
                loadingCard
            } else if let data = dashboard.data {
                dataStateBanner(for: data)
                bodyStatusSection
                persistentExperimentSection
                progressPreviewSection
                dashboardMetrics(data)
                if let insight = data.insights.first(where: { !$0.title.isEmpty || !$0.description.isEmpty }) {
                    insightCard(insight)
                }
                if bandState.isLiveReady { deviceCard }
            } else {
                noDataCard
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NavigationLink { RecordActivityView() } label: {
                NoomRecordingFloatingButton()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record a session")
            .accessibilityHint("Choose a spot check or activity tracking")
            .padding(.trailing, NoomTheme.horizontalPadding)
            .padding(.bottom, 14)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: dateContext.selectedDate) { await refreshDashboard() }
        .refreshable { await refreshDashboardFromUser() }
        .onReceive(sensorBio.sleepStored.merge(with: sensorBio.sleepUploaded)) { _ in
            refreshAfterSync()
        }
        .onReceive(sensorBio.syncCompleted) { result in
            guard result?.acknowledge == true else {
                markSyncRefreshFailed()
                return
            }
            refreshAfterSync(bypassThrottle: true)
        }
        .onReceive(sensorBio.$lastSyncd.dropFirst()) { _ in
            refreshAfterSync()
        }
        .onReceive(sensorBio.$deviceSyncing) { isSyncing in
            if isSyncing {
                syncIssue = nil
                showsSyncUpdated = false
            }
        }
        .onReceive(sensorBio.$haveDevice) { bandState = .live(paired: $0, connected: sensorBio.connected) }
        .onReceive(sensorBio.$connected) { bandState = .live(paired: sensorBio.haveDevice, connected: $0) }
    }

    private func refreshDashboard(force: Bool = false) async {
        await dashboard.load(date: dateContext.selectedDate, force: force)
        await productLoop.load()
    }

    private func refreshDashboardFromUser() async {
        await refreshDashboard(force: true)
        if syncIssue == .dashboardRefresh, dashboard.errorMessage == nil {
            syncIssue = nil
        }
    }

    /// BLE sync is SDK-owned. Once it reports completion, bypass both the
    /// app's one-minute dedupe and the SDK v0.13 cache immediately. A quiet
    /// follow-up catches sleep/recovery scores that finish server-side moments
    /// after the packet upload without making the user pull to refresh.
    private func refreshAfterSync(bypassThrottle: Bool = false) {
        guard Calendar.current.isDateInToday(dateContext.selectedDate) else { return }
        let now = Date()
        if !bypassThrottle,
           let lastSyncRefreshStartedAt,
           now.timeIntervalSince(lastSyncRefreshStartedAt) < 5 {
            return
        }
        lastSyncRefreshStartedAt = now
        let refreshID = UUID()
        activeSyncRefreshID = refreshID
        isApplyingSyncUpdate = true
        showsSyncUpdated = false
        syncIssue = nil
        postSyncRefreshTask?.cancel()
        postSyncRefreshTask = Task { @MainActor in
            await refreshDashboard(force: true)
            guard activeSyncRefreshID == refreshID, !Task.isCancelled else { return }
            isApplyingSyncUpdate = false
            guard dashboard.errorMessage == nil else {
                syncIssue = .dashboardRefresh
                return
            }
            showsSyncUpdated = true

            do { try await Task.sleep(nanoseconds: 2_400_000_000) }
            catch { return }
            guard activeSyncRefreshID == refreshID else { return }
            showsSyncUpdated = false

            do { try await Task.sleep(nanoseconds: 9_600_000_000) }
            catch { return }
            guard activeSyncRefreshID == refreshID else { return }
            await refreshDashboard(force: true)
        }
    }

    private func markSyncRefreshFailed() {
        postSyncRefreshTask?.cancel()
        activeSyncRefreshID = UUID()
        isApplyingSyncUpdate = false
        showsSyncUpdated = false
        syncIssue = .deviceUpload
    }

    @ViewBuilder
    private var bodyStatusSection: some View {
        if let nightlySleep = dashboard.nightlySleep,
           let status = BodyStatusScore.make(
             restingHeartRate: Int(nightlySleep.restingHr),
             nocturnalHRV: Int(nightlySleep.restingHrv),
             sleepScore: Int(nightlySleep.sleepScore.score),
             inflammationSignal: dashboard.inflammationSignal
           ) {
            let freshness = dashboard.freshness(for: dateContext.selectedDate)
            VStack(spacing: 12) {
                NoomCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 18) {
                            ZStack {
                                Circle().stroke(NoomTheme.softLine.opacity(0.72), lineWidth: 14)
                                Circle()
                                    .trim(from: 0, to: CGFloat(status.score) / 100)
                                    .stroke(freshness.isStaleCurrentDay ? NoomTheme.muted : NoomTheme.red, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text(MetricFormatting.humanNumber(status.score))
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(NoomTheme.logoBlack)
                            }
                            .frame(width: 128, height: 128)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Body Status").noomSerifTitle(size: 30)
                                Text(status.summary).noomBody()
                                HStack(spacing: 8) {
                                    NoomPill(title: status.stage, color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                                    NoomPill(title: freshnessPillTitle(freshness), color: freshnessPillColor(freshness), foreground: NoomTheme.logoBlack)
                                }
                            }
                        }

                        VStack(spacing: 0) {
                            NoomDetailValueRow(label: "Resting HR", value: "\(MetricFormatting.humanNumber(Int(nightlySleep.restingHr))) bpm", verticalPadding: 8)
                            NoomDetailValueRow(label: "Nocturnal HRV", value: "\(MetricFormatting.humanNumber(Int(nightlySleep.restingHrv))) ms", verticalPadding: 8)
                            NoomDetailValueRow(label: "Sleep score", value: "\(MetricFormatting.humanNumber(Int(nightlySleep.sleepScore.score))) / 100", verticalPadding: 8)
                            NoomDetailValueRow(label: "Inflammation signal", value: inflammationSignalValue, verticalPadding: 8)
                        }
                    }
                }
            }
        } else {
            if shouldShowFirstBodyStatus {
                NoomFirstNightCard(
                    title: "Your first Body Status starts tonight",
                    message: "Wear Noom Band overnight. After your morning sync, sleep, resting heart rate, HRV, and your available overnight signal come together here.",
                    bandReady: bandState.isLiveReady
                )
            } else {
                NoomEmptyStateCard(
                    title: "Body Status unavailable",
                    message: dashboard.errorMessage ?? (Calendar.current.isDateInToday(dateContext.selectedDate)
                        ? "No completed overnight session was returned for today. Your last useful dashboard values remain available while Noom checks again."
                        : "No completed overnight session was returned for this date."),
                    systemImage: "heart.text.square"
                )
            }
        }
    }

    private var shouldShowFirstBodyStatus: Bool {
        Calendar.current.isDateInToday(dateContext.selectedDate) &&
        !NoomSleepHistory.hasRecordedSleep(for: session.userId) &&
        dashboard.errorMessage == nil
    }

    private var inflammationSignalValue: String {
        guard let score = dashboard.inflammationSignal.validScore else {
            return dashboard.inflammationSignal.status.label
        }
        return "\(MetricFormatting.humanNumber(score)) / 100"
    }

    @ViewBuilder
    private func dataStateBanner(for data: SB_DashboardData) -> some View {
        let freshness = dashboard.freshness(for: dateContext.selectedDate)
        if !dashboard.networkStatus.isReachable && dashboard.errorMessage == nil {
            NoomStateBanner(title: "Offline", detail: "Showing only data returned by the local SDK cache. Today is not labeled current without a fresh sync.", systemImage: "wifi.slash", tint: NoomTheme.rose)
        }
        if freshness.isStaleCurrentDay {
            NoomStateBanner(title: "Stale today", detail: "Last Noom Band sync was not today. This Body Status is not current.", systemImage: "clock.badge.exclamationmark", tint: NoomTheme.rose)
        }
        if dashboard.nightlySleep != nil && data.metrics.isEmpty {
            NoomStateBanner(title: "Still filling in", detail: "Your overnight story is here. A few daytime metrics are still on their way.", systemImage: "chart.bar.doc.horizontal", tint: NoomTheme.mint)
        }
    }

    @ViewBuilder
    private var persistentExperimentSection: some View {
        if let active = productLoop.activeExperiment {
            experimentCard(active, label: "Active", onDismiss: {
                Task { await productLoop.cancel(active) }
            }) {
                HStack(spacing: 10) {
                    Button("Complete") { Task { await productLoop.complete(active) } }
                        .buttonStyle(NoomPrimaryButtonStyle())
                    Button("Cancel") { Task { await productLoop.cancel(active) } }
                        .buttonStyle(NoomSecondaryButtonStyle())
                }
            }
        } else {
            let suggestion = ProductLoopSuggestion.prelogLunch
            if dismissedNoomExperimentKey != experimentDismissalKey(suggestion) {
                persistentSuggestionCard(suggestion, proposal: productLoop.proposedExperiment)
            }
        }
    }

    private func persistentSuggestionCard(_ suggestion: ProductLoopSuggestion, proposal: ProductLoopExperiment?) -> some View {
        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Suggested experiment").noomSerifTitle(size: 24)
                    Spacer(minLength: 8)
                    NoomPill(title: "3 days", color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                    experimentDismissButton {
                        dismissExperiment {
                            dismissedNoomExperimentKey = experimentDismissalKey(suggestion)
                            if let proposal { Task { await productLoop.cancel(proposal) } }
                        }
                    }
                }
                Text(suggestion.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                Text(suggestion.reason).noomBody()
                Text(suggestion.instructions).noomBody()
                if let error = productLoop.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoomTheme.rose.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button {
                    Task { await productLoop.start(suggestion) }
                } label: {
                    HStack(spacing: 8) {
                        if productLoop.isSaving { ProgressView().tint(.white) }
                        Text(productLoop.isSaving ? "Starting…" : "Start experiment")
                    }
                }
                .buttonStyle(NoomPrimaryButtonStyle())
                .disabled(productLoop.isSaving)
            }
        }
        .offset(x: experimentDragOffset)
        .opacity(max(0.35, 1 - abs(experimentDragOffset) / 280))
        .simultaneousGesture(experimentDismissGesture {
            dismissedNoomExperimentKey = experimentDismissalKey(suggestion)
            if let proposal { Task { await productLoop.cancel(proposal) } }
        })
    }

    private func experimentCard<Actions: View>(
        _ experiment: ProductLoopExperiment,
        label: String,
        onDismiss: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Suggested experiment").noomSerifTitle(size: 26)
                    Spacer()
                    NoomPill(title: label, color: NoomTheme.ink)
                    experimentDismissButton { dismissExperiment(onDismiss) }
                }
                Text(experiment.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                Text(experiment.reason).noomBody()
                Text(experiment.instructions).noomBody()
                if let error = productLoop.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoomTheme.rose.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                actions().disabled(productLoop.isSaving)
            }
        }
        .offset(x: experimentDragOffset)
        .opacity(max(0.35, 1 - abs(experimentDragOffset) / 280))
        .simultaneousGesture(experimentDismissGesture(action: onDismiss))
    }

    private func experimentDismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoomTheme.logoBlack)
                .frame(width: 32, height: 32)
                .background(NoomTheme.softLine.opacity(0.74), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss experiment")
    }

    private func experimentDismissGesture(action: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                experimentDragOffset = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(.snappy) { experimentDragOffset = 0 }
                    return
                }
                if abs(value.translation.width) > 100 {
                    dismissExperiment(action)
                } else {
                    withAnimation(.snappy) { experimentDragOffset = 0 }
                }
            }
    }

    private func dismissExperiment(_ action: @escaping () -> Void) {
        let destination: CGFloat = experimentDragOffset < 0 ? -520 : 520
        withAnimation(.snappy) { experimentDragOffset = destination }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            action()
            experimentDragOffset = 0
        }
    }

    private func experimentDismissalKey(_ suggestion: ProductLoopSuggestion) -> String {
        let start = Calendar.current.startOfDay(for: dateContext.selectedDate)
        return "\(suggestion.demoCatalogId)-\(Int(start.timeIntervalSince1970))"
    }

    @ViewBuilder
    private var suggestedExperimentSection: some View {
        if let insights = dashboard.personalInsights {
            if let exp = insights.suggestedExperiment, !exp.reason.isEmpty {
                suggestedExperimentCard(exp, fallbackRecommendation: firstItemText(from: insights.recommendations))
            } else if let recommendation = firstItemText(from: insights.recommendations) {
                NoomCard(fill: Color.white.opacity(0.84)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Personal insight").noomSerifTitle(size: 26)
                            Spacer()
                            NoomPill(title: "SDK-backed", color: NoomTheme.ink)
                        }
                        Text(recommendation).noomBody()
                        Text("No suggested experiment was returned with this insight.").noomLabel()
                    }
                }
            }
        } else if dashboard.personalInsightsError != nil {
            NoomStateBanner(title: "Insight unavailable", detail: "Personal Insights did not return a recommendation. No experiment state is invented locally.", systemImage: "sparkles", tint: NoomTheme.rose)
        }
    }

    private func suggestedExperimentCard(_ exp: SB_ExperimentRecommendation, fallbackRecommendation: String?) -> some View {
        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Suggested experiment").noomSerifTitle(size: 26)
                    Spacer()
                    NoomPill(title: "Read-only", color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }
                if !exp.methodNames.isEmpty {
                    Text(exp.methodNames.joined(separator: ", "))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                }
                Text(exp.reason).noomBody()
                if let fallbackRecommendation {
                    NoomDetailValueRow(label: "Insight", value: fallbackRecommendation, verticalPadding: 8)
                }
                Text("Experiment lifecycle is feature-gated until the backend contract is integrated. No active or completed state is stored in this app.")
                    .noomLabel()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var progressPreviewSection: some View {
        let recoveryPoints = dashboard.weeklyRecovery?.graph?.recoveryScoreSection?.scorePoints.sorted { $0.date < $1.date } ?? []
        let sleepPoints = dashboard.weeklySleep?.sleepTimePoints.sorted { $0.date < $1.date } ?? []
        if !recoveryPoints.isEmpty || !sleepPoints.isEmpty {
            NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Progress from real history").noomSerifTitle(size: 26)
                        Spacer()
                        NoomPill(title: progressCoverageTitle(recoveryPoints: recoveryPoints, sleepPoints: sleepPoints), color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                    }
                    Text("Only returned sleep and Recovery dates are shown. Missing dates are discontinuous, and no causal score is computed.").noomBody()
                    if !recoveryPoints.isEmpty {
                        NoomDiscontinuousPointTrend(points: recoveryPoints, valueFormatter: { MetricFormatting.humanNumber(Int($0)) }, tint: NoomTheme.red)
                    }
                    if !sleepPoints.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(sleepPoints.prefix(4), id: \.date) { point in
                                NoomDetailValueRow(label: MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: .week), value: duration(seconds: Int(point.value)), verticalPadding: 8)
                            }
                        }
                    }
                    NavigationLink { NoomProgressSignalsView() } label: {
                        Text("Open progress details")
                    }
                    .buttonStyle(NoomSecondaryButtonStyle())
                }
            }
        } else if dashboard.progressError != nil {
            NoomStateBanner(title: "Progress unavailable", detail: "Recovery and sleep history did not load. The app does not fill gaps with sample data.", systemImage: "chart.xyaxis.line", tint: NoomTheme.rose)
        }
    }

    @ViewBuilder
    private func dashboardMetrics(_ data: SB_DashboardData) -> some View {
        NavigationLink { SleepDetailView() } label: {
            if let sleep = data.sleep {
                NoomDashboardMetricTile(
                    label: "Sleep",
                    value: formatNumber(sleep.item.value),
                    unit: "/100",
                    caption: sleep.durationSeconds > 0 ? "\(duration(seconds: sleep.durationSeconds)) asleep" : "View sleep details",
                    systemImage: "moon.stars.fill",
                    accent: NoomTheme.metricPurple,
                    minHeight: 132,
                    prominent: true
                )
            } else {
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
        }
        .buttonStyle(.plain)

        let metricsByType = Dictionary(grouping: data.metrics, by: \.metricType).compactMapValues(\.first)
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            metricRouteTile(label: "Steps", metric: metricsByType[.stepDashMetric], destination: StepsDetailView())
            metricRouteTile(label: "Active Calories", metric: metricsByType[.calorieDashMetric], destination: CaloriesDetailView())
            metricRouteTile(label: "Resting Heart Rate", metric: metricsByType[.hrDashMetric], destination: HRDetailView())
            metricRouteTile(label: "Heart Rate Variability", metric: metricsByType[.hrvDashMetric], destination: HRVDetailView())
            metricRouteTile(label: "Respiratory Rate", metric: metricsByType[.respRateDashMetric], destination: RRDetailView())
            inflammationMetricTile
        }
    }

    private var inflammationMetricTile: some View {
        NavigationLink {
            InflammationSignalDetailView(
                signal: dashboard.inflammationSignal,
                historicalValues: MockInflammationSignalProvider().trailingValues(before: dashboard.inflammationSignal.completedDate)
            )
        } label: {
            NoomDashboardMetricTile(
                label: "Inflammation Signal",
                value: dashboard.inflammationSignal.validScore.map(MetricFormatting.humanNumber) ?? dashboard.inflammationSignal.status.label,
                unit: dashboard.inflammationSignal.validScore == nil ? nil : "/100",
                caption: dashboard.inflammationSignal.isPreview ? "Sample overnight input" : (dashboard.inflammationSignal.status.isUsable ? "Daily overnight signal" : "Source integration pending"),
                systemImage: "waveform.path.ecg.rectangle",
                accent: NoomTheme.red
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inflammation signal, \(inflammationSignalValue)\(dashboard.inflammationSignal.isPreview ? ", sample data, not personal health data" : "")")
    }

    private func metricRouteTile<Destination: View>(label: String, metric: SB_DashboardMetric? = nil, destination: Destination) -> some View {
        NavigationLink { destination } label: {
            NoomDashboardMetricTile(
                label: label,
                value: metric.map(dashboardMetricNumber) ?? "—",
                unit: metric.flatMap(dashboardMetricUnit),
                caption: metric.map(metricFooter).flatMap { $0.isEmpty ? nil : $0 } ?? missingMetricCaption(for: label),
                systemImage: dashboardMetricIcon(for: label),
                accent: dashboardMetricAccent(for: label)
            )
        }
        .buttonStyle(.plain)
    }

    private func missingMetricCaption(for label: String) -> String {
        switch label {
        case "Steps": return "Take a few steps to get rolling"
        case "Active Calories": return "Move a little to light this up"
        case "Resting Heart Rate": return "One overnight read unlocks this"
        case "Heart Rate Variability": return "Your overnight rhythm will land here"
        case "Respiratory Rate": return "Wear Noom Band tonight to unlock"
        default: return "Your next sync will fill this in"
        }
    }

    private func insightCard(_ insight: SB_DashboardInsight) -> some View {
        NoomCard {
            VStack(alignment: .leading, spacing: 9) {
                if !insight.title.isEmpty { Text(insight.title).noomSerifTitle(size: 26) }
                if !insight.description.isEmpty { Text(insight.description).noomBody() }
            }
        }
    }

    private var deviceCard: some View {
        NavigationLink { NoomBandSetupEntryView() } label: {
            NoomCard {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(NoomTheme.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Noom Band").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                        Text(bandState.detail).noomBody()
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(NoomTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var loadingCard: some View {
        NoomLoadingExperience(
            title: "Bringing today into focus",
            detail: "Gathering sleep, movement, and overnight signals without clearing your last useful view.",
            systemImage: "sun.max.fill",
            accent: NoomTheme.red
        )
    }

    private var noDataCard: some View {
        VStack(spacing: 12) {
            NoomEmptyStateCard(
                title: noDataTitle,
                message: noDataMessage,
                systemImage: dashboard.networkStatus.isReachable ? "chart.bar.xaxis" : "wifi.slash"
            )
            if dashboard.errorMessage != nil {
                Button("Try again") { Task { await dashboard.load(date: dateContext.selectedDate) } }
                    .buttonStyle(NoomPrimaryButtonStyle())
            }
            if bandState.isLiveReady { deviceCard }
        }
    }

    private var noDataTitle: String {
        dashboard.networkStatus.isReachable ? "No data for this day" : "Offline or unavailable"
    }

    private var noDataMessage: String {
        if dashboard.errorMessage != nil && !dashboard.networkStatus.isReachable {
            return "No local SDK data was returned while offline. Connect and sync Noom Band to refresh."
        }
        return dashboard.errorMessage == nil ? "Wear Noom Band and sync to see available sleep, Recovery, and movement data." : "We couldn't load this day. Try again."
    }

    private func dashboardMetricNumber(_ metric: SB_DashboardMetric) -> String {
        if metric.valueFloat != 0 {
            return formatNumber(metric.valueFloat)
        }
        return MetricFormatting.humanNumber(metric.value)
    }

    private func dashboardMetricUnit(_ metric: SB_DashboardMetric) -> String? {
        guard let rawUnit = metric.valueUnit?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUnit.isEmpty else {
            return nil
        }
        switch rawUnit.lowercased() {
        case "bpm": return "bpm"
        case "ms": return "ms"
        case "/min", "brpm": return "/min"
        case "kcal": return "kcal"
        default: return rawUnit
        }
    }

    private func metricFooter(_ metric: SB_DashboardMetric) -> String {
        switch metric.footer {
        case .avgValue(let value):
            return "Average \(formatNumber(value))"
        case .improvementVsBaseline(let value):
            guard abs(value) >= 0.05 else { return "At baseline" }
            let sign = value > 0 ? "+" : ""
            if let unit = dashboardMetricUnit(metric) {
                return "\(sign)\(formatNumber(value)) \(unit) vs baseline"
            }
            return "\(sign)\(formatNumber(value)) vs baseline"
        case .unset:
            return ""
        @unknown default:
            return ""
        }
    }

    private func dashboardMetricIcon(for label: String) -> String {
        switch label {
        case "Steps": return "figure.walk"
        case "Active Calories": return "flame.fill"
        case "Resting Heart Rate": return "heart.fill"
        case "Heart Rate Variability": return "waveform.path.ecg"
        case "Respiratory Rate": return "lungs.fill"
        default: return "chart.xyaxis.line"
        }
    }

    private func dashboardMetricAccent(for label: String) -> Color {
        switch label {
        case "Steps": return NoomTheme.metricGreen
        case "Active Calories": return NoomTheme.metricAmber
        case "Resting Heart Rate": return NoomTheme.red
        case "Heart Rate Variability": return NoomTheme.metricPurple
        case "Respiratory Rate": return NoomTheme.metricBlue
        default: return NoomTheme.ink
        }
    }

    private func recoveryStageLabel(_ stage: SB_DashboardItemRecoveryStage) -> String {
        switch stage {
        case .restUp: return "Rest up"
        case .goEasy: return "Go easy"
        case .recovered: return "Recovered"
        case .medium: return "Medium"
        case .ready: return "Ready"
        case .excellent: return "Excellent"
        case .mentallyFit: return "Mentally fit"
        case .unknown: return "Status unknown"
        @unknown default: return "Status unknown"
        }
    }

    private func coverageText(_ calibration: SB_RecoveryCalibrationData?) -> String {
        guard let calibration, calibration.totalSegments > 0 else {
            return "Not returned"
        }
        return "\(calibration.segmentsUsed)/\(calibration.totalSegments) segments"
    }

    private func freshnessPillTitle(_ freshness: NoomDataFreshness) -> String {
        switch freshness {
        case .fresh: return "Fresh"
        case .stale, .unknownCurrentDay: return "Stale"
        case .historical: return "Historical"
        }
    }

    private func freshnessPillColor(_ freshness: NoomDataFreshness) -> Color {
        freshness.isStaleCurrentDay ? NoomTheme.rose : NoomTheme.mint
    }

    private func freshnessDetail(_ freshness: NoomDataFreshness) -> String {
        switch freshness {
        case .fresh(let lastSync): return "Synced " + lastSync.formatted(.dateTime.hour().minute())
        case .stale(let lastSync): return "Last sync " + lastSync.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        case .historical(let date): return "Viewing " + date.formatted(.dateTime.month(.abbreviated).day().year())
        case .unknownCurrentDay: return "No sync timestamp returned"
        }
    }

    private func firstItemText(from groups: [SB_InsightItemGroup]) -> String? {
        for group in groups {
            if let item = group.items.first {
                if !item.extraData.isEmpty { return item.extraData }
                if !item.name.isEmpty { return item.name }
            }
        }
        return nil
    }

    private func progressCoverageTitle(recoveryPoints: [SB_DateValuePoint], sleepPoints: [SB_DateValuePoint]) -> String {
        let count = max(recoveryPoints.count, sleepPoints.count)
        switch count {
        case 5...: return "Coverage \(count)/7"
        case 1...: return "Partial \(count)/7"
        default: return "No coverage"
        }
    }

    private func formatNumber(_ value: Float) -> String {
        MetricFormatting.humanNumber(value)
    }

    private func duration(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }

    private func initials(from username: String) -> String {
        username.first.map { String($0).uppercased() } ?? "N"
    }

    private func formattedDate(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.wide).day())
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}

// Mobbin reference: Oura iOS User Dashboard date hierarchy and compact day navigation.
// https://mobbin.com/explore/screens/c659bd1e-9301-4281-a238-422ceaff9e71
struct NoomDayNavigator: View {
    @Binding var selection: Date
    @State private var showsCalendar = false

    private var isToday: Bool { Calendar.current.isDateInToday(selection) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : selection.formatted(.dateTime.weekday(.wide)))
                    .noomSerifTitle(size: 30)
                Text(selection.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoomTheme.muted)
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Button(action: previousDay) {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("Previous day")

                Button { showsCalendar = true } label: {
                    Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.84), in: Circle())
                    .overlay { Circle().stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1) }
                }
                .accessibilityLabel("Choose date")

                Button(action: nextDay) {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 38)
                }
                .disabled(Calendar.current.isDateInToday(selection))
                .accessibilityLabel("Next day")
            }
            .buttonStyle(.plain)
            .foregroundStyle(NoomTheme.logoBlack)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width > 50 {
                        previousDay()
                    } else if value.translation.width < -50 && !isToday {
                        nextDay()
                    }
                }
        )
        .sheet(isPresented: $showsCalendar) {
            NavigationStack {
                DatePicker("Choose date", selection: $selection, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(NoomTheme.red)
                    .padding()
                    .navigationTitle("Choose a day")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsCalendar = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private func previousDay() {
        guard let day = Calendar.current.date(byAdding: .day, value: -1, to: selection) else { return }
        withAnimation(.snappy) { selection = day }
    }

    private func nextDay() {
        guard !isToday,
              let day = Calendar.current.date(byAdding: .day, value: 1, to: selection) else { return }
        withAnimation(.snappy) { selection = min(day, Date()) }
    }
}

struct NoomBandConnectionBanner: View {
    let state: NoomBandConnectionState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state == .connecting ? "arrow.triangle.2.circlepath" : "wave.3.right.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(NoomTheme.logoBlack)
                .frame(width: 42, height: 42)
                .background(NoomTheme.rose, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                switch state {
                case .neverPaired:
                    Text("Connect your Noom Band")
                    Text("Add sleep, movement, and overnight context to Today.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                case .pairedDisconnected, .error:
                    Text("Reconnect your Noom Band")
                    Text("Your band is paired but offline. Reconnect to sync the latest data.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                case .connecting:
                    Text("Connecting your Noom Band")
                    Text("Keep the band nearby while Noom restores the connection.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                case .connected:
                    EmptyView()
                }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(14)
        .background(NoomTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(state.callToAction)
    }
}

struct NoomStateBanner: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        NoomCard(fill: tint.opacity(0.30), padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NoomTheme.logoBlack)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.58), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Text(detail).noomBody()
                }
            }
        }
    }
}

struct NoomDiscontinuousPointTrend: View {
    let points: [SB_DateValuePoint]
    let valueFormatter: (Float) -> String
    var tint: Color

    private var maximum: Double { max(points.map { Double($0.value) }.max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(points.prefix(7), id: \.date) { point in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(LinearGradient(colors: [tint, tint.opacity(0.34)], startPoint: .top, endPoint: .bottom))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(18, 104 * CGFloat(Double(point.value) / maximum)))
                        Text(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: .week))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(NoomTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(height: 136, alignment: .bottom)
            VStack(spacing: 0) {
                ForEach(points.prefix(4), id: \.date) { point in
                    NoomDetailValueRow(label: MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: .week), value: valueFormatter(point.value), verticalPadding: 8)
                }
            }
        }
    }
}

struct NoomSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(NoomTheme.logoBlack)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.72 : 0.92), in: Capsule())
            .overlay { Capsule().stroke(NoomTheme.ink.opacity(0.10), lineWidth: 1) }
    }
}
