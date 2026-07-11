import SwiftUI
import SensorBioSDK

struct HRDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_HRDailyTrending?
    @State private var range: SB_HRRangeTrending?
    @State private var baseline: PersonalBaseline?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                NoomLoadingExperience(
                    title: "Listening for your rhythm",
                    detail: "Shaping your resting heart-rate story now.",
                    systemImage: "heart.fill",
                    accent: NoomTheme.red
                )
                .padding(NoomTheme.horizontalPadding)
            } else if let errorMessage {
                ContentUnavailableView("Heart rate unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if granularity == .day, let graph = daily?.graph {
                BaselineMetricDetail(
                    title: Metric.hr.title,
                    symbol: "heart.fill",
                    accent: .red,
                    date: dateContext.selectedDate,
                    value: Double(graph.restingBpm),
                    valueText: MetricFormatting.humanNumber(Double(graph.restingBpm)),
                    unit: "bpm",
                    tone: .heartRate,
                    baseline: baseline,
                    readings: [
                        MetricReading(label: "Resting", value: "\(MetricFormatting.humanNumber(Double(graph.restingBpm))) bpm"),
                        MetricReading(label: "Average", value: "\(MetricFormatting.humanNumber(Double(graph.rawAvg))) bpm"),
                        MetricReading(label: "Low", value: "\(MetricFormatting.humanNumber(Double(graph.rawLowest))) bpm"),
                        MetricReading(label: "High", value: "\(MetricFormatting.humanNumber(Double(graph.rawHighest))) bpm")
                    ] + graph.heartRateTimeseriesPoints.sorted { $0.timestamp < $1.timestamp }.map {
                        MetricReading(label: MetricFormatting.dayTimeLabel(timestampMillis: $0.timestamp, timezoneOffsetMinutes: $0.timezone), value: "\(MetricFormatting.humanNumber(Double($0.value))) bpm")
                    }
                )
            } else if let graph = range?.graph {
                List {
                    Section("Range summary") {
                        LabeledContent("Average", value: "\(MetricFormatting.humanNumber(Double(graph.avgBpm))) bpm")
                        LabeledContent("Low", value: "\(MetricFormatting.humanNumber(Double(graph.lowest))) bpm")
                        LabeledContent("High", value: "\(MetricFormatting.humanNumber(Double(graph.highest))) bpm")
                    }
                    Section("Readings") {
                        ForEach(graph.bpmPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                            LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: "\(MetricFormatting.humanNumber(Double(point.value))) bpm")
                        }
                    }
                }
            } else {
                ContentUnavailableView("No heart-rate data yet", systemImage: "heart")
            }
        }
        .navigationTitle(Metric.hr.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { DetailHeaderControls(granularity: $granularity) }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) { await load() }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                daily = try await sensorBio.fetchDailyHR(date: dateContext.selectedDate)
                let current = Double(daily?.graph?.restingBpm ?? 0)
                let observations = (try? await PersonalBaselineLoader.trailingObservations(for: .restingHeartRate, selectedDate: dateContext.selectedDate)) ?? []
                baseline = PersonalBaseline.make(currentValue: current, observations: observations)
            } else {
                range = try await sensorBio.fetchRangeHR(date: dateContext.selectedDate, granularity: granularity)
                baseline = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
