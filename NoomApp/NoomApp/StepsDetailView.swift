import Foundation
import SwiftUI
import SensorBioSDK

struct StepsDetailView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var dailySteps: Int?
    @State private var rangePoints: [StepDailyPoint] = []
    @State private var baseline: PersonalBaseline?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading steps…")
            } else if let errorMessage {
                ContentUnavailableView("Steps unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if granularity == .day, let dailySteps {
                BaselineMetricDetail(
                    title: Metric.steps.title,
                    symbol: "figure.walk",
                    accent: .orange,
                    date: dateContext.selectedDate,
                    value: Double(dailySteps),
                    valueText: MetricFormatting.humanNumber(dailySteps),
                    unit: "steps",
                    tone: .activity,
                    baseline: baseline,
                    readings: [MetricReading(label: "Daily total", value: "\(MetricFormatting.humanNumber(dailySteps)) steps")]
                )
            } else if !rangePoints.isEmpty {
                List(rangePoints) { point in
                    LabeledContent(
                        MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity),
                        value: "\(MetricFormatting.humanNumber(point.steps)) steps"
                    )
                }
            } else {
                ContentUnavailableView("No steps yet", systemImage: "figure.walk")
            }
        }
        .navigationTitle(Metric.steps.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { DetailHeaderControls(granularity: $granularity) }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) { await load() }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        dailySteps = nil
        baseline = nil
        rangePoints = []
        defer { isLoading = false }

        let days = dayCount(for: granularity)
        let startDate = rangeStartDate(for: dateContext.selectedDate, days: days)

        do {
            let stats = try await sensorBio.fetchDailyStats(
                startDate: packedDate(startDate),
                days: Int32(days),
                includeBiometrics: false,
                includeSleep: false,
                includeSteps: true
            )
            let points = stats.days.sorted { $0.date < $1.date }.map { day in
                StepDailyPoint(date: day.date, steps: day.physicalStats.reduce(0) { $0 + Int($1.steps) })
            }

            if granularity == .day {
                dailySteps = points.last?.steps
                let history = (try? await PersonalBaselineLoader.trailingValues(for: .steps, selectedDate: dateContext.selectedDate)) ?? []
                if let dailySteps {
                    baseline = PersonalBaseline.make(currentValue: Double(dailySteps), historicalValues: history)
                }
            } else {
                rangePoints = points
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dayCount(for granularity: SB_ViewGranularity) -> Int {
        switch granularity {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        @unknown default: return 1
        }
    }

    private func rangeStartDate(for date: Date, days: Int) -> Date {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
    }

    private func packedDate(_ date: Date) -> Int32 {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Int32((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
    }
}

private struct StepDailyPoint: Identifiable {
    let date: Int32
    let steps: Int
    var id: Int32 { date }
}
