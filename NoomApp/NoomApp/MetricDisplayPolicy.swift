import Foundation
import SensorBioSDK

/// App-owned identity for the dashboard metrics that have drill-in pages.
enum DashboardMetricKind: Equatable, Sendable {
    case steps
    case activeCalories
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate

    var canonicalUnit: String {
        switch self {
        case .steps: return "steps"
        case .activeCalories: return "kcal"
        case .restingHeartRate: return "bpm"
        case .heartRateVariability: return "ms"
        case .respiratoryRate: return "/min"
        }
    }

    fileprivate var permitsZero: Bool {
        switch self {
        case .steps, .activeCalories: return true
        case .restingHeartRate, .heartRateVariability, .respiratoryRate: return false
        }
    }
}

/// Immutable value handed from a dashboard tile to its detail destination.
/// The detail endpoint can still supply the chart and secondary readings, but
/// this preserves the exact primary value the person tapped.
struct DashboardMetricPresentation: Equatable, Sendable {
    let kind: DashboardMetricKind
    let sourceDate: Date
    let value: Double
    let valueText: String
    let unit: String
    let footerText: String?
}

/// Route context preserves both availability and value provenance. The
/// snapshot itself is non-optional for dashboard navigation, so a missing
/// presentation remains explicitly missing instead of being confused with a
/// detail screen opened outside the dashboard.
struct DashboardMetricRouteSnapshot: Equatable, Sendable {
    let kind: DashboardMetricKind
    let sourceDate: Date
    let presentation: DashboardMetricPresentation?
}

struct MetricPrimaryPresentation: Equatable, Sendable {
    let value: Double
    let valueText: String
    let unit: String

    var readingText: String { "\(valueText) \(unit)" }
}

enum DashboardMetricRouteResolution: Equatable, Sendable {
    case notApplicable
    case unavailable
    case available(MetricPrimaryPresentation)
}

enum MetricDisplayPolicy {
    static func activeCaloriesMetric(in metrics: [SB_CalorieMetric]) -> SB_CalorieMetric? {
        metrics.first { $0.metricType == .activeCalories }
    }

    static func routeSnapshot(
        kind: DashboardMetricKind,
        metric: SB_DashboardMetric?,
        sourceDate: Date
    ) -> DashboardMetricRouteSnapshot {
        let routePresentation: DashboardMetricPresentation?
        if let metric,
           let candidate = presentation(for: metric, sourceDate: sourceDate),
           candidate.kind == kind {
            routePresentation = candidate
        } else {
            routePresentation = nil
        }
        return DashboardMetricRouteSnapshot(
            kind: kind,
            sourceDate: sourceDate,
            presentation: routePresentation
        )
    }

    static func presentation(
        for metric: SB_DashboardMetric,
        sourceDate: Date
    ) -> DashboardMetricPresentation? {
        guard let kind = kind(for: metric.metricType),
              let value = preferredValue(for: metric)
        else { return nil }

        let unit = kind.canonicalUnit
        return DashboardMetricPresentation(
            kind: kind,
            sourceDate: sourceDate,
            value: value,
            valueText: MetricFormatting.humanNumber(value),
            unit: unit,
            footerText: footerText(metric.footer, unit: unit)
        )
    }

    static func routeResolution(
        kind: DashboardMetricKind,
        dashboardSnapshot: DashboardMetricRouteSnapshot?,
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> DashboardMetricRouteResolution {
        guard let dashboardSnapshot,
              dashboardSnapshot.kind == kind,
              calendar.isDate(dashboardSnapshot.sourceDate, inSameDayAs: selectedDate)
        else { return .notApplicable }

        guard let dashboard = dashboardSnapshot.presentation,
              dashboard.kind == kind,
              calendar.isDate(dashboard.sourceDate, inSameDayAs: dashboardSnapshot.sourceDate)
        else { return .unavailable }

        return .available(
            MetricPrimaryPresentation(
                value: dashboard.value,
                valueText: dashboard.valueText,
                unit: dashboard.unit
            )
        )
    }

    /// Resolves a detail page's primary value. A same-day, same-metric
    /// dashboard route snapshot wins over the independently fetched detail
    /// summary, guaranteeing value and missing-state parity. Another date,
    /// another metric, or a detail opened outside the dashboard uses its own
    /// validated detail value instead.
    static func primaryPresentation(
        kind: DashboardMetricKind,
        dashboardSnapshot: DashboardMetricRouteSnapshot?,
        selectedDate: Date,
        fallbackValue: Double?,
        calendar: Calendar = .current
    ) -> MetricPrimaryPresentation? {
        switch routeResolution(
            kind: kind,
            dashboardSnapshot: dashboardSnapshot,
            selectedDate: selectedDate,
            calendar: calendar
        ) {
        case .available(let presentation):
            return presentation
        case .unavailable:
            return nil
        case .notApplicable:
            break
        }

        guard let fallbackValue, isUsable(fallbackValue, for: kind) else { return nil }
        return MetricPrimaryPresentation(
            value: fallbackValue,
            valueText: MetricFormatting.humanNumber(fallbackValue),
            unit: kind.canonicalUnit
        )
    }

    private static func kind(for metricType: SB_DashboardMetricType) -> DashboardMetricKind? {
        switch metricType {
        case .stepDashMetric: return .steps
        case .calorieDashMetric: return .activeCalories
        case .hrDashMetric: return .restingHeartRate
        case .hrvDashMetric: return .heartRateVariability
        case .respRateDashMetric: return .respiratoryRate
        case .spo2DashMetric, .temperatureDashMetric, .unknown: return nil
        @unknown default: return nil
        }
    }

    /// SDK dashboard values use valueFloat when populated and value as their
    /// integer fallback. Validation happens before falling back so NaN,
    /// infinity, negative values, and dashboard zero sentinels never reach the
    /// UI. Explicit zero totals returned by activity detail endpoints remain
    /// valid through `primaryPresentation`.
    private static func preferredValue(for metric: SB_DashboardMetric) -> Double? {
        let floatValue = Double(metric.valueFloat)
        if floatValue.isFinite && floatValue > 0 {
            return floatValue
        }

        let integerValue = Double(metric.value)
        if integerValue.isFinite && integerValue > 0 {
            return integerValue
        }

        return nil
    }

    private static func isUsable(_ value: Double, for kind: DashboardMetricKind) -> Bool {
        guard value.isFinite else { return false }
        return kind.permitsZero ? value >= 0 : value > 0
    }

    private static func footerText(
        _ footer: SB_DashboardMetricFooter,
        unit: String
    ) -> String? {
        switch footer {
        case .avgValue(let value):
            guard value.isFinite else { return nil }
            return "Average \(MetricFormatting.humanNumber(value))"
        case .improvementVsBaseline(let value):
            guard value.isFinite else { return nil }
            guard abs(value) >= 0.05 else { return "At baseline" }
            let sign = value > 0 ? "+" : ""
            let number = MetricFormatting.humanNumber(value)
            return "\(sign)\(number) \(unit) vs baseline"
        case .unset:
            return nil
        @unknown default:
            return nil
        }
    }
}
