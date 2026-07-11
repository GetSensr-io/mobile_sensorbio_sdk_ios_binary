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
            "xEndValue >= pair.xStartValue",
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


if __name__ == "__main__":
    unittest.main()
