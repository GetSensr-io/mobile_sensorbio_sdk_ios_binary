import XCTest
import SensorBioSDK
@testable import NoomApp

final class MetricDisplayPolicyTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: day,
            hour: hour
        ).date!
    }

    private func metric(
        type: SB_DashboardMetricType = .respRateDashMetric,
        value: Int = 0,
        valueFloat: Float = 0,
        unit: String? = "/min",
        footer: SB_DashboardMetricFooter = .unset
    ) -> SB_DashboardMetric {
        SB_DashboardMetric(
            metricType: type,
            value: value,
            valueFloat: valueFloat,
            valueUnit: unit,
            footer: footer
        )
    }

    func testRespiratoryDetailUsesTheExactDashboardValueUnitAndFooterForTheSameDay() {
        let sourceDate = date(13, hour: 8)
        let dashboard = MetricDisplayPolicy.presentation(
            for: metric(
                valueFloat: 16.6,
                unit: "unexpected-backend-unit",
                footer: .improvementVsBaseline(-2.2)
            ),
            sourceDate: sourceDate
        )
        let snapshot = DashboardMetricRouteSnapshot(
            kind: .respiratoryRate,
            sourceDate: sourceDate,
            presentation: dashboard
        )

        let detail = MetricDisplayPolicy.primaryPresentation(
            kind: .respiratoryRate,
            dashboardSnapshot: snapshot,
            selectedDate: date(13, hour: 22),
            fallbackValue: 17.9,
            calendar: calendar
        )

        XCTAssertEqual(dashboard?.valueText, "16.6")
        XCTAssertEqual(dashboard?.unit, "/min")
        XCTAssertEqual(dashboard?.footerText, "-2.2 /min vs baseline")
        XCTAssertEqual(detail?.valueText, dashboard?.valueText)
        XCTAssertEqual(detail?.value, dashboard?.value)
        XCTAssertEqual(detail?.unit, dashboard?.unit)
    }

    func testSameDayUnavailableRouteCannotBecomeAvailableFromDetailFallback() {
        let sourceDate = date(13, hour: 7)
        let snapshot = DashboardMetricRouteSnapshot(
            kind: .steps,
            sourceDate: sourceDate,
            presentation: nil
        )

        let detail = MetricDisplayPolicy.primaryPresentation(
            kind: .steps,
            dashboardSnapshot: snapshot,
            selectedDate: date(13, hour: 19),
            fallbackValue: 4_123,
            calendar: calendar
        )

        XCTAssertNil(detail)
    }

    func testSameDayRouteResolutionIsIndependentFromAncillaryDetailLoading() {
        let sourceDate = date(13, hour: 8)
        let presentation = MetricDisplayPolicy.presentation(
            for: metric(valueFloat: 16.6),
            sourceDate: sourceDate
        )
        let availableSnapshot = DashboardMetricRouteSnapshot(
            kind: .respiratoryRate,
            sourceDate: sourceDate,
            presentation: presentation
        )
        let missingSnapshot = DashboardMetricRouteSnapshot(
            kind: .respiratoryRate,
            sourceDate: sourceDate,
            presentation: nil
        )

        let available = MetricDisplayPolicy.routeResolution(
            kind: .respiratoryRate,
            dashboardSnapshot: availableSnapshot,
            selectedDate: date(13, hour: 22),
            calendar: calendar
        )
        guard case .available(let primary) = available else {
            return XCTFail("Expected the same-day dashboard route to remain available")
        }
        XCTAssertEqual(primary.value, 16.6, accuracy: 0.0001)
        XCTAssertEqual(primary.valueText, "16.6")
        XCTAssertEqual(primary.unit, "/min")
        XCTAssertEqual(
            MetricDisplayPolicy.routeResolution(
                kind: .respiratoryRate,
                dashboardSnapshot: missingSnapshot,
                selectedDate: date(13, hour: 22),
                calendar: calendar
            ),
            .unavailable
        )
        XCTAssertEqual(
            MetricDisplayPolicy.routeResolution(
                kind: .respiratoryRate,
                dashboardSnapshot: availableSnapshot,
                selectedDate: date(14),
                calendar: calendar
            ),
            .notApplicable
        )
    }

    func testDifferentDayUnavailableRouteUsesTheSelectedDayFallback() {
        let snapshot = DashboardMetricRouteSnapshot(
            kind: .steps,
            sourceDate: date(13),
            presentation: nil
        )

        let detail = MetricDisplayPolicy.primaryPresentation(
            kind: .steps,
            dashboardSnapshot: snapshot,
            selectedDate: date(14),
            fallbackValue: 4_123,
            calendar: calendar
        )

        XCTAssertEqual(detail?.valueText, "4,123")
        XCTAssertEqual(detail?.unit, "steps")
    }

    func testDetailDoesNotReuseDashboardValueForAnotherDay() {
        let sourceDate = date(13)
        let dashboard = MetricDisplayPolicy.presentation(
            for: metric(valueFloat: 16.6),
            sourceDate: sourceDate
        )
        let snapshot = DashboardMetricRouteSnapshot(
            kind: .respiratoryRate,
            sourceDate: sourceDate,
            presentation: dashboard
        )

        let detail = MetricDisplayPolicy.primaryPresentation(
            kind: .respiratoryRate,
            dashboardSnapshot: snapshot,
            selectedDate: date(14),
            fallbackValue: 17.9,
            calendar: calendar
        )

        XCTAssertEqual(detail?.valueText, "17.9")
        XCTAssertEqual(detail?.value ?? 0, 17.9, accuracy: 0.0001)
        XCTAssertEqual(detail?.unit, "/min")
    }

    func testDetailDoesNotReuseDashboardValueForAnotherMetric() {
        let sourceDate = date(13)
        let heartRate = MetricDisplayPolicy.presentation(
            for: metric(type: .hrDashMetric, value: 58, unit: "wrong"),
            sourceDate: sourceDate
        )
        let snapshot = DashboardMetricRouteSnapshot(
            kind: .restingHeartRate,
            sourceDate: sourceDate,
            presentation: heartRate
        )

        let respiratory = MetricDisplayPolicy.primaryPresentation(
            kind: .respiratoryRate,
            dashboardSnapshot: snapshot,
            selectedDate: date(13),
            fallbackValue: 16.6,
            calendar: calendar
        )

        XCTAssertEqual(respiratory?.valueText, "16.6")
        XCTAssertEqual(respiratory?.unit, "/min")
    }

    func testHeartRateFallsBackToIntegerFieldWhenFloatIsDefaultZero() {
        let presentation = MetricDisplayPolicy.presentation(
            for: metric(type: .hrDashMetric, value: 58, valueFloat: 0, unit: "bogus"),
            sourceDate: date(13)
        )

        XCTAssertEqual(presentation?.kind, .restingHeartRate)
        XCTAssertEqual(presentation?.value, 58)
        XCTAssertEqual(presentation?.valueText, "58")
        XCTAssertEqual(presentation?.unit, "bpm")
    }

    func testInvalidFloatStillFallsBackToValidatedIntegerField() {
        let presentation = MetricDisplayPolicy.presentation(
            for: metric(type: .hrvDashMetric, value: 42, valueFloat: .nan),
            sourceDate: date(13)
        )

        XCTAssertEqual(presentation?.value, 42)
        XCTAssertEqual(presentation?.valueText, "42")
        XCTAssertEqual(presentation?.unit, "ms")
    }

    func testPhysiologicalZeroAndInvalidValuesRemainUnavailable() {
        XCTAssertNil(MetricDisplayPolicy.presentation(for: metric(), sourceDate: date(13)))
        XCTAssertNil(MetricDisplayPolicy.presentation(for: metric(value: -1, valueFloat: -1), sourceDate: date(13)))
        XCTAssertNil(
            MetricDisplayPolicy.primaryPresentation(
                kind: .respiratoryRate,
                dashboardSnapshot: nil,
                selectedDate: date(13),
                fallbackValue: 0,
                calendar: calendar
            )
        )
    }

    func testDashboardActivityZeroRemainsUnavailableButExplicitDetailZeroIsValid() {
        let steps = MetricDisplayPolicy.presentation(
            for: metric(type: .stepDashMetric, value: 0, valueFloat: 0, unit: nil),
            sourceDate: date(13)
        )
        let calories = MetricDisplayPolicy.presentation(
            for: metric(type: .calorieDashMetric, value: 0, valueFloat: 0, unit: nil),
            sourceDate: date(13)
        )
        let detail = MetricDisplayPolicy.primaryPresentation(
            kind: .steps,
            dashboardSnapshot: nil,
            selectedDate: date(13),
            fallbackValue: 0,
            calendar: calendar
        )

        XCTAssertNil(steps)
        XCTAssertNil(calories)
        XCTAssertEqual(detail?.valueText, "0")
        XCTAssertEqual(detail?.unit, "steps")
    }

    func testActiveCaloriesDetailSelectsTheActiveSeriesInsteadOfArrayOrder() {
        let resting = SB_CalorieMetric(
            name: "Resting",
            avgValue: 1_500,
            metricType: .restingCalories
        )
        let active = SB_CalorieMetric(
            name: "Active",
            avgValue: 420,
            metricType: .activeCalories
        )

        let selected = MetricDisplayPolicy.activeCaloriesMetric(in: [resting, active])

        XCTAssertEqual(selected?.metricType, .activeCalories)
        XCTAssertEqual(selected?.avgValue, 420)
    }

    func testReadingTextUsesTheSameValueAndUnitAsTheHeadline() {
        let presentation = MetricPrimaryPresentation(value: 16.6, valueText: "16.6", unit: "/min")
        XCTAssertEqual(presentation.readingText, "16.6 /min")
    }
}
