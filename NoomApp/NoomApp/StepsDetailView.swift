import Foundation
import SwiftUI
import SensorBioSDK

struct StepsDetailView: View {
    let dashboardSnapshot: DashboardMetricRouteSnapshot?

    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var dailySteps: Int?
    @State private var rangePoints: [StepDailyPoint] = []
    @State private var baseline: PersonalBaseline?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(dashboardSnapshot: DashboardMetricRouteSnapshot? = nil) {
        self.dashboardSnapshot = dashboardSnapshot
    }

    var body: some View {
        Group {
            switch dashboardRouteResolution {
            case .available(let primary):
                dayDetail(primary: primary, supportingState: supportingState)
            case .unavailable:
                ContentUnavailableView("No steps yet", systemImage: "figure.walk")
            case .notApplicable:
                if isLoading {
                    NoomLoadingExperience(
                        title: "Counting up your day",
                        detail: "Bringing your movement into focus.",
                        systemImage: "figure.walk",
                        accent: NoomTheme.metricGreen
                    )
                    .padding(NoomTheme.horizontalPadding)
                } else if let errorMessage {
                    ContentUnavailableView("Steps unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if granularity == .day, let primary = dailyPrimary {
                    dayDetail(primary: primary)
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
        }
        .navigationTitle(Metric.steps.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { DetailHeaderControls(granularity: $granularity) }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) { await load() }
    }

    private var dashboardRouteResolution: DashboardMetricRouteResolution {
        guard granularity == .day else { return .notApplicable }
        return MetricDisplayPolicy.routeResolution(
            kind: .steps,
            dashboardSnapshot: dashboardSnapshot,
            selectedDate: dateContext.selectedDate
        )
    }

    private var supportingState: MetricDetailSupportingState? {
        if isLoading { return .loading }
        if let errorMessage { return .error(errorMessage) }
        return nil
    }

    private func dayDetail(
        primary: MetricPrimaryPresentation,
        supportingState: MetricDetailSupportingState? = nil
    ) -> some View {
        BaselineMetricDetail(
            title: Metric.steps.title,
            symbol: "figure.walk",
            accent: .orange,
            date: dateContext.selectedDate,
            value: primary.value,
            valueText: primary.valueText,
            unit: primary.unit,
            tone: .activity,
            baseline: baseline,
            readings: [MetricReading(label: "Daily total", value: primary.readingText)],
            supportingState: supportingState
        )
    }

    private var dailyPrimary: MetricPrimaryPresentation? {
        MetricDisplayPolicy.primaryPresentation(
            kind: .steps,
            dashboardSnapshot: dashboardSnapshot,
            selectedDate: dateContext.selectedDate,
            fallbackValue: dailySteps.map(Double.init)
        )
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
                let observations = (try? await PersonalBaselineLoader.trailingObservations(for: .steps, selectedDate: dateContext.selectedDate)) ?? []
                if let primary = dailyPrimary {
                    baseline = PersonalBaseline.make(currentValue: primary.value, observations: observations)
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
