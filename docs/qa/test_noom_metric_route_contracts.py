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


if __name__ == "__main__":
    unittest.main()
