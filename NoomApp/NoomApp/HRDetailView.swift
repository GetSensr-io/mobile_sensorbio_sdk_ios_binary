import SwiftUI
import SensorBioSDK

struct HRDetailView: View {
    let dashboardSnapshot: DashboardMetricRouteSnapshot?

    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_HRDailyTrending?
    @State private var range: SB_HRRangeTrending?
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
                ContentUnavailableView("No heart-rate data yet", systemImage: "heart")
            case .notApplicable:
                if isLoading {
                    NoomLoadingExperience(
                        title: "Listening for your rhythm",
                        detail: "Shaping your resting heart-rate story now.",
                        systemImage: "heart.fill",
                        accent: NoomTheme.red
                    )
                    .padding(NoomTheme.horizontalPadding)
                } else if let errorMessage {
                    ContentUnavailableView("Heart rate unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if granularity == .day, let primary = dailyPrimary {
                    dayDetail(primary: primary)
                } else if let graph = range?.graph {
                    List {
                        Section("Range summary") {
                            LabeledContent("Average", value: "\(MetricFormatting.humanNumber(Double(graph.avgBpm))) bpm")
                            LabeledContent("Low", value: "\(MetricFormatting.humanNumber(Double(graph.lowest))) bpm")
                            LabeledContent("High", value: "\(MetricFormatting.humanNumber(Double(graph.highest))) bpm")
                        }
                        Section("Readings") {
                            ForEach(graph.bpmPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                                LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: "\(MetricFormatting.humanNumber(Double(point.value))) bpm")
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No heart-rate data yet", systemImage: "heart")
                }
            }
        }
        .navigationTitle(Metric.hr.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { DetailHeaderControls(granularity: $granularity) }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) { await load() }
    }

    private var dashboardRouteResolution: DashboardMetricRouteResolution {
        guard granularity == .day else { return .notApplicable }
        return MetricDisplayPolicy.routeResolution(
            kind: .restingHeartRate,
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
        let graph = daily?.graph
        return BaselineMetricDetail(
            title: Metric.hr.title,
            symbol: "heart.fill",
            accent: .red,
            date: dateContext.selectedDate,
            value: primary.value,
            valueText: primary.valueText,
            unit: primary.unit,
            tone: .heartRate,
            baseline: baseline,
            readings: [MetricReading(label: "Resting", value: primary.readingText)] + (graph.map {
                [
                    MetricReading(label: "Average", value: "\(MetricFormatting.humanNumber(Double($0.rawAvg))) \(primary.unit)"),
                    MetricReading(label: "Low", value: "\(MetricFormatting.humanNumber(Double($0.rawLowest))) \(primary.unit)"),
                    MetricReading(label: "High", value: "\(MetricFormatting.humanNumber(Double($0.rawHighest))) \(primary.unit)")
                ] + $0.heartRateTimeseriesPoints.sorted { $0.timestamp < $1.timestamp }.map {
                    MetricReading(
                        label: MetricFormatting.dayTimeLabel(timestampMillis: $0.timestamp, timezoneOffsetMinutes: $0.timezone),
                        value: "\(MetricFormatting.humanNumber(Double($0.value))) \(primary.unit)"
                    )
                }
            } ?? []),
            supportingState: supportingState
        )
    }

    private var dailyPrimary: MetricPrimaryPresentation? {
        MetricDisplayPolicy.primaryPresentation(
            kind: .restingHeartRate,
            dashboardSnapshot: dashboardSnapshot,
            selectedDate: dateContext.selectedDate,
            fallbackValue: daily?.graph.map { Double($0.restingBpm) }
        )
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                daily = try await sensorBio.fetchDailyHR(date: dateContext.selectedDate)
                let observations = (try? await PersonalBaselineLoader.trailingObservations(for: .restingHeartRate, selectedDate: dateContext.selectedDate)) ?? []
                baseline = dailyPrimary.flatMap { PersonalBaseline.make(currentValue: $0.value, observations: observations) }
            } else {
                range = try await sensorBio.fetchRangeHR(date: dateContext.selectedDate, granularity: granularity)
                baseline = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
