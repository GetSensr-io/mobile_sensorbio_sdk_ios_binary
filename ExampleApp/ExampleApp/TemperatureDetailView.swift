import SwiftUI
import SensorBioSDK

struct TemperatureDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_DailyTemperatureTrending?
    @State private var range: SB_TemperatureRangeTrending?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("Loading\u{2026}").foregroundStyle(.secondary) } }
            } else if let error = errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            } else if granularity == .day, let daily {
                Section("Summary") {
                    LabeledContent("Average", value: celsius(daily.average))
                    LabeledContent("Lowest", value: celsius(daily.lowest))
                    LabeledContent("Highest", value: celsius(daily.highest))
                    LabeledContent("Latest", value: celsius(daily.latest))
                    if let baseline = daily.baseline {
                        LabeledContent("Baseline", value: celsius(baseline))
                    }
                    if let sleep = daily.sleepAverage {
                        LabeledContent("Sleep", value: celsius(sleep))
                    }
                }
                Section("Readings") {
                    if daily.points.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(daily.points, id: \.epoch) { point in
                            LabeledContent(MetricFormatting.sampleTimeLabel(timestampMillis: point.epoch),
                                           value: celsius(point.value))
                        }
                    }
                }
            } else if granularity != .day, let range {
                rangeSection("Sleep", range.sleep)
                rangeSection("Whole Day", range.daily)
            }
        }
        .navigationTitle(Metric.temperature.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
        }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) {
            await load()
        }
    }

    @ViewBuilder
    private func rangeSection(_ title: String, _ graph: SB_TemperatureTrendingGraph) -> some View {
        Section(title) {
            LabeledContent("Average", value: celsius(graph.average))
            if let baseline = graph.baseline {
                LabeledContent("Baseline", value: celsius(baseline))
            }
            let points = graph.graph?.mainPoints ?? []
            ForEach(points.sorted { $0.date < $1.date }, id: \.date) { point in
                LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                               value: celsius(point.value))
            }
        }
    }

    private func celsius(_ value: Float) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) \u{00B0}C"
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                daily = try await sensorBio.fetchDailyTemperature(date: dateContext.selectedDate)
            } else {
                range = try await sensorBio.fetchRangeTemperature(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
