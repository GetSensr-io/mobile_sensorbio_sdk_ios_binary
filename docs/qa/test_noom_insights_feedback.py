#!/usr/bin/env python3
"""Regression contracts for the Noom+ Insights feedback fixes."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
INSIGHTS = (ROOT / "NoomApp/NoomApp/InsightsView.swift").read_text()


class InsightsFeedbackContractTests(unittest.TestCase):
    def test_population_histogram_filters_invalid_values_and_marks_the_user(self) -> None:
        for token in (
            "import Charts",
            "Chart {",
            "RectangleMark",
            "yStart: .value(\"Baseline\", 0)",
            "yEnd: .value(\"Population\", bucket.population)",
            "RuleMark",
            "validHistogramData",
            "xStartValue.isFinite",
            "xEndValue.isFinite",
            "yValue.isFinite",
            "xEndValue > pair.xStartValue",
            ".chartXScale(domain: xAxisDomain)",
            ".chartXAxisLabel",
            ".chartYAxisLabel",
            "populationInsightsSection",
            'Text("Population insights")',
        ):
            self.assertIn(token, INSIGHTS)

    def test_population_radar_is_rendered_as_a_comparison_graph(self) -> None:
        for token in (
            "PopulationRadarChartView",
            "radarRelativePoints",
            "Canvas",
            'Text("You")',
            'legendItem(title: "Population"',
        ):
            self.assertIn(token, INSIGHTS)

    def test_partial_radar_payload_uses_a_nonblank_fallback(self) -> None:
        self.assertIn("radarData.count >= 3", INSIGHTS)
        self.assertIn("PopulationRadarFallbackView", INSIGHTS)

    def test_radar_clamps_each_sdk_percentile_without_global_rescaling(self) -> None:
        radar_start = INSIGHTS.index("private func radarRelativePoints")
        radar_end = INSIGHTS.index("private func personalCards", radar_start)
        radar_source = INSIGHTS[radar_start:radar_end]
        self.assertIn("min(1, max(0, point.relativePair.userValue))", radar_source)
        self.assertIn("min(1, max(0, point.relativePair.populationValue))", radar_source)
        self.assertNotIn("let scale", radar_source)

    def test_out_of_range_user_value_does_not_expand_histogram_domain(self) -> None:
        chart_start = INSIGHTS.index("private struct PopulationHistogramChartView")
        chart_end = INSIGHTS.index("private struct PopulationRadarDatum", chart_start)
        chart_source = INSIGHTS[chart_start:chart_end]
        self.assertIn("visibleUserValue", chart_source)
        self.assertIn("xAxisDomain.contains(userValue)", chart_source)
        domain_start = chart_source.index("private var xAxisDomain")
        domain_end = chart_source.index("var body", domain_start)
        self.assertNotIn("values.append(userValue)", chart_source[domain_start:domain_end])

    def test_population_filter_controls_expose_selected_state(self) -> None:
        self.assertGreaterEqual(INSIGHTS.count(".accessibilityAddTraits("), 3)
        self.assertIn(".isSelected", INSIGHTS)

    def test_population_graph_has_a_deterministic_debug_preview(self) -> None:
        self.assertIn("PopulationInsightsGraphPreviewView", INSIGHTS)
        content = (ROOT / "NoomApp/NoomApp/ContentView.swift").read_text()
        self.assertIn('case "population_insights_preview"', content)

    def test_population_refresh_clears_stale_graphs_and_owns_latest_request(self) -> None:
        state = (ROOT / "NoomApp/NoomApp/InsightsState.swift").read_text()
        for token in (
            "activePopulationRequestID",
            "guard activePopulationRequestID == requestID else { return }",
            "populationHistogram = nil",
            "populationRadarChart = nil",
        ):
            self.assertIn(token, state)
        start = state.index("func loadPopulation() async")
        first_fetch = state.index("sensorBio.fetchPopulationInsights(", start)
        self.assertLess(state.index("populationHistogram = nil", start), first_fetch)
        self.assertLess(state.index("populationRadarChart = nil", start), first_fetch)

    def test_empty_personal_payload_does_not_render_a_placeholder_card(self) -> None:
        self.assertNotIn('title: "No signals yet"', INSIGHTS)
        self.assertNotIn('title: "Signals are still warming up"', INSIGHTS)
        self.assertNotIn('title: "No new personal insight"', INSIGHTS)
        self.assertNotIn("personalInsightUnavailableCard", INSIGHTS)

    def test_personal_service_failure_remains_visible_without_raw_sdk_text(self) -> None:
        state = (ROOT / "NoomApp/NoomApp/InsightsState.swift").read_text()
        self.assertIn('title: "Personal insights unavailable"', INSIGHTS)
        self.assertIn("personalErrorMessage", state)
        self.assertNotIn("personalError = error.localizedDescription", state)

    def test_population_retry_preserves_valid_filter_selections(self) -> None:
        state = (ROOT / "NoomApp/NoomApp/InsightsState.swift").read_text()
        retry_start = state.index("func retryPopulation() async")
        retry_end = state.index("func populationErrorMessage", retry_start)
        retry_source = state[retry_start:retry_end]
        self.assertNotIn("selectedPopulationMetric = nil", retry_source)
        self.assertNotIn("selectedAgeGroup = nil", retry_source)
        self.assertIn("first(where:", state)


if __name__ == "__main__":
    unittest.main()
