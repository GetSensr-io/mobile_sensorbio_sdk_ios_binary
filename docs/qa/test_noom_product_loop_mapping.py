#!/usr/bin/env python3
"""Truthful product-loop guards for Noom Body State -> experiment -> progress."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
DASHBOARD_STATE = (SRC / "DashboardState.swift").read_text()
DASHBOARD_VIEW = (SRC / "DashboardView.swift").read_text()
PRODUCT = (SRC / "NoomProductScreens.swift").read_text()
INSIGHTS = (SRC / "InsightsView.swift").read_text()
MAIN = (SRC / "MainTabView.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()


class NoomProductLoopMappingTests(unittest.TestCase):
    def test_body_status_is_nightly_sleep_backed_with_freshness(self) -> None:
        self.assertIn("fetchDashboardData(date: date, tzOffset: tzOffset)", DASHBOARD_STATE)
        self.assertIn("fetchSleepDetail(endDate: endDate, endTimestamp:", DASHBOARD_STATE)
        self.assertIn("nightlySleep", DASHBOARD_STATE)
        self.assertIn("enum NoomDataFreshness", DASHBOARD_STATE)
        self.assertIn("sensorBio.lastSyncd", DASHBOARD_STATE)
        self.assertIn("Stale today", DASHBOARD_VIEW)
        self.assertIn("This Body Status is not current", DASHBOARD_VIEW)
        self.assertIn("Body Status", DASHBOARD_VIEW)
        self.assertIn("BodyStatusScore.make", DASHBOARD_VIEW)
        for signal in ("Resting HR", "Nocturnal HRV", "Sleep score", "Three overnight signals, equal weight"):
            self.assertIn(signal, DASHBOARD_VIEW)
        self.assertNotIn("Recovery from Noom Band", DASHBOARD_VIEW)
        self.assertNotIn("coverageText(recovery.calibrationData)", DASHBOARD_VIEW)
        self.assertNotIn("No Recovery value was returned", DASHBOARD_VIEW)
        self.assertNotIn("fallback body score", DASHBOARD_STATE)

    def test_suggested_experiment_is_persisted_and_tied_to_body_status(self) -> None:
        self.assertIn("ProductLoopStore", DASHBOARD_STATE)
        self.assertIn("ProductLoopAPI", DASHBOARD_STATE)
        self.assertIn("DemoInstallIdentity", DASHBOARD_STATE)
        self.assertIn("/demo/v1/proposals", DASHBOARD_STATE)
        self.assertIn("ProductLoopSuggestion.eveningReset", DASHBOARD_VIEW)
        self.assertIn("Button(\"Start experiment", DASHBOARD_VIEW)
        self.assertIn("Button(\"Complete\")", DASHBOARD_VIEW)
        self.assertIn("Button(\"Cancel\")", DASHBOARD_VIEW)
        self.assertIn("Save this experiment", DASHBOARD_VIEW)
        self.assertNotIn("UserDefaults", DASHBOARD_STATE)
        self.assertNotIn("raw PPG", DASHBOARD_STATE)

    def test_body_status_is_local_and_demo_persistence_does_not_upload_health(self) -> None:
        self.assertNotIn("syncOvernightStatus", DASHBOARD_STATE)
        self.assertNotIn("restingHeartRate", DASHBOARD_STATE)
        self.assertNotIn("nocturnalHrv", DASHBOARD_STATE)
        self.assertNotIn("sleepScore", DASHBOARD_STATE)
        self.assertNotIn("syncOvernightStatus", DASHBOARD_VIEW)
        self.assertIn("BodyStatusScore.make", DASHBOARD_VIEW)

    def test_progress_uses_recovery_sleep_history_without_gap_filling(self) -> None:
        for snippet in (
            "fetchRangeRecovery(date: date, granularity: .week)",
            "fetchSleepAggregation(date: date, granularity: .week)",
            "recoveryScoreSection?.scorePoints",
            "sleepTimePoints",
            "SB_DateValuePoint",
            "Missing dates are left blank",
            "Threshold for a fuller read is 5 of 7 days",
            "NoomDiscontinuousPointTrend",
        ):
            self.assertIn(snippet, DASHBOARD_VIEW + PRODUCT + DASHBOARD_STATE)
        self.assertNotIn("interpolate", DASHBOARD_VIEW + PRODUCT)
        self.assertNotIn("compositeScore", DASHBOARD_VIEW + PRODUCT)
        self.assertIn("does not create a composite score", PRODUCT)

    def test_navigation_keeps_example_capabilities_and_adds_clean_progress_shell(self) -> None:
        self.assertIn("NoomProgressSignalsView()", MAIN)
        self.assertIn('Label("Progress", systemImage: "chart.xyaxis.line")', MAIN)
        self.assertIn('case "progress", "progress_signals"', CONTENT)
        for view in (
            "RecoveryDetailView()",
            "SleepDetailView()",
            "StepsDetailView()",
            "CaloriesDetailView()",
            "HRDetailView()",
            "HRVDetailView()",
            "RRDetailView()",
        ):
            self.assertIn(view, DASHBOARD_VIEW + CONTENT)

    def test_unsupported_simulations_are_removed_from_app_routes(self) -> None:
        for forbidden in (
            "NoomGLP1CheckInView",
            "NoomCoachPlanView",
            'case "glp1"',
            'case "coach_plan"',
            "Appetite and fullness",
            "Down 0.7 lb",
            "Start today's plan",
            "Save check-in",
            "Energy\", value: \"7/10",
        ):
            self.assertNotIn(forbidden, PRODUCT + CONTENT)


if __name__ == "__main__":
    unittest.main()
