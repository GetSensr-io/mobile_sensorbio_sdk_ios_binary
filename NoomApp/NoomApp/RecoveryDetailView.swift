import SwiftUI
import SensorBioSDK

struct RecoveryDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_DailyRecoveryTrending?
    @State private var range: SB_RecoveryRangeTrending?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                screenHeader

                if isLoading {
                    loadingCard
                } else if isQAPreview {
                    qaDaySections
                } else if errorMessage != nil {
                    recoveryNoData(message: "Recovery data will appear after your next check-in.")
                } else if granularity == .day, let graph = daily?.graph {
                    daySections(graph)
                } else if granularity != .day, let graph = range?.graph {
                    rangeSections(graph)
                } else {
                    recoveryNoData(message: "Wear Noom Band overnight. Your recovery details appear after the next sync.")
                }
            }
            .padding(.horizontal, NoomTheme.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .noomBackground()
        .navigationTitle(Metric.recovery.title)
        .navigationBarTitleDisplayMode(.inline)
        .noomDetailBackButton()
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
        }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) {
            if !isQAPreview { await load() }
        }
    }

    private var isQAPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOOM_QA_ROUTE"] == "recovery_detail"
        #else
        false
        #endif
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery")
                .noomSerifTitle(size: 38)
            Text("A daily readiness readout from sleep, resting signals, and recent variation.")
                .noomBody()
        }
    }

    private var loadingCard: some View {
        NoomCard(fill: Color.white.opacity(0.82)) {
            HStack(spacing: 10) {
                ProgressView().tint(NoomTheme.red)
                Text("Loading...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoomTheme.muted)
            }
        }
    }

    @ViewBuilder
    private var qaDaySections: some View {
        recoveryHero(score: 76, variation: 5.4)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NoomMetricTile(label: "Resting HR", value: "58 bpm", caption: "Overnight", minHeight: 96)
            NoomMetricTile(label: "Sleep", value: "7h 34m", caption: "Last night", minHeight: 96)
            NoomMetricTile(label: "Variation", value: "+5.4%", caption: "Compared with usual", minHeight: 96)
            NoomMetricTile(label: "Readiness", value: "Supportive", caption: "Today", minHeight: 96)
        }

        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Signals")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: "Supportive", color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }
                RecoverySignalRow(label: "Recovery score", value: "76", progress: 0.76, tint: NoomTheme.ink)
                RecoverySignalRow(label: "Resting heart rate", value: "58 bpm", progress: 0.58, tint: Color(hex: 0x98C7B2))
                RecoverySignalRow(label: "Sleep time", value: "7h 34m", progress: 0.84, tint: NoomTheme.red.opacity(0.84))
            }
        }

        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score factors")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                RecoveryFactorRow(title: "Rested baseline", detail: "Sleep duration supported your morning readiness.")
                RecoveryFactorRow(title: "Lower strain", detail: "Your overnight signals suggest a steady start.")
            }
        }

        guidanceCard(score: 76)
    }

    @ViewBuilder
    private func daySections(_ graph: SB_DailyRecoveryGraph) -> some View {
        let score = Int(graph.goalItem.item.value)
        recoveryHero(score: score, variation: Double(graph.variationPercentage))

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NoomMetricTile(label: "Resting HR", value: "\(MetricFormatting.humanNumber(Int(graph.restingHr))) bpm", caption: "Overnight", minHeight: 96)
            NoomMetricTile(label: "Sleep", value: hoursMinutes(seconds: Int(graph.sleepTimeSeconds)), caption: "Last night", minHeight: 96)
            NoomMetricTile(label: "Variation", value: variationLabel(Double(graph.variationPercentage)), caption: "Compared with usual", minHeight: 96)
            NoomMetricTile(label: "Readiness", value: readinessLabel(score), caption: "Today", minHeight: 96)
        }

        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Signals")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: score >= 70 ? "Supportive" : "Go gently", color: score >= 70 ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
                }
                RecoverySignalRow(label: "Recovery score", value: MetricFormatting.humanNumber(score), progress: Double(score) / 100, tint: NoomTheme.ink)
                RecoverySignalRow(label: "Resting heart rate", value: "\(MetricFormatting.humanNumber(Int(graph.restingHr))) bpm", progress: min(max(Double(graph.restingHr) / 100, 0.12), 1), tint: Color(hex: 0x98C7B2))
                RecoverySignalRow(label: "Sleep time", value: hoursMinutes(seconds: Int(graph.sleepTimeSeconds)), progress: min(max(Double(graph.sleepTimeSeconds) / (9 * 3600), 0.12), 1), tint: NoomTheme.red.opacity(0.84))
            }
        }

        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score factors")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                if graph.scoreFactors.isEmpty {
                    Text("No data")
                        .noomBody()
                } else {
                    ForEach(graph.scoreFactors.indices, id: \.self) { idx in
                        let factor = graph.scoreFactors[idx]
                        RecoveryFactorRow(title: factor.title.isEmpty ? "Recovery factor" : factor.title, detail: factor.description)
                    }
                }
            }
        }

        guidanceCard(score: score)
    }

    @ViewBuilder
    private func rangeSections(_ graph: SB_RecoveryRangeGraph) -> some View {
        let score = Int(graph.goalItem.item.value)
        recoveryHero(score: score, variation: Double(graph.variationPercentage))

        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(granularity == .year ? "Monthly recovery" : "Recovery trend")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: granularity.displayName, color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }
                let points = graph.recoveryScoreSection?.scorePoints ?? []
                if points.isEmpty {
                    Text("No data")
                        .noomBody()
                } else {
                    RecoveryBarTrend(values: points.sorted { $0.date < $1.date }.map { Double($0.value) })
                        .frame(height: 148)
                    VStack(spacing: 0) {
                        ForEach(points.sorted { $0.date < $1.date }.prefix(5), id: \.date) { point in
                            NoomDetailValueRow(label: MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: MetricFormatting.humanNumber(Int(point.value)), verticalPadding: 8)
                        }
                    }
                }
            }
        }

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NoomMetricTile(label: "Resting HR", value: "\(MetricFormatting.humanNumber(Int(graph.restingHr))) bpm", caption: "Average", minHeight: 96)
            NoomMetricTile(label: "Sleep", value: hoursMinutes(seconds: Int(graph.sleepTimeSeconds)), caption: "Average", minHeight: 96)
            NoomMetricTile(label: "Variation", value: variationLabel(Double(graph.variationPercentage)), caption: "Range", minHeight: 96)
            NoomMetricTile(label: "Readiness", value: readinessLabel(score), caption: granularity.displayName, minHeight: 96)
        }

        guidanceCard(score: score)
    }

    private func recoveryHero(score: Int, variation: Double) -> some View {
        NoomCard(fill: NoomTheme.ink, padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    RecoveryGauge(score: score)
                        .frame(width: 132, height: 108)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Recovery")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                        Text(MetricFormatting.humanNumber(score))
                            .font(.system(size: 56, weight: .bold, design: .serif))
                            .tracking(-2.5)
                            .foregroundStyle(.white)
                        NoomPill(title: readinessLabel(score), color: score >= 70 ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
                    }
                }

                Text(readinessSentence(score: score))
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    RecoveryHeroChip(label: "Variation", value: variationLabel(variation))
                    RecoveryHeroChip(label: "Focus", value: score >= 70 ? "Keep steady" : "Lower effort")
                }
            }
        }
    }

    private func guidanceCard(score: Int) -> some View {
        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                NoomPill(title: "Today's guidance", color: NoomTheme.red)
                Text(score >= 70 ? "Use the momentum" : "Make the day easier")
                    .noomSerifTitle(size: 26)
                Text(score >= 70 ? "Your signals can support normal movement and steady meals. Keep the plan simple so recovery stays consistent." : "Choose a gentler workout, hydrate early, and give yourself a clear wind-down window tonight.")
                    .noomBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func recoveryNoData(message: String) -> some View {
        NoomCard(fill: Color.white.opacity(0.82)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(NoomTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(NoomTheme.mint, in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text("No recovery data yet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Text(message)
                        .noomBody()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func readinessLabel(_ score: Int) -> String {
        switch score {
        case 80...: return "Strong"
        case 65..<80: return "Supportive"
        case 45..<65: return "Building"
        default: return "Rest day"
        }
    }

    private func readinessSentence(score: Int) -> String {
        switch score {
        case 80...: return "Your body looks ready for a normal day. Keep effort steady and protect your evening routine."
        case 65..<80: return "Signals look supportive. Favor consistency over intensity and keep meals predictable."
        case 45..<65: return "Recovery is still building. A lighter plan may help tomorrow feel easier."
        default: return "Your signals suggest extra care today. Lower the load and make rest feel intentional."
        }
    }

    private func variationLabel(_ variation: Double) -> String {
        let formatted = abs(variation).formatted(.number.precision(.fractionLength(1)))
        if variation > 0 { return "+\(formatted)%" }
        if variation < 0 { return "-\(formatted)%" }
        return "0.0%"
    }

    private func hoursMinutes(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(m)m"
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                daily = try await sensorBio.fetchDailyRecovery(date: dateContext.selectedDate)
            } else {
                range = try await sensorBio.fetchRangeRecovery(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = "Recovery data will appear after your next check-in."
        }
    }
}

private struct RecoveryGauge: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.14, to: 0.86)
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.14, to: 0.14 + 0.72 * CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(LinearGradient(colors: [Color(hex: 0x98C7B2), NoomTheme.red], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 58, height: 58)
            Circle()
                .fill(NoomTheme.red)
                .frame(width: 10, height: 10)
                .offset(x: 42, y: 26)
        }
    }
}

private struct RecoveryHeroChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct RecoverySignalRow: View {
    let label: String
    let value: String
    var progress: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NoomTheme.warmSurface)
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(min(max(progress, 0), 1)))
                }
            }
            .frame(height: 9)
        }
        .padding(12)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecoveryFactorRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(NoomTheme.mint)
                .frame(width: 10, height: 10)
                .overlay { Circle().fill(NoomTheme.red).frame(width: 4, height: 4) }
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                Text(detail.isEmpty ? "This signal is part of your recovery score." : detail)
                    .noomBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoomTheme.warmSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecoveryBarTrend: View {
    let values: [Double]

    private var maximum: Double { max(values.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(values.prefix(12).enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(LinearGradient(colors: [index % 3 == 0 ? NoomTheme.red : NoomTheme.ink, Color(hex: 0xF3B397)], startPoint: .top, endPoint: .bottom))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(20, 126 * CGFloat(value / maximum)))
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}
