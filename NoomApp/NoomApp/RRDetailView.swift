import SwiftUI
import SensorBioSDK

struct RRDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_RRDailyTrending?
    @State private var range: SB_RRRangeTrending?
    @State private var baseline: PersonalBaseline?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading respiratory rate…")
            } else if let errorMessage {
                ContentUnavailableView("Respiratory rate unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if granularity == .day, let graph = daily?.graph {
                BaselineMetricDetail(
                    title: Metric.rr.title,
                    symbol: "lungs.fill",
                    accent: .teal,
                    date: dateContext.selectedDate,
                    value: Double(graph.brpm),
                    valueText: MetricFormatting.humanNumber(Double(graph.brpm)),
                    unit: "brpm",
                    tone: .respiratory,
                    baseline: baseline,
                    readings: [
                        MetricReading(label: "Average", value: "\(MetricFormatting.humanNumber(Double(graph.brpm))) brpm"),
                        MetricReading(label: "Low", value: "\(MetricFormatting.humanNumber(Double(graph.rawLowest))) brpm"),
                        MetricReading(label: "High", value: "\(MetricFormatting.humanNumber(Double(graph.rawHighest))) brpm")
                    ] + graph.rawDatetimePoints.sorted { $0.timestamp < $1.timestamp }.map {
                        MetricReading(label: MetricFormatting.dayTimeLabel(timestampMillis: $0.timestamp, timezoneOffsetMinutes: $0.timezone), value: "\(MetricFormatting.humanNumber(Double($0.value))) brpm")
                    }
                )
            } else if let graph = range?.graph {
                List {
                    Section("Range summary") {
                        LabeledContent("Average", value: "\(MetricFormatting.humanNumber(Double(graph.avgBrpm))) brpm")
                        LabeledContent("Low", value: "\(MetricFormatting.humanNumber(Double(graph.lowest))) brpm")
                        LabeledContent("High", value: "\(MetricFormatting.humanNumber(Double(graph.highest))) brpm")
                    }
                    Section("Readings") {
                        ForEach(graph.brpmPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                            LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: "\(MetricFormatting.humanNumber(Double(point.value))) brpm")
                        }
                    }
                }
            } else {
                ContentUnavailableView("No respiratory-rate data yet", systemImage: "lungs")
            }
        }
        .navigationTitle(Metric.rr.title)
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
                daily = try await sensorBio.fetchDailyRR(date: dateContext.selectedDate)
                let current = Double(daily?.graph?.brpm ?? 0)
                let history = (try? await PersonalBaselineLoader.trailingValues(for: .respiratoryRate, selectedDate: dateContext.selectedDate)) ?? []
                baseline = PersonalBaseline.make(currentValue: current, historicalValues: history)
            } else {
                range = try await sensorBio.fetchRangeRR(date: dateContext.selectedDate, granularity: granularity)
                baseline = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
