import SwiftUI
import SensorBioSDK

struct RRDetailView: View {
    let dashboardSnapshot: DashboardMetricRouteSnapshot?

    @Environment(AppDateContext.self) private var dateContext
    @State private var granularity: SB_ViewGranularity = .day
    @State private var daily: SB_RRDailyTrending?
    @State private var range: SB_RRRangeTrending?
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
                ContentUnavailableView("No respiratory-rate data yet", systemImage: "lungs")
            case .notApplicable:
                if isLoading {
                    NoomLoadingExperience(
                        title: "Following your overnight breathing",
                        detail: "Preparing your respiratory-rate pattern.",
                        systemImage: "lungs.fill",
                        accent: NoomTheme.metricBlue
                    )
                    .padding(NoomTheme.horizontalPadding)
                } else if let errorMessage {
                    ContentUnavailableView("Respiratory rate unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if granularity == .day, let primary = dailyPrimary {
                    dayDetail(primary: primary)
                } else if let graph = range?.graph {
                    List {
                        Section("Range summary") {
                            LabeledContent("Average", value: "\(MetricFormatting.humanNumber(Double(graph.avgBrpm))) /min")
                            LabeledContent("Low", value: "\(MetricFormatting.humanNumber(Double(graph.lowest))) /min")
                            LabeledContent("High", value: "\(MetricFormatting.humanNumber(Double(graph.highest))) /min")
                        }
                        Section("Readings") {
                            ForEach(graph.brpmPoints.sorted { $0.date < $1.date }, id: \.date) { point in
                                LabeledContent(MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: granularity), value: "\(MetricFormatting.humanNumber(Double(point.value))) /min")
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No respiratory-rate data yet", systemImage: "lungs")
                }
            }
        }
        .navigationTitle(Metric.rr.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { DetailHeaderControls(granularity: $granularity) }
        .task(id: DetailLoadKey(date: dateContext.selectedDate, granularity: granularity)) { await load() }
    }

    private var dashboardRouteResolution: DashboardMetricRouteResolution {
        guard granularity == .day else { return .notApplicable }
        return MetricDisplayPolicy.routeResolution(
            kind: .respiratoryRate,
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
            title: Metric.rr.title,
            symbol: "lungs.fill",
            accent: .teal,
            date: dateContext.selectedDate,
            value: primary.value,
            valueText: primary.valueText,
            unit: primary.unit,
            tone: .respiratory,
            baseline: baseline,
            readings: graph.map {
                [
                    MetricReading(label: "Average", value: primary.readingText),
                    MetricReading(label: "Low", value: "\(MetricFormatting.humanNumber(Double($0.rawLowest))) \(primary.unit)"),
                    MetricReading(label: "High", value: "\(MetricFormatting.humanNumber(Double($0.rawHighest))) \(primary.unit)")
                ] + $0.rawDatetimePoints.sorted { $0.timestamp < $1.timestamp }.map {
                    MetricReading(
                        label: MetricFormatting.dayTimeLabel(timestampMillis: $0.timestamp, timezoneOffsetMinutes: $0.timezone),
                        value: "\(MetricFormatting.humanNumber(Double($0.value))) \(primary.unit)"
                    )
                }
            } ?? [MetricReading(label: "Average", value: primary.readingText)],
            supportingState: supportingState
        )
    }

    private var dailyPrimary: MetricPrimaryPresentation? {
        MetricDisplayPolicy.primaryPresentation(
            kind: .respiratoryRate,
            dashboardSnapshot: dashboardSnapshot,
            selectedDate: dateContext.selectedDate,
            fallbackValue: daily?.graph.map { Double($0.brpm) }
        )
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if granularity == .day {
                daily = try await sensorBio.fetchDailyRR(date: dateContext.selectedDate)
                let observations = (try? await PersonalBaselineLoader.trailingObservations(for: .respiratoryRate, selectedDate: dateContext.selectedDate)) ?? []
                baseline = dailyPrimary.flatMap { PersonalBaseline.make(currentValue: $0.value, observations: observations) }
            } else {
                range = try await sensorBio.fetchRangeRR(date: dateContext.selectedDate, granularity: granularity)
                baseline = nil
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
