import SwiftUI
import SensorBioSDK
import Combine

struct NoomSleepNoDataView: View {
    var showsFirstNight: Bool = false
    var bandReady: Bool = false
    var title: String = "No sleep session for this date"
    var message: String = "No completed sleep was returned for the selected date. Try another day or sync Noom Band again."

    @ViewBuilder
    var body: some View {
        if showsFirstNight {
            NoomFirstNightCard(bandReady: bandReady)
        } else {
            NoomEmptyStateCard(title: title, message: message, systemImage: "moon.zzz.fill")
        }
    }
}

struct SleepDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_SleepDetailDay?
    @State private var range: SB_SleepDetailAggregated?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var activeRequestID: UUID?
    @State private var haveDevice = sensorBio.haveDevice
    @State private var connected = sensorBio.connected
    @State private var detectedSleep: SB_DetectedSleep?
    @State private var postSyncReloadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                screenHeader

                if isLoading, granularity == .day, isSelectedDateToday, detectedSleep != nil {
                    detectedSleepSections
                } else if isLoading {
                    loadingCard
                } else if isQAPreview {
                    qaDaySections
                } else if errorMessage != nil {
                    NoomSleepNoDataView(
                        title: "Sleep unavailable",
                        message: errorMessage ?? "Noom could not load sleep for this date. Try again after reconnecting your band."
                    )
                } else if granularity == .day, let detail = daily {
                    daySections(detail)
                } else if granularity != .day, let agg = range {
                    rangeSections(agg)
                } else if granularity == .day, isSelectedDateToday, detectedSleep != nil {
                    detectedSleepSections
                } else {
                    NoomSleepNoDataView(
                        showsFirstNight: shouldShowFirstNight,
                        bandReady: haveDevice && connected
                    )
                }
            }
            .padding(.horizontal, NoomTheme.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .noomBackground()
        .navigationTitle(Metric.sleep.title)
        .navigationBarTitleDisplayMode(.inline)
        .noomDetailBackButton()
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
        }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) {
            if !isQAPreview { await load() }
        }
        .onReceive(sensorBio.sleepStored.merge(with: sensorBio.sleepUploaded)) { _ in
            if !isQAPreview { schedulePostSyncReload() }
        }
        .onReceive(sensorBio.sleepDetected) { detected in
            guard !isQAPreview,
                  granularity == .day,
                  isSelectedDateToday else { return }
            detectedSleep = detected
            schedulePostSyncReload()
        }
        .onReceive(sensorBio.syncCompleted) { result in
            guard result?.acknowledge == true, !isQAPreview else {
                postSyncReloadTask?.cancel()
                return
            }
            schedulePostSyncReload()
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onDisappear { postSyncReloadTask?.cancel() }
    }

    private func schedulePostSyncReload() {
        postSyncReloadTask?.cancel()
        postSyncReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await load(forceRemote: true)
        }
    }

    private var shouldShowFirstNight: Bool {
        granularity == .day &&
        isSelectedDateToday &&
        !NoomSleepHistory.hasRecordedSleep(for: sensorBio.session?.userId) &&
        errorMessage == nil
    }

    private var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(dateContext.selectedDate)
    }

    private var isQAPreview: Bool {
        #if DEBUG
        ["sleep_detail", "sleep_detail_processing_preview", "sleep_detail_complete_preview"]
            .contains(ProcessInfo.processInfo.environment["NOOM_QA_ROUTE"])
        #else
        false
        #endif
    }

    private var qaRoute: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["NOOM_QA_ROUTE"]
        #else
        nil
        #endif
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep")
                .noomSerifTitle(size: 38)
            Text("Your overnight signals from Noom Band, shaped into a calmer plan for today.")
                .noomBody()
        }
    }

    private var loadingCard: some View {
        NoomLoadingExperience(
            title: "Checking last night's sleep",
            detail: "Loading the latest sleep session available for this date.",
            systemImage: "moon.stars.fill",
            accent: NoomTheme.metricPurple
        )
    }

    @ViewBuilder
    private var qaDaySections: some View {
        #if DEBUG
        NoomStateBanner(
            title: "Preview sample",
            detail: "Synthetic sleep data for layout review. It is not a personal health result.",
            systemImage: "wrench.and.screwdriver",
            tint: NoomTheme.rose
        )

        if qaRoute == "sleep_detail_processing_preview" {
            sleepSessionStatusCard(
                isProcessing: true,
                onsetMillis: 1_783_826_100_000,
                wakeMillis: 1_783_854_120_000,
                timezoneOffsetMinutes: -300
            )
            processingSleepCard
        } else {
            sleepSessionStatusCard(
                isProcessing: false,
                onsetMillis: 1_783_826_100_000,
                wakeMillis: 1_783_854_120_000,
                timezoneOffsetMinutes: -300
            )
            sleepHero(score: 82, sleepTime: "7h 34m", restingHR: 58, restingHRV: 42)

            NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sleep stages")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    SleepStageBand(stages: makeStageData(awake: 8, light: 48, deep: 22, rem: 22))
                        .frame(height: 18)
                    stageLegend(makeStageData(awake: 8, light: 48, deep: 22, rem: 22))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NoomMetricTile(label: "Sleep time", value: "7h 34m", caption: "Last night", minHeight: 96)
                NoomMetricTile(label: "Resting HR", value: "58 bpm", caption: "Overnight", minHeight: 96)
                NoomMetricTile(label: "HRV", value: "42 ms", caption: "Recovery signal", minHeight: 96)
                NoomMetricTile(label: "Awake", value: "8%", caption: "Sleep stage", minHeight: 96)
            }
        }
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func daySections(_ detail: SB_SleepDetailDay) -> some View {
        sleepSessionStatusCard(
            isProcessing: detail.processing,
            onsetMillis: detail.sleepOnset,
            wakeMillis: detail.wakeUpTime,
            timezoneOffsetMinutes: detail.timezone
        )

        if detail.processing {
            processingSleepCard
        } else {
            sleepHero(score: Int(detail.sleepScore.score), sleepTime: hoursMinutes(seconds: Int(detail.sleepTimeSec)), restingHR: Int(detail.restingHr), restingHRV: Int(detail.restingHrv))

        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sleep stages")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                SleepStageBand(stages: stageData(detail.stages))
                    .frame(height: 18)
                stageLegend(stageData(detail.stages))
            }
        }

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NoomMetricTile(label: "Sleep time", value: hoursMinutes(seconds: Int(detail.sleepTimeSec)), caption: "Last night", minHeight: 96)
            NoomMetricTile(label: "Resting HR", value: "\(MetricFormatting.humanNumber(Int(detail.restingHr))) bpm", caption: "Overnight", minHeight: 96)
            NoomMetricTile(label: "HRV", value: "\(MetricFormatting.humanNumber(Int(detail.restingHrv))) ms", caption: "Recovery signal", minHeight: 96)
            NoomMetricTile(label: "Awake", value: "\(MetricFormatting.humanNumber(Int(detail.stages.awakePercentage)))%", caption: "Sleep stage", minHeight: 96)
        }

        if !detail.scoreFactors.isEmpty {
            NoomCard(fill: Color.white.opacity(0.84)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contributors")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    ForEach(detail.scoreFactors.indices, id: \.self) { idx in
                        let factor = detail.scoreFactors[idx]
                        NoomFactorRow(title: factor.title.isEmpty ? "Sleep factor" : factor.title, detail: factor.description, tint: NoomTheme.mint)
                    }
                }
            }
        }

        if let bio = detail.biometrics {
            NoomCard(fill: Color.white.opacity(0.84)) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Biometrics")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        NoomMetricTile(label: "Heart rate", value: "\(MetricFormatting.humanNumber(Int(bio.hrGraph.avg))) bpm", caption: "Average", minHeight: 88)
                        NoomMetricTile(label: "HRV", value: "\(MetricFormatting.humanNumber(Int(bio.hrvGraph.avg))) ms", caption: "Average", minHeight: 88)
                        NoomMetricTile(label: "Resp rate", value: "\(MetricFormatting.humanNumber(Int(bio.respGraph.avg))) brpm", caption: "Average", minHeight: 88)
                        NoomMetricTile(label: "SpO\u{2082}", value: "\(MetricFormatting.humanNumber(Int(bio.spo2Graph.avg)))%", caption: "Average", minHeight: 88)
                    }
                }
            }
        }

        if let rec = detail.bedtimeRecommendation, !rec.isGenerating {
            recommendationCard(rec)
        }

        if let acc = detail.sleepAccounting, !acc.isGenerating {
            NoomCard(fill: Color.white.opacity(0.84)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep balance")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    NoomDetailValueRow(label: "Circadian score", value: MetricFormatting.humanNumber(Int(acc.circadianScore)), verticalPadding: 8)
                    NoomDetailValueRow(label: "Sleep debt", value: hoursMinutes(minutes: Int(acc.sleepDebtNetMins)), verticalPadding: 8)
                    NoomDetailValueRow(label: "Recommended", value: hoursMinutes(minutes: Int(acc.current.recommendedMins)), verticalPadding: 8)
                    NoomDetailValueRow(label: "Achieved", value: hoursMinutes(minutes: Int(acc.current.achievedMins)), verticalPadding: 8)
                }
            }
        }
        }
    }

    @ViewBuilder
    private func rangeSections(_ agg: SB_SleepDetailAggregated) -> some View {
        sleepHero(score: Int(agg.sleepScore.score), sleepTime: hoursMinutes(seconds: Int(agg.sleepTimeSec)), restingHR: Int(agg.restingHr), restingHRV: nil)

        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(granularity == .year ? "Monthly rhythm" : "Sleep rhythm")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: granularity.displayName, color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }
                if agg.sleepTimePoints.isEmpty {
                    Text("No data")
                        .noomBody()
                } else {
                    NoomBarTrend(values: agg.sleepTimePoints.sorted { $0.date < $1.date }.map { Double($0.value) }, tint: NoomTheme.ink)
                        .frame(height: 148)
                    VStack(spacing: 0) {
                        ForEach(agg.sleepTimePoints.sorted { $0.date < $1.date }.prefix(5), id: \.date) { point in
                            NoomDetailValueRow(label: MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: hoursMinutes(seconds: Int(point.value)), verticalPadding: 8)
                        }
                    }
                }
            }
        }

        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Average stages")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                SleepStageBand(stages: stageData(agg.stages))
                    .frame(height: 18)
                stageLegend(stageData(agg.stages))
            }
        }

        if !agg.metrics.isEmpty {
            NoomCard(fill: Color.white.opacity(0.84)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep metrics")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    ForEach(agg.metrics.indices, id: \.self) { idx in
                        let metric = agg.metrics[idx]
                        NoomDetailValueRow(label: metric.name.isEmpty ? "Metric" : metric.name, value: sleepMetricValue(metric), verticalPadding: 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detectedSleepSections: some View {
        NoomStateBanner(
            title: "Sleep detected",
            detail: "Noom+ is processing the session. Your score, stages, and overnight metrics will appear when analysis is complete.",
            systemImage: "moon.stars.fill",
            tint: NoomTheme.metricPurple
        )
        sleepSessionStatusCard(
            isProcessing: true,
            onsetMillis: 0,
            wakeMillis: 0,
            timezoneOffsetMinutes: 0
        )
        processingSleepCard
    }

    private var processingSleepCard: some View {
        NoomLoadingExperience(
            title: "Finishing your sleep analysis",
            detail: "Sleep was detected. Your score, stages, and overnight metrics may update while analysis finishes.",
            systemImage: "waveform.path.ecg",
            accent: NoomTheme.metricPurple
        )
        .accessibilityLabel("Sleep analysis in progress")
    }

    private func sleepSessionStatusCard(
        isProcessing: Bool,
        onsetMillis: Int64,
        wakeMillis: Int64,
        timezoneOffsetMinutes: Int32
    ) -> some View {
        let onset = sleepClockLabel(timestampMillis: onsetMillis, timezoneOffsetMinutes: timezoneOffsetMinutes)
        let wake = sleepClockLabel(timestampMillis: wakeMillis, timezoneOffsetMinutes: timezoneOffsetMinutes)

        return NoomCard(fill: isProcessing ? NoomTheme.metricPurple.opacity(0.12) : Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    if isProcessing {
                        ProgressView()
                            .tint(NoomTheme.metricPurple)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(NoomTheme.mint)
                            .accessibilityHidden(true)
                    }
                    Text(isProcessing ? "Processing sleep" : "Sleep analysis complete")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Spacer(minLength: 8)
                    NoomPill(title: isProcessing ? "In progress" : "Complete", color: isProcessing ? NoomTheme.rose : NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }

                Text(isProcessing ? "Noom+ is still preparing this session. Timing can appear before the score and stages are final." : "These results are ready from the completed sleep session.")
                    .noomBody()
                    .fixedSize(horizontal: false, vertical: true)

                if onset != nil || wake != nil {
                    VStack(spacing: 0) {
                        if let onset {
                            NoomDetailValueRow(label: "Sleep onset", value: onset, verticalPadding: 8)
                        }
                        if let wake {
                            NoomDetailValueRow(label: "Wake up", value: wake, verticalPadding: 8)
                        }
                    }
                } else {
                    Text("Sleep onset and wake-up times will appear when the session provides them.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoomTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sleepClockLabel(timestampMillis: Int64, timezoneOffsetMinutes: Int32) -> String? {
        guard timestampMillis > 0 else { return nil }
        let secondsFromGMT = Int(timezoneOffsetMinutes) * 60
        let timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? .current
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        return Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000).formatted(style)
    }

    private func sleepHero(score: Int, sleepTime: String, restingHR: Int, restingHRV: Int?) -> some View {
        NoomCard(fill: NoomTheme.ink, padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sleep score")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                        Text("\(score)")
                            .font(.system(size: 64, weight: .bold, design: .serif))
                            .tracking(-3)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    NoomPill(title: readinessLabel(score), color: score >= 70 ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
                }

                Text(score >= 70 ? "A solid base for today. Keep choices steady and protect your wind-down window." : "Your body may want a gentler day. Small routines count most after lighter sleep.")
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SleepHeroChip(label: "Duration", value: sleepTime)
                    SleepHeroChip(label: "Resting HR", value: "\(restingHR) bpm")
                    if let restingHRV {
                        SleepHeroChip(label: "HRV", value: "\(restingHRV) ms")
                    }
                }
            }
        }
    }

    private func recommendationCard(_ rec: SB_SleepBedtimeRecommendation) -> some View {
        NoomCard(fill: Color.white.opacity(0.84)) {
            VStack(alignment: .leading, spacing: 12) {
                NoomPill(title: "Tonight", color: NoomTheme.red)
                Text("Plan a softer landing")
                    .noomSerifTitle(size: 26)
                VStack(spacing: 0) {
                    if let bedtime = rec.bedtime {
                        NoomDetailValueRow(label: "Bedtime", value: localTimeLabel(timestampMillis: bedtime.tsMillis, timezoneOffsetMinutes: bedtime.tzOffset), verticalPadding: 8)
                    }
                    if let wakeup = rec.wakeup {
                        NoomDetailValueRow(label: "Wake up", value: localTimeLabel(timestampMillis: wakeup.tsMillis, timezoneOffsetMinutes: wakeup.tzOffset), verticalPadding: 8)
                    }
                    NoomDetailValueRow(label: "Target sleep", value: hoursMinutes(minutes: Int(rec.sleepHoursInMins)), verticalPadding: 8)
                }
                Text("Treat this as a gentle planning cue, not a rule. Consistency is the signal Noom watches over time.")
                    .noomBody()
            }
        }
    }

    private func stageLegend(_ stages: [SleepStageSlice]) -> some View {
        HStack(spacing: 9) {
            ForEach(stages) { stage in
                HStack(spacing: 5) {
                    Circle().fill(stage.color).frame(width: 7, height: 7)
                    Text("\(stage.label) \(Int(stage.percentage))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(NoomTheme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageData(_ stages: SB_SleepStages) -> [SleepStageSlice] {
        makeStageData(awake: stages.awakePercentage, light: stages.lightPercentage, deep: stages.deepPercentage, rem: stages.remPercentage)
    }

    private func stageData(_ stages: SB_SleepStagesAggregated) -> [SleepStageSlice] {
        makeStageData(awake: stages.awakePercentage, light: stages.lightPercentage, deep: stages.deepPercentage, rem: stages.remPercentage)
    }

    private func makeStageData(awake: Int32, light: Int32, deep: Int32, rem: Int32) -> [SleepStageSlice] {
        [
            SleepStageSlice(label: "Awake", percentage: max(0, Double(awake)), color: NoomTheme.red.opacity(0.82)),
            SleepStageSlice(label: "Light", percentage: max(0, Double(light)), color: Color(hex: 0x98C7B2)),
            SleepStageSlice(label: "Deep", percentage: max(0, Double(deep)), color: NoomTheme.ink),
            SleepStageSlice(label: "REM", percentage: max(0, Double(rem)), color: Color(hex: 0xBFDACD))
        ]
    }

    private func readinessLabel(_ score: Int) -> String {
        switch score {
        case 80...: return "Restorative"
        case 65..<80: return "Supportive"
        default: return "Gentle day"
        }
    }

    private func sleepMetricValue(_ metric: SB_SleepMetric) -> String {
        switch metric.value {
        case .valueUnit(let vu): return formattedValueUnit(vu)
        case .timeTz(let tt): return localTimeLabel(timestampMillis: tt.timestamp, timezoneOffsetMinutes: tt.timezone)
        case .empty: return "No data"
        @unknown default: return "No data"
        }
    }

    private func formattedValueUnit(_ wrapper: SB_ValueUnitWrapper) -> String {
        if !wrapper.stringValue.isEmpty { return wrapper.stringValue }
        let lowerUnit = wrapper.unit.lowercased()
        let isMinuteUnit = ["min", "mins", "minute", "minutes"].contains(lowerUnit)
        if isMinuteUnit {
            return hoursMinutes(minutes: Int(wrapper.value))
        }
        let num = MetricFormatting.humanNumber(Int(wrapper.value))
        return wrapper.unit.isEmpty ? num : "\(num) \(wrapper.unit)"
    }

    private func localTimeLabel(timestampMillis: Int64, timezoneOffsetMinutes: Int32) -> String {
        sleepClockLabel(timestampMillis: timestampMillis, timezoneOffsetMinutes: timezoneOffsetMinutes) ?? "—"
    }

    private func hoursMinutes(seconds: Int) -> String {
        hoursMinutes(minutes: max(0, seconds) / 60)
    }

    private func hoursMinutes(minutes: Int) -> String {
        let mag = abs(minutes)
        let prefix = minutes < 0 ? "-" : ""
        if mag < 60 {
            return "\(prefix)\(mag) \(mag == 1 ? "minute" : "minutes")"
        }
        let h = mag / 60
        let m = mag % 60
        return "\(prefix)\(h)h \(m)m"
    }

    @MainActor
    private func load(forceRemote: Bool = false) async {
        let requestID = UUID()
        activeRequestID = requestID
        let requestUserID = sensorBio.session?.userId
        isLoading = true
        defer {
            if activeRequestID == requestID { isLoading = false }
        }

        var nextDaily: SB_SleepDetailDay?
        var nextRange: SB_SleepDetailAggregated?
        var nextError: String?

        do {
            if granularity == .day {
                let tzOffset = Int32(TimeZone.current.secondsFromGMT(for: dateContext.selectedDate))
                let dashboard = try await sensorBio.fetchDashboardData(date: dateContext.selectedDate, tzOffset: tzOffset, forceRemote: forceRemote)
                if let session = dashboard.sleeps.first {
                    NoomSleepHistory.recordSleep(for: requestUserID)
                    let endTs = Date(timeIntervalSince1970: TimeInterval(session.endTimestamp) / 1000)
                    nextDaily = try await sensorBio.fetchSleepDetail(endDate: endTs, endTimestamp: Int64(session.endTimestamp), forceRemote: forceRemote)
                }
            } else {
                nextRange = try await sensorBio.fetchSleepAggregation(date: dateContext.selectedDate, granularity: granularity, forceRemote: forceRemote)
                if nextRange?.sleepTimePoints.isEmpty == false { NoomSleepHistory.recordSleep(for: requestUserID) }
            }
        } catch is CancellationError {
            return
        } catch {
            nextError = "Connect your Noom Band to see tonight's sleep story."
        }

        guard activeRequestID == requestID, !Task.isCancelled else { return }
        daily = nextDaily
        range = nextRange
        errorMessage = nextError
        if !isSelectedDateToday || nextDaily?.processing == false {
            detectedSleep = nil
        }
    }
}

private struct SleepStageSlice: Identifiable {
    let id = UUID()
    let label: String
    let percentage: Double
    let color: Color
}

private struct SleepStageBand: View {
    let stages: [SleepStageSlice]

    private var total: Double { max(stages.map(\.percentage).reduce(0, +), 1) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(stages) { stage in
                    stage.color
                        .frame(width: proxy.size.width * CGFloat(stage.percentage / total))
                }
            }
            .clipShape(Capsule())
        }
    }
}

private struct SleepHeroChip: View {
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

struct NoomDetailValueRow: View {
    let label: String
    let value: String
    var verticalPadding: CGFloat = 10

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(NoomTheme.muted)
            Spacer(minLength: 16)
            Text(value).bold().foregroundStyle(NoomTheme.logoBlack)
        }
        .font(.system(size: 14))
        .padding(.vertical, verticalPadding)
        .overlay(alignment: .top) { NoomTheme.ink.opacity(0.08).frame(height: 1) }
    }
}

private struct NoomFactorRow: View {
    let title: String
    let detail: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .overlay { Circle().fill(NoomTheme.red).frame(width: 4, height: 4) }
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                Text(detail.isEmpty ? "This signal is part of your sleep score." : detail)
                    .noomBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoomTheme.warmSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct NoomBarTrend: View {
    let values: [Double]
    var tint: Color

    private var maximum: Double { max(values.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(values.prefix(12).enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.34)], startPoint: .top, endPoint: .bottom))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(20, 126 * CGFloat(value / maximum)))
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}
