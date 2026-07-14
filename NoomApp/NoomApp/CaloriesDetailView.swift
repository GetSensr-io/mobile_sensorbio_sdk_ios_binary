import SwiftUI
import SensorBioSDK

struct CaloriesDetailView: View {
    let dashboardSnapshot: DashboardMetricRouteSnapshot?

    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var data: SB_CaloriesTrending?
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
                ContentUnavailableView("No active calories yet", systemImage: "flame")
            case .notApplicable:
                if isLoading {
                    NoomLoadingExperience(
                        title: "Warming up your movement story",
                        detail: "Gathering active energy across your selected time.",
                        systemImage: "flame.fill",
                        accent: NoomTheme.metricAmber
                    )
                    .padding(NoomTheme.horizontalPadding)
                } else if let errorMessage {
                    ContentUnavailableView("Active calories unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if granularity == .day, let primary = dailyPrimary {
                    dayDetail(primary: primary)
                } else if granularity != .day, let metrics = data?.graph?.metrics, !metrics.isEmpty {
                    List(metrics.indices, id: \.self) { metricSection(metrics[$0]) }
                } else {
                    ContentUnavailableView("No active calories yet", systemImage: "flame")
                }
            }
        }
        .navigationTitle(Metric.calories.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { DetailHeaderControls(granularity: $granularity) }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) { await load() }
    }

    private var dashboardRouteResolution: DashboardMetricRouteResolution {
        guard granularity == .day else { return .notApplicable }
        return MetricDisplayPolicy.routeResolution(
            kind: .activeCalories,
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
        let metric = activeCaloriesMetric
        return BaselineMetricDetail(
            title: Metric.calories.title,
            symbol: "flame.fill",
            accent: .pink,
            date: dateContext.selectedDate,
            value: primary.value,
            valueText: primary.valueText,
            unit: primary.unit,
            tone: .activity,
            baseline: baseline,
            readings: [MetricReading(label: "Daily total", value: primary.readingText)] + (metric?.timeDatapoints.sorted { $0.timestamp < $1.timestamp }.map {
                MetricReading(
                    label: MetricFormatting.dayTimeLabel(timestampMillis: $0.timestamp, timezoneOffsetMinutes: $0.timezone),
                    value: "\(MetricFormatting.humanNumber(Double($0.value))) \(primary.unit)"
                )
            } ?? []),
            supportingState: supportingState
        )
    }

    private var dailyPrimary: MetricPrimaryPresentation? {
        MetricDisplayPolicy.primaryPresentation(
            kind: .activeCalories,
            dashboardSnapshot: dashboardSnapshot,
            selectedDate: dateContext.selectedDate,
            fallbackValue: activeCaloriesMetric.map(dailyTotal)
        )
    }

    private var activeCaloriesMetric: SB_CalorieMetric? {
        MetricDisplayPolicy.activeCaloriesMetric(in: data?.graph?.metrics ?? [])
    }

    private func metricSection(_ metric: SB_CalorieMetric) -> some View {
        Section(metric.name.isEmpty ? "Active calories" : metric.name) {
            LabeledContent("Average", value: "\(MetricFormatting.humanNumber(Double(metric.avgValue))) \(metric.unit)")
            ForEach(metric.datapoints.sorted { $0.date < $1.date }, id: \.date) { point in
                LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: "\(MetricFormatting.humanNumber(Double(point.value))) \(metric.unit)")
            }
        }
    }

    private func dailyTotal(_ metric: SB_CalorieMetric) -> Double {
        let total = metric.timeDatapoints.reduce(0) { $0 + Double($1.value) }
        return total > 0 ? total : Double(metric.avgValue)
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            data = try await sensorBio.fetchCalories(date: dateContext.selectedDate, granularity: granularity)
            guard granularity == .day else { baseline = nil; return }
            let observations = (try? await PersonalBaselineLoader.trailingObservations(for: .calories, selectedDate: dateContext.selectedDate)) ?? []
            guard let primary = dailyPrimary else { baseline = nil; return }
            baseline = PersonalBaseline.make(currentValue: primary.value, observations: observations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
