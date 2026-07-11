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


class MetricRouteContracts(unittest.TestCase):
    def test_dashboard_metric_tiles_use_the_matching_route_and_metric_type(self) -> None:
        contracts = {
            "Steps": (".stepDashMetric", "StepsDetailView()"),
            "Active Calories": (".calorieDashMetric", "CaloriesDetailView()"),
            "Resting Heart Rate": (".hrDashMetric", "HRDetailView()"),
            "Heart Rate Variability": (".hrvDashMetric", "HRVDetailView()"),
            "Respiratory Rate": (".respRateDashMetric", "RRDetailView()"),
        }
        for label, (metric_type, destination) in contracts.items():
            expected = f'metricRouteTile(label: "{label}", metric: metricsByType[{metric_type}], destination: {destination})'
            self.assertIn(expected, DASHBOARD)

    def test_each_detail_screen_declares_its_own_metric_title_fetch_and_unit(self) -> None:
        contracts = {
            "StepsDetailView.swift": ("Metric.steps.title", "fetchDailyStats", 'unit: "steps"'),
            "CaloriesDetailView.swift": ("Metric.calories.title", "fetchCalories", "SB_CalorieMetric"),
            "HRDetailView.swift": ("Metric.hr.title", "fetchDailyHR", 'unit: "bpm"'),
            "HRVDetailView.swift": ("Metric.hrv.title", "fetchDailyHRV", 'unit: "ms"'),
            "RRDetailView.swift": ("Metric.rr.title", "fetchDailyRR", 'unit: "brpm"'),
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
        self.assertIn("dashboardMetricUnit", metrics_section)
        self.assertIn("spacing: 12", metrics_section)

    def test_dashboard_units_and_baseline_copy_are_normalized(self) -> None:
        self.assertIn('case "bpm": return "bpm"', DASHBOARD)
        self.assertIn('case "ms": return "ms"', DASHBOARD)
        self.assertIn('case "/min", "brpm": return "/min"', DASHBOARD)
        self.assertIn('return "At baseline"', DASHBOARD)
        self.assertIn('return "\\(sign)\\(formatNumber(value)) \\(unit) vs baseline"', DASHBOARD)

    def test_debug_dashboard_tile_preview_uses_the_production_component(self) -> None:
        self.assertIn('case "dashboard_metric_tiles_preview":', CONTENT)
        self.assertIn("struct DashboardMetricTilesPreviewView", CONTENT)
        self.assertGreaterEqual(CONTENT.count("NoomDashboardMetricTile("), 7)
        self.assertIn('label: "Sleep"', CONTENT)
        self.assertIn('label: "Inflammation Signal"', CONTENT)


if __name__ == "__main__":
    unittest.main()
