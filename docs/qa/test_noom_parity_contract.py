#!/usr/bin/env python3
"""Static parity contract tests for the Noom shell over the Sensor Bio ExampleApp."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
NOOM_APP = (SRC / "NoomApp.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()
SIGNIN = (SRC / "SignInView.swift").read_text()
DASHBOARD = (SRC / "DashboardView.swift").read_text()
INSIGHTS_STATE = (SRC / "InsightsState.swift").read_text()
INSIGHTS_VIEW = (SRC / "InsightsView.swift").read_text()
PRODUCT = (SRC / "NoomProductScreens.swift").read_text()


class NoomParityContractTests(unittest.TestCase):
    def test_startup_defaults_production_outside_debug_and_hydrates_session(self) -> None:
        self.assertIn("sensorBio.hydrateSession()", NOOM_APP)
        debug_start = NOOM_APP.index("#if DEBUG")
        else_start = NOOM_APP.index("#else", debug_start)
        endif = NOOM_APP.index("#endif", else_start)
        debug_body = NOOM_APP[debug_start:else_start]
        release_body = NOOM_APP[else_start:endif]
        self.assertIn("envIsDev", debug_body)
        self.assertIn("SB_SDK.environment = .production", release_body)
        self.assertNotIn("envIsDev", release_body)
        self.assertNotIn('register(defaults: ["envIsDev": true])', NOOM_APP)

    def test_environment_switch_ui_is_debug_only(self) -> None:
        self.assertIn("#if DEBUG", CONTENT)
        self.assertIn("@AppStorage(\"envIsDev\")", CONTENT)
        self.assertIn("Use staging SDK environment", CONTENT)
        self.assertIn("SB_SDK.environment = newValue ? .staging : .production", CONTENT)
        self.assertIn("sensorBio.hydrateSession()", CONTENT)
        release_region = CONTENT[CONTENT.index("#else", CONTENT.index("#if DEBUG")):CONTENT.index("#endif", CONTENT.index("#else", CONTENT.index("#if DEBUG")))]
        self.assertNotIn("envIsDev", release_region)

    def test_password_reset_button_calls_sdk_and_shows_outcome(self) -> None:
        self.assertIn("requestPasswordReset(email:", SIGNIN)
        self.assertRegex(SIGNIN, r"case \.resetSent|Reset link sent")
        self.assertNotIn('Button("Forgot password?") { }', SIGNIN)

    def test_dashboard_exposes_every_exampleapp_metric_route(self) -> None:
        for view in (
            "RecoveryDetailView()",
            "SleepDetailView()",
            "StepsDetailView()",
            "CaloriesDetailView()",
            "HRDetailView()",
            "HRVDetailView()",
            "RRDetailView()",
        ):
            self.assertIn(view, DASHBOARD)
        for metric_case in (
            ".stepDashMetric",
            ".calorieDashMetric",
            ".hrDashMetric",
            ".hrvDashMetric",
            ".respRateDashMetric",
        ):
            self.assertIn(metric_case, DASHBOARD)

    def test_debug_qa_routes_cover_all_metric_detail_screenshots(self) -> None:
        for route in (
            "sleep_detail",
            "recovery_detail",
            "steps_detail",
            "calories_detail",
            "hr_detail",
            "hrv_detail",
            "rr_detail",
        ):
            self.assertIn(f'case "{route}"', CONTENT)

    def test_population_insights_are_loaded_and_rendered(self) -> None:
        for snippet in (
            "fetchPopulationInsightsMetricList()",
            "fetchPopulationInsights(",
            "selectedPopulationMetric",
            "selectedAgeGroup",
            "selectedGender",
        ):
            self.assertIn(snippet, INSIGHTS_STATE)
        self.assertIn("populationInsightsSection", INSIGHTS_VIEW)
        self.assertIn("submitInsightsFeedback", INSIGHTS_STATE)
        self.assertIn("submitFeedback", INSIGHTS_VIEW)

    def test_unsupported_noom_product_loop_screens_are_not_release_routable(self) -> None:
        release_content = CONTENT[CONTENT.index("#else", CONTENT.index("#if DEBUG")):CONTENT.index("#endif", CONTENT.index("#else", CONTENT.index("#if DEBUG")))]
        for unsupported_view in ("NoomGLP1CheckInView", "NoomProgressSignalsView", "NoomCoachPlanView"):
            self.assertNotIn(unsupported_view, release_content)
        for empty_action in ('Button("Save check-in") { }', 'Button("Start today\'s plan") { }'):
            self.assertNotIn(empty_action, PRODUCT)
        self.assertNotRegex(PRODUCT, r"Down 0\.7 lb|Appetite and fullness|Energy\", value: \"7/10")


if __name__ == "__main__":
    unittest.main()
