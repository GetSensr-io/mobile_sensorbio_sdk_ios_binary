import SwiftUI
import SensorBioSDK

struct SleepDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_SleepDetailDay?
    @State private var range: SB_SleepDetailAggregated?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("Loading\u{2026}").foregroundStyle(.secondary) } }
            } else if let error = errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            } else if granularity == .day, let detail = daily {
                daySections(detail)
            } else if granularity != .day, let agg = range {
                rangeSections(agg)
            }
        }
        .navigationTitle(Metric.sleep.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
        }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) {
            await load()
        }
    }

    @ViewBuilder
    private func daySections(_ detail: SB_SleepDetailDay) -> some View {
        Section("Summary") {
            LabeledContent("Score", value: "\(detail.sleepScore.score)")
            LabeledContent("Sleep Time", value: hoursMinutes(seconds: Int(detail.sleepTimeSec)))
            LabeledContent("Resting HR", value: "\(Int(detail.restingHr)) bpm")
            LabeledContent("Resting HRV", value: "\(Int(detail.restingHrv)) ms")
        }

        Section("Stages") {
            LabeledContent("Awake", value: "\(Int(detail.stages.awakePercentage))%")
            LabeledContent("Light", value: "\(Int(detail.stages.lightPercentage))%")
            LabeledContent("Deep",  value: "\(Int(detail.stages.deepPercentage))%")
            LabeledContent("REM",   value: "\(Int(detail.stages.remPercentage))%")
        }

        if !detail.metrics.isEmpty {
            Section("Metrics") {
                ForEach(detail.metrics.indices, id: \.self) { idx in
                    sleepMetricRow(detail.metrics[idx])
                }
            }
        }

        if !detail.scoreFactors.isEmpty {
            Section("Contributing Factors") {
                ForEach(detail.scoreFactors.indices, id: \.self) { idx in
                    let factor = detail.scoreFactors[idx]
                    LabeledContent(factor.title.isEmpty ? "Factor" : factor.title) {
                        Text(factor.description)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if !detail.scorePenalty.isEmpty {
            Section("Penalties") {
                ForEach(detail.scorePenalty.indices, id: \.self) { idx in
                    let penalty = detail.scorePenalty[idx]
                    let valueText = String(format: "%.1f", penalty.value)
                    LabeledContent(penalty.name.isEmpty ? "Penalty" : penalty.name, value: valueText)
                }
            }
        }

        if let bio = detail.biometrics {
            Section("Biometrics (avg)") {
                LabeledContent("Heart Rate", value: "\(Int(bio.hrGraph.avg)) bpm")
                LabeledContent("HRV", value: "\(Int(bio.hrvGraph.avg)) ms")
                LabeledContent("Resp Rate", value: "\(Int(bio.respGraph.avg)) brpm")
                LabeledContent("SpO\u{2082}", value: "\(Int(bio.spo2Graph.avg))%")
            }
        }

        Section("Disturbances") {
            LabeledContent("Snoring", value: "\(detail.disturbances.snoringGraph.stages.count)")
            LabeledContent("Arm movements", value: "\(detail.disturbances.armGraph.stages.count)")
            LabeledContent("Leg movements", value: "\(detail.disturbances.legGraph.stages.count)")
            LabeledContent("Kicks", value: "\(detail.disturbances.kicksGraph.stages.count)")
            if !detail.bathroomBreakTimestamps.isEmpty {
                LabeledContent("Bathroom breaks", value: "\(detail.bathroomBreakTimestamps.count)")
            }
        }

        if let rec = detail.bedtimeRecommendation, !rec.isGenerating {
            Section("Recommendation") {
                if let bedtime = rec.bedtime {
                    LabeledContent("Bedtime", value: localTimeLabel(timestampMillis: bedtime.tsMillis))
                }
                if let wakeup = rec.wakeup {
                    LabeledContent("Wake up", value: localTimeLabel(timestampMillis: wakeup.tsMillis))
                }
                LabeledContent("Target Sleep", value: hoursMinutes(minutes: Int(rec.sleepHoursInMins)))
            }
        }

        if let acc = detail.sleepAccounting, !acc.isGenerating {
            Section("Sleep Accounting") {
                LabeledContent("Circadian Score", value: "\(Int(acc.circadianScore))")
                LabeledContent("Sleep Debt", value: hoursMinutes(minutes: Int(acc.sleepDebtNetMins)))
                LabeledContent("Recommended", value: hoursMinutes(minutes: Int(acc.current.recommendedMins)))
                LabeledContent("Achieved", value: hoursMinutes(minutes: Int(acc.current.achievedMins)))
            }
        }
    }

    @ViewBuilder
    private func rangeSections(_ agg: SB_SleepDetailAggregated) -> some View {
        Section("Summary") {
            LabeledContent("Score", value: "\(agg.sleepScore.score)")
            LabeledContent("Sleep Time", value: hoursMinutes(seconds: Int(agg.sleepTimeSec)))
            LabeledContent("Resting HR", value: "\(Int(agg.restingHr)) bpm")
        }

        Section("Stages") {
            LabeledContent("Awake", value: "\(Int(agg.stages.awakePercentage))%")
            LabeledContent("Light", value: "\(Int(agg.stages.lightPercentage))%")
            LabeledContent("Deep",  value: "\(Int(agg.stages.deepPercentage))%")
            LabeledContent("REM",   value: "\(Int(agg.stages.remPercentage))%")
        }

        if !agg.metrics.isEmpty {
            Section("Metrics") {
                ForEach(agg.metrics.indices, id: \.self) { idx in
                    sleepMetricRow(agg.metrics[idx])
                }
            }
        }

        Section(granularity == .year ? "By Month" : "By Day") {
            if agg.sleepTimePoints.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                ForEach(agg.sleepTimePoints.sorted { $0.date < $1.date }, id: \.date) { point in
                    LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                                   value: hoursMinutes(seconds: Int(point.value)))
                }
            }
        }
    }

    @ViewBuilder
    private func sleepMetricRow(_ metric: SB_SleepMetric) -> some View {
        let label = metric.name.isEmpty ? "Metric" : metric.name
        switch metric.value {
        case .valueUnit(let vu):
            LabeledContent(label, value: formattedValueUnit(vu))
        case .timeTz(let tt):
            LabeledContent(label, value: localTimeLabel(timestampMillis: tt.timestamp))
        case .empty:
            LabeledContent(label, value: "—")
        }
    }

    private func formattedValueUnit(_ wrapper: SB_ValueUnitWrapper) -> String {
        if !wrapper.stringValue.isEmpty { return wrapper.stringValue }
        let lowerUnit = wrapper.unit.lowercased()
        let isMinuteUnit = ["min", "mins", "minute", "minutes"].contains(lowerUnit)
        if isMinuteUnit {
            return hoursMinutes(minutes: Int(wrapper.value))
        }
        let num = "\(Int(wrapper.value))"
        return wrapper.unit.isEmpty ? num : "\(num) \(wrapper.unit)"
    }

    private func localTimeLabel(timestampMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
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
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                // The day's sleep session is in `data.sleeps` on the
                // dashboard payload; fetchSleepDetail wants the session's
                // exact end timestamp.
                let tzOffset = Int32(TimeZone.current.secondsFromGMT(for: dateContext.selectedDate))
                let dashboard = try await sensorBio.fetchDashboardData(date: dateContext.selectedDate, tzOffset: tzOffset)
                guard let session = dashboard.sleeps.first else {
                    daily = nil
                    errorMessage = "No sleep session recorded for this day."
                    return
                }
                let endTs = Date(timeIntervalSince1970: TimeInterval(session.endTimestamp) / 1000)
                daily = try await sensorBio.fetchSleepDetail(endDate: endTs, endTimestamp: endTs)
            } else {
                range = try await sensorBio.fetchSleepAggregation(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
