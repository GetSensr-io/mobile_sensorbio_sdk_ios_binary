import SwiftUI
import SensorBioSDK

struct StepsDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var data: SB_StepsTrending?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("Loading\u{2026}").foregroundStyle(.secondary) } }
            } else if let error = errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            } else if let metrics = data?.graph?.metrics, !metrics.isEmpty {
                ForEach(metrics.indices, id: \.self) { idx in
                    metricSection(metrics[idx])
                }
            } else {
                Section { Text("No data").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(Metric.steps.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
        }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) {
            await load()
        }
    }

    @ViewBuilder
    private func metricSection(_ metric: SB_StepMetric) -> some View {
        Section(metric.name.isEmpty ? "Metric" : metric.name) {
            LabeledContent("Average", value: "\(Int(metric.avgValue).formatted(.number)) \(metric.unit)")
            if granularity == .day {
                if metric.timeDatapoints.isEmpty {
                    Text("No data").foregroundStyle(.secondary)
                } else {
                    ForEach(metric.timeDatapoints.sorted { $0.timestamp < $1.timestamp }, id: \.timestamp) { point in
                        LabeledContent(MetricFormatting.dayTimeLabel(timestampMillis: point.timestamp, timezoneOffsetMinutes: point.timezone),
                                       value: "\(Int(point.value).formatted(.number)) \(metric.unit)")
                    }
                }
            } else {
                if metric.datapoints.isEmpty {
                    Text("No data").foregroundStyle(.secondary)
                } else {
                    ForEach(metric.datapoints.sorted { $0.date < $1.date }, id: \.date) { point in
                        LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                                       value: "\(Int(point.value).formatted(.number)) \(metric.unit)")
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            data = try await sensorBio.fetchSteps(date: dateContext.selectedDate, granularity: granularity)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
