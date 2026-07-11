import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
DESIGN = (SRC / "NoomDesignSystem.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()

LOADERS = {
    name: (SRC / name).read_text()
    for name in (
        "DashboardView.swift",
        "MainTabView.swift",
        "SleepDetailView.swift",
        "RecoveryDetailView.swift",
        "InsightsView.swift",
        "NoomProductScreens.swift",
        "StepsDetailView.swift",
        "CaloriesDetailView.swift",
        "HRDetailView.swift",
        "HRVDetailView.swift",
        "RRDetailView.swift",
    )
}


class NoomLoadingExperienceContracts(unittest.TestCase):
    def test_shared_loader_is_contextual_stable_and_reduce_motion_safe(self) -> None:
        for snippet in (
            "struct NoomLoadingExperience",
            "@Environment(\\.accessibilityReduceMotion)",
            '.accessibilityValue("Loading")',
            "NoomLoadingSkeleton",
            "repeatForever(autoreverses: true)",
            ".accessibilityLabel",
        ):
            self.assertIn(snippet, DESIGN)

    def test_all_primary_data_surfaces_use_the_shared_loader(self) -> None:
        for filename, source in LOADERS.items():
            with self.subTest(filename=filename):
                self.assertIn("NoomLoadingExperience(", source)

    def test_metric_details_do_not_collapse_to_a_centered_spinner(self) -> None:
        for filename in (
            "StepsDetailView.swift",
            "CaloriesDetailView.swift",
            "HRDetailView.swift",
            "HRVDetailView.swift",
            "RRDetailView.swift",
        ):
            with self.subTest(filename=filename):
                self.assertNotIn('ProgressView("Loading', LOADERS[filename])

    def test_deterministic_loading_preview_routes_exist(self) -> None:
        for route in (
            "loading_metric_preview",
            "loading_dashboard_preview",
            "loading_sleep_preview",
        ):
            self.assertIn(f'case "{route}"', CONTENT)
        self.assertIn("NoomLoadingPreviewView", CONTENT)


if __name__ == "__main__":
    unittest.main()
