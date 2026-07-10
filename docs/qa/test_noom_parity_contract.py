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
METRIC_FORMATTING = (SRC / "Metric.swift").read_text()
BODY_STATUS = METRIC_FORMATTING
SLEEP_HOME = (SRC / "MainTabView.swift").read_text()
NOOM_DESIGN = (SRC / "NoomDesignSystem.swift").read_text()
SLEEP_DETAIL = (SRC / "SleepDetailView.swift").read_text()
RECOVERY_DETAIL = (SRC / "RecoveryDetailView.swift").read_text()
INFLAMMATION_DETAIL = (SRC / "InflammationSignal.swift").read_text()
NUMERIC_DISPLAY_SOURCES = {
    "DashboardView.swift": DASHBOARD,
    "InsightsView.swift": INSIGHTS_VIEW,
    "RecoveryDetailView.swift": (SRC / "RecoveryDetailView.swift").read_text(),
    "SleepDetailView.swift": (SRC / "SleepDetailView.swift").read_text(),
    "HRDetailView.swift": (SRC / "HRDetailView.swift").read_text(),
    "HRVDetailView.swift": (SRC / "HRVDetailView.swift").read_text(),
    "RRDetailView.swift": (SRC / "RRDetailView.swift").read_text(),
}


class NoomParityContractTests(unittest.TestCase):
    def test_startup_respects_environment_switch_and_defaults_to_production(self) -> None:
        self.assertIn("sensorBio.hydrateSession()", NOOM_APP)
        self.assertIn('UserDefaults.standard.register(defaults: ["envIsDev": false])', NOOM_APP)
        self.assertIn('let isDev = UserDefaults.standard.bool(forKey: "envIsDev")', NOOM_APP)
        self.assertIn("SB_SDK.environment = isDev ? .staging : .production", NOOM_APP)
        self.assertNotIn("#if DEBUG", NOOM_APP)

    def test_environment_switch_ui_is_available_in_testflight(self) -> None:
        self.assertIn('@AppStorage("envIsDev") private var envIsDev: Bool = false', CONTENT)
        self.assertNotIn("#if DEBUG\n    @AppStorage", CONTENT)
        self.assertIn("Use staging SDK environment", CONTENT)
        self.assertIn("SB_SDK.environment = newValue ? .staging : .production", CONTENT)
        self.assertIn("sensorBio.hydrateSession()", CONTENT)

    def test_qa_detail_routes_are_pushed_so_back_dismisses(self) -> None:
        content = (SRC / "ContentView.swift").read_text()
        expected_routes = {
            'case "metric_baseline_preview":\n                metricDetailStack(initial: .metricBaseline)',
            'case "steps_detail":\n                metricDetailStack(initial: .stepsDetail)',
            'case "calories_detail":\n                metricDetailStack(initial: .caloriesDetail)',
            'case "hr_detail":\n                metricDetailStack(initial: .heartRateDetail)',
            'case "hrv_detail":\n                metricDetailStack(initial: .hrvDetail)',
            'case "rr_detail":\n                metricDetailStack(initial: .respiratoryRateDetail)',
        }
        for route in expected_routes:
            self.assertIn(route, content)

        for root_only_detail in (
            "NavigationStack { StepsDetailView() }",
            "NavigationStack { CaloriesDetailView() }",
            "NavigationStack { HRDetailView() }",
            "NavigationStack { HRVDetailView() }",
            "NavigationStack { RRDetailView() }",
        ):
            self.assertNotIn(root_only_detail, content)

        self.assertIn("NavigationStack(path: $path)", content)
        self.assertIn("setInitialDestination(initial)", content)
        self.assertIn("NoomMetricPreviewHub", content)

    def test_detail_pages_have_one_explicit_accessible_back_affordance(self) -> None:
        for snippet in (
            "struct NoomDetailBackButton",
            '@Environment(\\.dismiss)',
            'Image(systemName: "chevron.left")',
            '.accessibilityLabel("Back")',
            "func noomDetailBackButton()",
            "navigationBarBackButtonHidden(true)",
            "ToolbarItem(placement: .topBarLeading)",
        ):
            self.assertIn(snippet, NOOM_DESIGN)
        self.assertIn(".noomDetailBackButton()", METRIC_FORMATTING)
        self.assertIn(".noomDetailBackButton()", SLEEP_DETAIL)
        self.assertIn(".noomDetailBackButton()", RECOVERY_DETAIL)
        self.assertIn(".noomDetailBackButton()", INFLAMMATION_DETAIL)

    def test_dashboard_logo_sits_top_left_on_the_today_header_row(self) -> None:
        header = DASHBOARD[DASHBOARD.index("NoomScreen {"):DASHBOARD.index("if dashboard.isLoading")]
        self.assertIn("NoomLogoPlate(compact: true)", header)
        self.assertIn("Spacer()", header)
        self.assertNotIn("NoomTopBar(label:", header)
        self.assertNotIn("Text(\"Today\")", header)

    def test_sleep_hub_surfaces_returned_sleep_context_and_keeps_detail_drill_ins(self) -> None:
        for snippet in (
            "SleepHomeState",
            "fetchDashboardData(date:",
            "fetchSleepDetail(endDate:",
            "sleepHeroSummary",
            "sleepStagesPreview",
            "recoveryFactorsPreview",
            "Open sleep details",
            "Open recovery details",
            "No sleep session yet",
        ):
            self.assertIn(snippet, SLEEP_HOME)
        self.assertNotIn("Recovery: 78", SLEEP_HOME)
        self.assertNotIn("better than 74%", SLEEP_HOME)

    def test_sleep_hub_preview_route_is_debug_only(self) -> None:
        host = CONTENT[CONTENT.index("private struct NoomQAHost"):]
        self.assertIn('case "sleep_hub_preview"', host)
        self.assertIn("SleepHubPreviewView", host)

    def test_body_status_is_a_local_score_from_three_overnight_signals(self) -> None:
        for snippet in (
            "struct BodyStatusScore",
            "static func make(",
            "restingHeartRate",
            "nocturnalHRV",
            "sleepScore",
            "restingHeartRateComponent",
            "nocturnalHRVComponent",
            "sleepComponent",
        ):
            self.assertIn(snippet, BODY_STATUS)
        self.assertIn("dashboard.nightlySleep", DASHBOARD)
        self.assertIn("bodyStatusSection", DASHBOARD)
        self.assertIn("Resting HR", DASHBOARD)
        self.assertIn("Nocturnal HRV", DASHBOARD)
        self.assertIn("Sleep score", DASHBOARD)
        self.assertNotIn("if let recovery = data.recovery", DASHBOARD)

    def test_inflammation_signal_poc_has_a_provider_neutral_mock_only_contract(self) -> None:
        source_path = SRC / "InflammationSignal.swift"
        self.assertTrue(source_path.exists(), "Inflammation signal contract is missing")
        if not source_path.exists():
            return
        source = source_path.read_text()
        for snippet in (
            "struct InflammationSignal",
            "case valid",
            "case unavailable",
            "score: Int",
            "completedDate: Date",
            "algorithmVersion: String",
            "isPreview",
            "MockInflammationSignalProvider",
            "#if DEBUG",
        ):
            self.assertIn(snippet, source)
        self.assertNotIn("demoInstallId", source)
        self.assertNotIn("Convex", source)

    def test_body_status_v2_has_an_explicit_fourth_input_and_visible_coverage(self) -> None:
        for snippet in (
            "inflammationSignal",
            "inflammationSignalComponent",
            "availableComponentCount",
            "totalComponentCount",
            "weightedAverage",
        ):
            self.assertIn(snippet, BODY_STATUS)
        for snippet in ("Inflammation signal", "coverageDescription", "methodDescription"):
            self.assertIn(snippet, DASHBOARD)

    def test_inflammation_mock_preview_has_a_bounded_timeline_and_drill_in(self) -> None:
        source = (SRC / "InflammationSignal.swift").read_text()
        for snippet in (
            "struct InflammationPreviewTimeline",
            "30-day preview timeline",
            "Open signal details",
            "NavigationLink",
            "allSatisfy { (1...100).contains",
        ):
            self.assertIn(snippet, source)

    def test_inflammation_preview_route_is_debug_only_and_never_a_release_fixture(self) -> None:
        host = CONTENT[CONTENT.index("private struct NoomQAHost"):]
        self.assertIn('case "inflammation_preview"', host)
        self.assertIn("InflammationSignalPreviewView", host)
        release_content = CONTENT[CONTENT.index("#else", CONTENT.index("#if DEBUG")):CONTENT.index("#endif", CONTENT.index("#else", CONTENT.index("#if DEBUG")))]
        self.assertNotIn("InflammationSignalPreviewView", release_content)

    def test_signed_out_home_uses_lifestyle_carousel_with_auth_actions(self) -> None:
        self.assertIn("struct NoomWelcomeCarousel", CONTENT)
        self.assertIn(".tabViewStyle(.page(indexDisplayMode: .never))", CONTENT)
        for asset in ("WelcomeMorning", "WelcomeKitchen", "WelcomeEvening"):
            self.assertIn(f'imageName: "{asset}"', CONTENT)
        self.assertIn('Text("Sign in")', CONTENT)
        self.assertIn('Text("Create account")', CONTENT)

    def test_numeric_metrics_use_a_localized_human_number_formatter(self) -> None:
        self.assertIn("static func humanNumber(_ value: Int)", METRIC_FORMATTING)
        self.assertIn("value.formatted(.number)", METRIC_FORMATTING)
        for filename, source in NUMERIC_DISPLAY_SOURCES.items():
            self.assertIn("MetricFormatting.humanNumber", source, filename)

    def test_sign_in_uses_an_accessible_full_bleed_lifestyle_hero(self) -> None:
        for token in ("struct SignInFullBleedHero", 'Image("WelcomeMorning")', "SignInFullBleedHero()", "ignoresSafeArea", "NoomLogoPlate", "Continue your everyday plan"):
            self.assertIn(token, SIGNIN)

    def test_password_reset_button_calls_sdk_and_shows_outcome(self) -> None:
        self.assertIn("requestPasswordReset(email:", SIGNIN)
        self.assertRegex(SIGNIN, r"case \.resetSent|Reset link sent")
        self.assertNotIn('Button("Forgot password?") { }', SIGNIN)

    def test_dashboard_exposes_every_exampleapp_metric_route(self) -> None:
        for view in (
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
            "signin_preview",
            "steps_detail",
            "calories_detail",
            "hr_detail",
            "hrv_detail",
            "rr_detail",
            "record_activity",
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

    def test_recording_surface_uses_sdk_owned_activity_and_spot_check_orchestration(self) -> None:
        main_tabs = (SRC / "MainTabView.swift").read_text()
        self.assertIn("struct RecordActivityView", main_tabs)
        for token in ("recordDetailedBiometrics", "recordActivity", "finishCurrentRecording", "pauseRecording", "resumeRecording", "awaitActiveRecordingCompletion"):
            self.assertIn(token, main_tabs)
        self.assertIn("RecordActivityView()", DASHBOARD)

    def test_unsupported_noom_product_loop_screens_are_not_release_routable(self) -> None:
        release_content = CONTENT[CONTENT.index("#else", CONTENT.index("#if DEBUG")):CONTENT.index("#endif", CONTENT.index("#else", CONTENT.index("#if DEBUG")))]
        for unsupported_view in ("NoomGLP1CheckInView", "NoomProgressSignalsView", "NoomCoachPlanView"):
            self.assertNotIn(unsupported_view, release_content)
        for empty_action in ('Button("Save check-in") { }', 'Button("Start today\'s plan") { }'):
            self.assertNotIn(empty_action, PRODUCT)
        self.assertNotRegex(PRODUCT, r"Down 0\.7 lb|Appetite and fullness|Energy\", value: \"7/10")


if __name__ == "__main__":
    unittest.main()
