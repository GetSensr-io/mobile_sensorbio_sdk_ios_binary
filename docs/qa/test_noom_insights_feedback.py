#!/usr/bin/env python3
"""Regression contracts for the Noom+ Insights feedback fixes."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
INSIGHTS = (ROOT / "NoomApp/NoomApp/InsightsView.swift").read_text()


class InsightsFeedbackContractTests(unittest.TestCase):
    def test_population_insights_card_is_not_rendered(self) -> None:
        for token in (
            "import Charts",
            "Chart {",
            "BarMark",
            "RuleMark",
            "populationInsightsSection",
            'Text("Population insights")',
            'title: "Population insight unavailable"',
        ):
            self.assertNotIn(token, INSIGHTS)

    def test_empty_personal_payload_does_not_claim_sensor_signals_are_missing(self) -> None:
        self.assertNotIn('title: "No signals yet"', INSIGHTS)
        self.assertNotIn('title: "Signals are still warming up"', INSIGHTS)
        self.assertIn('title: "No new personal insight"', INSIGHTS)
        self.assertIn("Your health signals remain available", INSIGHTS)


if __name__ == "__main__":
    unittest.main()
