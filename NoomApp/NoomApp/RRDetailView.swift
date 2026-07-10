import SwiftUI
import SensorBioSDK

struct RRDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_RRDailyTrending?
    @State private var range: SB_RRRangeTrending?
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
                    LabeledContent("Average", value: "\(Int(graph.brpm)) brpm")
                    LabeledContent("Lowest", value: "\(Int(graph.rawLowest)) brpm")
                    LabeledContent("Highest", value: "\(Int(graph.rawHighest)) brpm")
                }
                Section("By Hour") {
                    if graph.rawDatetimePoints.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(graph.rawDatetimePoints.sorted { $0.timestamp < $1.timestamp }, id: \.timestamp) { point in
                            LabeledContent(MetricFormatting.dayTimeLabel(timestampMillis: point.timestamp, timezoneOffsetMinutes: point.timezone),
                                           value: "\(Int(point.value)) brpm")
                        }
                    }
                }
            } else if granularity != .day, let graph = range?.graph {
                Section("Summary") {
                    LabeledContent("Average", value: "\(Int(graph.avgBrpm)) brpm")
                    LabeledContent("Lowest", value: "\(Int(graph.lowest)) brpm")
                    LabeledContent("Highest", value: "\(Int(graph.highest)) brpm")
                }
                Section(granularity == .year ? "By Month" : "By Day") {
                    if graph.brpmPoints.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(graph.brpmPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                            LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                                           value: "\(Int(point.value)) brpm")
                        }
                    }
                }
            }
        }
        .navigationTitle(Metric.rr.title)
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
                daily = try await sensorBio.fetchDailyRR(date: dateContext.selectedDate)
            } else {
                range = try await sensorBio.fetchRangeRR(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
