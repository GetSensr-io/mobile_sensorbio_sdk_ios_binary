import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
METRIC = (SRC / "Metric.swift").read_text()
DASHBOARD = (SRC / "DashboardView.swift").read_text()
MAIN = (SRC / "MainTabView.swift").read_text()
PRODUCT = (SRC / "NoomProductScreens.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()
DETAIL_FILES = [
    (SRC / name).read_text()
    for name in (
        "StepsDetailView.swift",
        "CaloriesDetailView.swift",
        "HRDetailView.swift",
        "HRVDetailView.swift",
        "RRDetailView.swift",
        "SleepDetailView.swift",
        "RecoveryDetailView.swift",
    )
]


class NoomDateNavigatorContracts(unittest.TestCase):
    def test_detail_header_reuses_the_today_navigator(self) -> None:
        header = METRIC.split("struct DetailHeaderControls", 1)[1].split("struct DetailLoadKey", 1)[0]
        self.assertIn("NoomDayNavigator(selection: $ctx.selectedDate)", header)
        self.assertNotIn('DatePicker("Date"', header)
        for label in ("Day", "Week", "Month", "Year"):
            self.assertIn(f'Text("{label}")', header)

    def test_all_metric_sleep_and_recovery_details_use_the_shared_header(self) -> None:
        for source in DETAIL_FILES:
            self.assertIn("DetailHeaderControls(granularity: $granularity)", source)

    def test_sleep_and_progress_hubs_use_the_same_day_navigator(self) -> None:
        sleep_home = MAIN.split("struct SleepHomeView", 1)[1].split("final class SleepHomeState", 1)[0]
        progress = PRODUCT.split("struct NoomProgressSignalsView", 1)[1]
        self.assertIn("NoomDayNavigator(selection: $ctx.selectedDate)", sleep_home)
        self.assertIn("NoomDayNavigator(selection: $ctx.selectedDate)", progress)

    def test_today_navigator_blocks_future_dates_and_has_accessible_controls(self) -> None:
        navigator = DASHBOARD.split("struct NoomDayNavigator", 1)[1].split("struct NoomBandConnectionBanner", 1)[0]
        self.assertIn("in: ...Date()", navigator)
        self.assertIn(".disabled(Calendar.current.isDateInToday(selection))", navigator)
        for label in ("Previous day", "Choose date", "Next day"):
            self.assertIn(f'.accessibilityLabel("{label}")', navigator)

    def test_date_navigator_has_a_deterministic_preview_route(self) -> None:
        self.assertIn('case "date_navigator_preview"', CONTENT)
        self.assertIn("NoomDateNavigatorPreviewView", CONTENT)


if __name__ == "__main__":
    unittest.main()
