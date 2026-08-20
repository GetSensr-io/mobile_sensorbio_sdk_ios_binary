import SwiftUI
import SensorBioSDK

struct HRDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_BiometricDailyTrending?
    @State private var range: SB_HRRangeTrending?
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
                    LabeledContent("Resting BPM", value: "\(Int(graph.resting))")
                    LabeledContent("Average", value: "\(Int(graph.average))")
                    LabeledContent("Lowest", value: "\(Int(graph.lowest))")
                    LabeledContent("Highest", value: "\(Int(graph.highest))")
                    LabeledContent("Baseline", value: "\(Int(graph.baseline))")
                }
                Section("By Hour") {
                    // `points` already arrives ascending by timestamp and tagged
                    // sleep / awake; outliers are samples the server flagged as
                    // unreliable, so they are skipped.
                    let plotted = graph.points.filter { !$0.valueType.isOutlier }
                    if plotted.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(plotted, id: \.timestamp) { point in
                            LabeledContent(MetricFormatting.sampleTimeLabel(timestampMillis: point.timestamp),
                                           value: "\(Int(point.value)) bpm")
                        }
                    }
                }
            } else if granularity != .day, let graph = range?.graph {
                Section("Summary") {
                    LabeledContent("Average", value: "\(Int(graph.averageBpm))")
                    LabeledContent("Lowest", value: "\(Int(graph.lowest))")
                    LabeledContent("Highest", value: "\(Int(graph.highest))")
                }
                Section(granularity == .week ? "By Day" : granularity == .month ? "By Day" : "By Month") {
                    if graph.bpmPoints.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(graph.bpmPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                            LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                                           value: "\(Int(point.value)) bpm")
                        }
                    }
                }
            }
        }
        .navigationTitle(Metric.hr.title)
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
                daily = try await sensorBio.fetchDailyHR(date: dateContext.selectedDate)
            } else {
                range = try await sensorBio.fetchRangeHR(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
