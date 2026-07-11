import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
MAIN_TAB = (SRC / "MainTabView.swift").read_text()
DASHBOARD = (SRC / "DashboardView.swift").read_text()
STATE = (SRC / "DashboardState.swift").read_text()


class DashboardRefreshContractTests(unittest.TestCase):
    def test_dashboard_store_is_owned_above_the_tab_content(self) -> None:
        self.assertIn("@State private var dashboard = DashboardState()", MAIN_TAB)
        self.assertIn("@State private var productLoop = ProductLoopStore()", MAIN_TAB)
        self.assertIn(
            "DashboardView(session: session, dashboard: dashboard, productLoop: productLoop)",
            MAIN_TAB,
        )
        self.assertNotIn("@State private var dashboard = DashboardState()", DASHBOARD)
        self.assertNotIn("@State private var productLoop = ProductLoopStore()", DASHBOARD)

    def test_refresh_publishes_one_complete_snapshot_without_clearing_visible_data(self) -> None:
        self.assertIn("struct DashboardSnapshot", STATE)
        self.assertIn("let nextData", STATE)
        self.assertIn("nextNightlySleep", STATE)
        self.assertIn("snapshot = DashboardSnapshot(", STATE)

        load_body = STATE.split("func load(date: Date", 1)[1].split("func freshness", 1)[0]
        for destructive_assignment in (
            "data = nil",
            "nightlySleep = nil",
            "weeklyRecovery = nil",
            "weeklySleep = nil",
            "personalInsights = nil",
        ):
            self.assertNotIn(destructive_assignment, load_body)

    def test_automatic_tab_return_refreshes_are_deduplicated(self) -> None:
        self.assertIn("static let automaticRefreshInterval: TimeInterval = 60", STATE)
        self.assertIn("func load(date: Date, force: Bool = false) async", STATE)
        self.assertIn("guard !force, let currentSnapshot = snapshotForSameDay(as: date)", STATE)
        self.assertIn("Date().timeIntervalSince(currentSnapshot.loadedAt) < Self.automaticRefreshInterval", STATE)
        self.assertIn(".refreshable { await refreshDashboard(force: true) }", DASHBOARD)
        self.assertIn("await refreshDashboard(force: true)", DASHBOARD)

    def test_processed_sleep_forces_an_immediate_today_refresh(self) -> None:
        self.assertIn(
            ".onReceive(sensorBio.sleepStored.merge(with: sensorBio.sleepUploaded))",
            DASHBOARD,
        )
        sleep_handler = DASHBOARD.split(
            ".onReceive(sensorBio.sleepStored.merge(with: sensorBio.sleepUploaded))", 1
        )[1].split(".onReceive", 1)[0]
        self.assertNotIn("Task.sleep", sleep_handler)
        self.assertIn("refreshAfterSync()", sleep_handler)
        refresh_handler = DASHBOARD.split("private func refreshAfterSync(", 1)[1].split("private func markSyncRefreshFailed", 1)[0]
        immediate = refresh_handler.split("await refreshDashboard(force: true)", 1)[0]
        self.assertNotIn("Task.sleep", immediate)
        self.assertIn("await refreshDashboard(force: true)", refresh_handler)

    def test_tab_bar_has_an_opaque_background_that_hides_scrolling_content(self) -> None:
        self.assertIn(".toolbarBackground(.visible, for: .tabBar)", MAIN_TAB)
        self.assertIn(".toolbarBackground(NoomTheme.warmSurface, for: .tabBar)", MAIN_TAB)


if __name__ == "__main__":
    unittest.main()
