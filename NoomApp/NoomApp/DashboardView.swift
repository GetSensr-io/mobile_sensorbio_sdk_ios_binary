import SwiftUI
import SensorBioSDK

struct DashboardView: View {
    let session: SB_Session

    @Environment(AppDateContext.self) private var dateContext
    @State private var dashboard = DashboardState()
    @State private var productLoop = ProductLoopStore()
    @State private var postSyncRefreshTask: Task<Void, Never>?
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
                    NavigationLink { RecordActivityView() } label: {
                        Image(systemName: "record.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(NoomTheme.logoBlack)
                            .frame(width: 36, height: 36)
                            .background(NoomTheme.softLine.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Record activity or spot check")
                    BandBatteryBadge()
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
                deviceCard
            } else {
                noDataCard
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DatePicker("Date", selection: $ctx.selectedDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .tint(NoomTheme.red)
            }
        }
        .task(id: dateContext.selectedDate) { await refreshDashboard() }
        .refreshable { await refreshDashboard() }
        .onReceive(sensorBio.$lastSyncd.dropFirst()) { _ in
            guard Calendar.current.isDateInToday(dateContext.selectedDate) else { return }
            postSyncRefreshTask?.cancel()
            postSyncRefreshTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await refreshDashboard()
            }
        }
        .onReceive(sensorBio.$haveDevice) { bandState = .live(paired: $0, connected: sensorBio.connected) }
        .onReceive(sensorBio.$connected) { bandState = .live(paired: sensorBio.haveDevice, connected: $0) }
    }

    private func refreshDashboard() async {
        await dashboard.load(date: dateContext.selectedDate)
        await productLoop.load()
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
                    NoomDetailValueRow(label: "Coverage", value: status.coverageDescription, verticalPadding: 8)
                    NoomDetailValueRow(label: "Method", value: status.methodDescription, verticalPadding: 8)
                }
            }
        }
        } else {
            NoomEmptyStateCard(
                title: "Body Status unavailable",
                message: "Wear Noom Band overnight and sync to calculate Body Status from available overnight signals.",
                systemImage: "heart.text.square"
            )
        }
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
        if dashboard.nightlySleep == nil || data.metrics.isEmpty {
            NoomStateBanner(title: "Partial data", detail: "Body Status needs one completed sleep with resting HR, nocturnal HRV, and a sleep score.", systemImage: "chart.bar.doc.horizontal", tint: NoomTheme.mint)
        }
    }

    @ViewBuilder
    private var persistentExperimentSection: some View {
        if let active = productLoop.activeExperiment {
            experimentCard(active, label: "Active") {
                HStack(spacing: 10) {
                    Button("Complete") { Task { await productLoop.complete(active) } }
                        .buttonStyle(NoomPrimaryButtonStyle())
                    Button("Cancel") { Task { await productLoop.cancel(active) } }
                        .buttonStyle(NoomSecondaryButtonStyle())
                }
            }
        } else if let proposal = productLoop.proposedExperiment {
            experimentCard(proposal, label: "Suggested") {
                HStack(spacing: 10) {
                    Button("Start experiment") { Task { await productLoop.accept(proposal) } }
                        .buttonStyle(NoomPrimaryButtonStyle())
                    Button("Not now") { Task { await productLoop.cancel(proposal) } }
                        .buttonStyle(NoomSecondaryButtonStyle())
                }
            }
        } else {
            let suggestion = ProductLoopSuggestion.eveningReset
            NoomCard(fill: Color.white.opacity(0.84)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Suggested experiment").noomSerifTitle(size: 26)
                        Spacer()
                        NoomPill(title: "3 nights", color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                    }
                    Text(suggestion.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                    Text(suggestion.reason).noomBody()
                    Text(suggestion.instructions).noomBody()
                    Button("Save this experiment") { Task { await productLoop.propose(suggestion) } }
                        .buttonStyle(NoomPrimaryButtonStyle())
                        .disabled(productLoop.isSaving)
                }
            }
        }
        if let error = productLoop.errorMessage {
            NoomStateBanner(title: "Experiment sync unavailable", detail: error, systemImage: "arrow.triangle.2.circlepath", tint: NoomTheme.rose)
        }
    }

    private func experimentCard<Actions: View>(_ experiment: ProductLoopExperiment, label: String, @ViewBuilder actions: () -> Actions) -> some View {
        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Suggested experiment").noomSerifTitle(size: 26)
                    Spacer()
                    NoomPill(title: label, color: NoomTheme.ink)
                }
                Text(experiment.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                Text(experiment.reason).noomBody()
                Text(experiment.instructions).noomBody()
                actions().disabled(productLoop.isSaving)
            }
        }
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
        if let sleep = data.sleep {
            NavigationLink { SleepDetailView() } label: {
                NoomCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sleep").noomLabel()
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatNumber(sleep.item.value)).noomSerifTitle(size: 34)
                            Spacer()
                            if sleep.durationSeconds > 0 {
                                Text(duration(seconds: sleep.durationSeconds)).noomBody()
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            metricRouteTile(label: "Sleep", metric: nil, destination: SleepDetailView())
        }

        let metricsByType = Dictionary(grouping: data.metrics, by: \.metricType).compactMapValues(\.first)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
            InflammationSignalDetailView(signal: dashboard.inflammationSignal)
        } label: {
            NoomMetricTile(
                label: "Inflammation signal",
                value: inflammationSignalValue,
                caption: dashboard.inflammationSignal.status.isUsable ? "Daily overnight signal" : "Source integration pending",
                minHeight: 104
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inflammation signal, \(inflammationSignalValue)")
    }

    private func metricRouteTile<Destination: View>(label: String, metric: SB_DashboardMetric? = nil, destination: Destination) -> some View {
        NavigationLink { destination } label: {
            NoomMetricTile(
                label: label,
                value: metric.map(metricValue) ?? "Open",
                caption: metric.map(metricFooter).flatMap { $0.isEmpty ? nil : $0 } ?? "Details",
                minHeight: 104
            )
        }
        .buttonStyle(.plain)
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
        NoomCard {
            HStack(spacing: 12) {
                ProgressView().tint(NoomTheme.red)
                Text("Loading today's data").noomBody()
            }
        }
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
            deviceCard
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

    private func metricValue(_ metric: SB_DashboardMetric) -> String {
        let number: String
        if metric.valueFloat != 0 {
            number = formatNumber(metric.valueFloat)
        } else {
            number = MetricFormatting.humanNumber(metric.value)
        }
        guard let unit = metric.valueUnit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }

    private func metricFooter(_ metric: SB_DashboardMetric) -> String {
        switch metric.footer {
        case .avgValue(let value): return "Average \(formatNumber(value))"
        case .improvementVsBaseline(let value): return "\(formatNumber(value)) vs baseline"
        case .unset: return ""
        @unknown default: return ""
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
