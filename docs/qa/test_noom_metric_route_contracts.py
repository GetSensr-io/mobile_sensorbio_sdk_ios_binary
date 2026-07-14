#!/usr/bin/env python3
"""Metric identity and unit contracts for Noom dashboard drill-ins.

These source-level contracts prevent a dashboard metric tile from silently
opening a detail screen that displays a different metric or unit.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
DASHBOARD = (SRC / "DashboardView.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()
DISPLAY_POLICY = (SRC / "MetricDisplayPolicy.swift").read_text()


class MetricRouteContracts(unittest.TestCase):
    def test_dashboard_metric_tiles_use_the_matching_route_and_metric_type(self) -> None:
        contracts = {
            "Steps": (".stepDashMetric", "StepsDetailView(dashboardSnapshot: stepsSnapshot)"),
            "Active Calories": (".calorieDashMetric", "CaloriesDetailView(dashboardSnapshot: caloriesSnapshot)"),
            "Resting Heart Rate": (".hrDashMetric", "HRDetailView(dashboardSnapshot: heartRateSnapshot)"),
            "Heart Rate Variability": (".hrvDashMetric", "HRVDetailView(dashboardSnapshot: hrvSnapshot)"),
            "Respiratory Rate": (".respRateDashMetric", "RRDetailView(dashboardSnapshot: respiratorySnapshot)"),
        }
        for label, (metric_type, destination) in contracts.items():
            self.assertIn(f"metricsByType[{metric_type}]", DASHBOARD)
            self.assertIn(f'label: "{label}"', DASHBOARD)
            self.assertIn(destination, DASHBOARD)

    def test_dashboard_and_details_share_one_immutable_primary_presentation(self) -> None:
        self.assertIn("struct DashboardMetricRouteSnapshot", DISPLAY_POLICY)
        self.assertIn("struct DashboardMetricPresentation", DISPLAY_POLICY)
        self.assertIn("struct MetricPrimaryPresentation", DISPLAY_POLICY)
        self.assertIn("static func primaryPresentation", DISPLAY_POLICY)
        self.assertIn("calendar.isDate(dashboardSnapshot.sourceDate, inSameDayAs: selectedDate)", DISPLAY_POLICY)
        self.assertIn("snapshot: DashboardMetricRouteSnapshot", DASHBOARD)
        for filename in (
            "StepsDetailView.swift",
            "CaloriesDetailView.swift",
            "HRDetailView.swift",
            "HRVDetailView.swift",
            "RRDetailView.swift",
        ):
            source = (SRC / filename).read_text()
            self.assertIn("let dashboardSnapshot: DashboardMetricRouteSnapshot?", source, filename)
            self.assertIn("MetricDisplayPolicy.primaryPresentation", source, filename)
            self.assertIn("primary.valueText", source, filename)
            self.assertIn("primary.value", source, filename)
            self.assertIn("primary.unit", source, filename)

    def test_same_day_route_state_precedes_ancillary_loading_and_errors(self) -> None:
        detail_surface = (SRC / "Metric.swift").read_text()
        self.assertIn("if let supportingState", detail_surface)
        self.assertIn("supportingCard(supportingState)", detail_surface)
        self.assertIn('title: "Additional detail unavailable"', detail_surface)
        for filename in (
            "StepsDetailView.swift",
            "CaloriesDetailView.swift",
            "HRDetailView.swift",
            "HRVDetailView.swift",
            "RRDetailView.swift",
        ):
            source = (SRC / filename).read_text()
            self.assertIn("MetricDisplayPolicy.routeResolution", source, filename)
            self.assertIn("case .available(let primary):", source, filename)
            self.assertIn("case .unavailable:", source, filename)
            self.assertIn("supportingState: supportingState", source, filename)
            self.assertLess(source.index("switch dashboardRouteResolution"), source.index("if isLoading"), filename)
        calories = (SRC / "CaloriesDetailView.swift").read_text()
        self.assertIn("else if granularity != .day, let metrics", calories)

    def test_valid_dashboard_value_without_footer_uses_neutral_copy(self) -> None:
        tile = DASHBOARD.split("private func metricRouteTile", 1)[1].split("private func missingMetricCaption", 1)[0]
        self.assertIn('caption = presentation.footerText ?? "Selected-day value"', tile)
        self.assertIn("caption = missingMetricCaption(for: label)", tile)
        self.assertNotIn("presentation?.footerText ?? missingMetricCaption", tile)

    def test_each_detail_screen_declares_its_own_metric_title_fetch_and_unit(self) -> None:
        contracts = {
            "StepsDetailView.swift": ("Metric.steps.title", "fetchDailyStats", "kind: .steps"),
            "CaloriesDetailView.swift": ("Metric.calories.title", "fetchCalories", "kind: .activeCalories"),
            "HRDetailView.swift": ("Metric.hr.title", "fetchDailyHR", "kind: .restingHeartRate"),
            "HRVDetailView.swift": ("Metric.hrv.title", "fetchDailyHRV", "kind: .heartRateVariability"),
            "RRDetailView.swift": ("Metric.rr.title", "fetchDailyRR", "kind: .respiratoryRate"),
        }
        for filename, required in contracts.items():
            source = (SRC / filename).read_text()
            for token in required:
                self.assertIn(token, source, f"{filename} missing {token}")

    def test_steps_detail_cannot_render_energy_data_or_energy_units(self) -> None:
        source = (SRC / "StepsDetailView.swift").read_text().lower()
        self.assertIn("physicalstats", source)
        self.assertIn(".steps", source)
        self.assertNotIn("kcal", source)
        self.assertNotIn("calorie", source)

    def test_dashboard_tiles_share_one_numeric_type_and_separate_units(self) -> None:
        design = (SRC / "NoomDesignSystem.swift").read_text()
        self.assertIn("struct NoomDashboardMetricTile", design)
        self.assertIn("let unit: String?", design)
        self.assertIn("design: .rounded", design)
        self.assertIn(".monospacedDigit()", design)
        self.assertIn("Text(unit)", design)
        self.assertIn("Image(systemName: systemImage)", design)
        self.assertIn('Image(systemName: "chevron.right")', design)
        self.assertIn("lineLimit(2)", design)
        caption_layout = design.split("Text(caption)", 1)[1].split('Image(systemName: "chevron.right")', 1)[0]
        self.assertIn(".lineLimit(2)", caption_layout)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", caption_layout)

    def test_sleep_and_grid_metrics_use_the_same_tile_component(self) -> None:
        metrics_section = DASHBOARD.split("private func dashboardMetrics", 1)[1].split("private func insightCard", 1)[0]
        self.assertGreaterEqual(metrics_section.count("NoomDashboardMetricTile("), 3)
        self.assertNotIn("noomSerifTitle", metrics_section)
        self.assertIn('label: "Sleep"', metrics_section)
        self.assertIn('unit: "/100"', metrics_section)
        self.assertIn('systemImage: "moon.stars.fill"', metrics_section)
        self.assertIn("MetricDisplayPolicy.routeSnapshot", metrics_section)
        self.assertIn("spacing: 12", metrics_section)

    def test_dashboard_units_and_baseline_copy_are_normalized(self) -> None:
        self.assertIn('case .restingHeartRate: return "bpm"', DISPLAY_POLICY)
        self.assertIn('case .heartRateVariability: return "ms"', DISPLAY_POLICY)
        self.assertIn('case .respiratoryRate: return "/min"', DISPLAY_POLICY)
        self.assertIn('return "At baseline"', DISPLAY_POLICY)
        self.assertIn('return "\\(sign)\\(number) \\(unit) vs baseline"', DISPLAY_POLICY)

    def test_metric_detail_reading_heading_is_truthful_for_historical_days(self) -> None:
        source = (SRC / "Metric.swift").read_text()
        self.assertIn('Text("Selected-day readings")', source)
        self.assertNotIn('Text("Today’s readings")', source)
        self.assertIn("Selected-day data is still available below.", source)
        self.assertNotIn("Today’s data is still available below.", source)

    def test_debug_dashboard_tile_preview_uses_the_production_component(self) -> None:
        self.assertIn('case "dashboard_metric_tiles_preview":', CONTENT)
        self.assertIn("struct DashboardMetricTilesPreviewView", CONTENT)
        self.assertGreaterEqual(CONTENT.count("NoomDashboardMetricTile("), 7)
        self.assertIn('label: "Sleep"', CONTENT)
        self.assertIn('label: "Inflammation Signal"', CONTENT)


if __name__ == "__main__":
    unittest.main()
