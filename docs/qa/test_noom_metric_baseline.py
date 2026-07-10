#!/usr/bin/env python3
"""Contract coverage for personal-baseline metric details."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
BASELINE_PATH = SRC / "Metric.swift"
DETAIL_PATH = BASELINE_PATH


class PersonalBaselineContracts(unittest.TestCase):
    def test_baseline_is_trailing_30_days_with_a_minimum_evidence_gate(self) -> None:
        source = BASELINE_PATH.read_text()
        self.assertIn("static let trailingDays = 30", source)
        self.assertIn("static let minimumSampleCount = 14", source)
        self.assertIn("calendar.date(byAdding: .day, value: -trailingDays", source)
        self.assertIn("fetchDailyStats", source)
        self.assertIn("includeBiometrics: true", source)
        self.assertIn("includeSteps: true", source)

    def test_baseline_uses_robust_personal_statistics_not_population_targets(self) -> None:
        source = BASELINE_PATH.read_text()
        for token in ("median(", "medianAbsoluteDeviation", "usualRange", "sampleCount"):
            self.assertIn(token, source)
        baseline_block = source[source.index("struct PersonalBaseline"):source.index("enum BaselineMetric")]
        self.assertNotIn("population", baseline_block.lower())

    def test_steps_detail_uses_step_counts_and_never_uses_energy_units(self) -> None:
        source = (SRC / "StepsDetailView.swift").read_text()
        self.assertIn("fetchDailyStats", source)
        self.assertIn("physicalStats", source)
        self.assertIn(".steps", source)
        self.assertIn('unit: "steps"', source)
        self.assertNotIn("unit: metric.unit", source)
        self.assertNotIn("\\(metric.unit)", source)

    def test_detail_pages_share_the_baseline_first_design(self) -> None:
        design = DETAIL_PATH.read_text()
        for token in ("struct BaselineMetricDetail", "30-day personal baseline", "Typical range", "Not a medical assessment", "30-day median", "selected-day marker", "medianLine"):
            self.assertIn(token, design)
        for filename in ("StepsDetailView.swift", "CaloriesDetailView.swift", "HRDetailView.swift", "HRVDetailView.swift", "RRDetailView.swift"):
            self.assertIn("BaselineMetricDetail", (SRC / filename).read_text(), filename)


if __name__ == "__main__":
    unittest.main()
