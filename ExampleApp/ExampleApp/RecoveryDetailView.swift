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
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("Loading\u{2026}").foregroundStyle(.secondary) } }
            } else if let error = errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            } else if granularity == .day, let graph = daily?.graph {
                Section("Summary") {
                    LabeledContent("Recovery", value: "\(Int(graph.goalItem.item.value))")
                    LabeledContent("Variation",
                                   value: "\(graph.variationPercentage.formatted(.number.precision(.fractionLength(1))))%")
                    LabeledContent("Resting HR", value: "\(Int(graph.restingHr)) bpm")
                    LabeledContent("Sleep", value: "\(Int(graph.sleepTimeSeconds / 3600))h \(Int(graph.sleepTimeSeconds.truncatingRemainder(dividingBy: 3600) / 60))m")
                }
                Section("Score Factors") {
                    if graph.scoreFactors.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(graph.scoreFactors.indices, id: \.self) { idx in
                            let factor = graph.scoreFactors[idx]
                            LabeledContent(factor.title) {
                                Text(factor.description)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if granularity != .day, let graph = range?.graph {
                Section("Summary") {
                    LabeledContent("Recovery", value: "\(Int(graph.goalItem.item.value))")
                    LabeledContent("Variation",
                                   value: "\(graph.variationPercentage.formatted(.number.precision(.fractionLength(1))))%")
                    LabeledContent("Resting HR", value: "\(Int(graph.restingHr)) bpm")
                    LabeledContent("Sleep", value: "\(Int(graph.sleepTimeSeconds / 3600))h \(Int(graph.sleepTimeSeconds.truncatingRemainder(dividingBy: 3600) / 60))m")
                }
                Section(granularity == .year ? "By Month" : "By Day") {
                    let points = graph.recoveryScoreSection?.scorePoints ?? []
                    if points.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(points.sorted { $0.date < $1.date }, id: \.date) { point in
                            LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                                           value: "\(Int(point.value))")
                        }
                    }
                }
            }
        }
        .navigationTitle(Metric.recovery.title)
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
                daily = try await sensorBio.fetchDailyRecovery(date: dateContext.selectedDate)
            } else {
                range = try await sensorBio.fetchRangeRecovery(date: dateContext.selectedDate, granularity: granularity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
