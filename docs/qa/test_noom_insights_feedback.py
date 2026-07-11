#!/usr/bin/env python3
"""Regression contracts for the Noom+ Insights feedback fixes."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
INSIGHTS = (ROOT / "NoomApp/NoomApp/InsightsView.swift").read_text()


class InsightsFeedbackContractTests(unittest.TestCase):
    def test_population_histogram_uses_dynamic_axis_and_marks_the_user(self) -> None:
        for token in (
            "import Charts",
            "Chart {",
            "BarMark",
            "RuleMark",
            "histogramYAxisMaximum",
            ".chartYScale(domain: 0...yAxisMaximum)",
            'Text("You")',
        ):
            self.assertIn(token, INSIGHTS)

        self.assertNotIn("min(120, pair.yValue * 120)", INSIGHTS)

    def test_population_histogram_exposes_readable_axes(self) -> None:
        for token in (
            ".chartXAxis",
            ".chartYAxis",
            "AxisMarks",
            "AxisValueLabel",
        ):
            self.assertIn(token, INSIGHTS)

    def test_empty_personal_payload_does_not_claim_sensor_signals_are_missing(self) -> None:
        self.assertNotIn('title: "No signals yet"', INSIGHTS)
        self.assertNotIn('title: "Signals are still warming up"', INSIGHTS)
        self.assertIn('title: "No new personal insight"', INSIGHTS)
        self.assertIn("Your health signals remain available", INSIGHTS)


if __name__ == "__main__":
    unittest.main()
