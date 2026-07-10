import SwiftUI
import SensorBioSDK

struct HRVDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_HRVDailyTrending?
    @State private var range: SB_HRVRangeTrending?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("Loading\u{2026}").foregroundStyle(.secondary) } }
            } else if let error = errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            } else if granularity == .day, let graph = daily?.graph {
                Section("Summary") {
                    LabeledContent("rMSSD", value: "\(Int(graph.rMssd)) ms")
                    LabeledContent("Average", value: "\(Int(graph.rawAvg)) ms")
                    LabeledContent("Lowest", value: "\(Int(graph.rawLowest)) ms")
                    LabeledContent("Highest", value: "\(Int(graph.rawHighest)) ms")
                }
                Section("By Hour") {
                    if graph.rawDatetimeHrvPoints.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(graph.rawDatetimeHrvPoints.sorted { $0.timestamp < $1.timestamp }, id: \.timestamp) { point in
                            LabeledContent(MetricFormatting.dayTimeLabel(timestampMillis: point.timestamp, timezoneOffsetMinutes: point.timezone),
                                           value: "\(Int(point.value)) ms")
                        }
                    }
                }
            } else if granularity != .day, let graph = range?.graph {
                Section("Summary") {
                    LabeledContent("Average", value: "\(Int(graph.avg)) ms")
                    LabeledContent("Lowest", value: "\(Int(graph.lowest)) ms")
                    LabeledContent("Highest", value: "\(Int(graph.highest)) ms")
                }
                Section(granularity == .year ? "By Month" : "By Day") {
                    if graph.hrvIndexPoints.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(graph.hrvIndexPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                            LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                                           value: "\(Int(point.value)) ms")
                        }
                    }
                }
            }
        }
        .navigationTitle(Metric.hrv.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeaderControls(granularity: $granularity)
        }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                daily = try await sensorBio.fetchDailyHRV(date: dateContext.selectedDate)
            } else {
                range = try await sensorBio.fetchRangeHRV(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
