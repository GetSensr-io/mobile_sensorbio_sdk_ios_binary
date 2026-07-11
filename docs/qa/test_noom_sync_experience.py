import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
DASHBOARD = (SRC / "DashboardView.swift").read_text()
STATE = (SRC / "DashboardState.swift").read_text()
MAIN_TAB = (SRC / "MainTabView.swift").read_text()
SLEEP_DETAIL = (SRC / "SleepDetailView.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()
README = (ROOT / "NoomApp/README.md").read_text()
POD_LOCK = (ROOT / "NoomApp/Podfile.lock").read_text()
with (SRC / "Info.plist").open("rb") as handle:
    INFO = plistlib.load(handle)


class NoomSyncExperienceContracts(unittest.TestCase):
    def test_v013_is_integrated_and_forced_refresh_bypasses_sdk_cache(self) -> None:
        self.assertIn("SensorBioSDK (0.13.0)", POD_LOCK)
        load_body = STATE.split("func load(date: Date", 1)[1].split("func freshness", 1)[0]
        for snippet in (
            "fetchDashboardData(date: date, tzOffset: tzOffset, forceRemote: forceRemote)",
            "fetchSleepDetail(\n",
            "endTimestamp: Int64(sleepSession.endTimestamp),\n                    forceRemote: forceRemote",
            "fetchRangeRecovery(date: date, granularity: .week, forceRemote: forceRemote)",
            "fetchSleepAggregation(date: date, granularity: .week, forceRemote: forceRemote)",
        ):
            self.assertIn(snippet, load_body)

    def test_top_badge_has_determinate_sync_progress_and_refresh_phases(self) -> None:
        badge = MAIN_TAB.split("struct BandBatteryBadge", 1)[1].split("/// A deliberate entry point", 1)[0]
        for snippet in (
            "sensorBio.deviceSyncing",
            "sensorBio.percentSynced",
            'Text("\\(clampedProgress)%")',
            'ProgressView(value: Double(clampedProgress), total: 100)',
            '.frame(width: 64)',
            'Text("Updating")',
            'Text("Updated")',
            'Text(issue == .deviceUpload ? "Sync issue" : "Data issue")',
            'Latest data sync failed',
            'Latest dashboard update failed',
            'Noom Band syncing, \\(clampedProgress) percent',
        ):
            self.assertIn(snippet, badge)
        self.assertNotIn('Text("Retry")', badge)
        self.assertIn("BandBatteryBadge(", DASHBOARD)
        self.assertIn("isApplyingSyncUpdate: isApplyingSyncUpdate", DASHBOARD)

    def test_sync_completion_starts_an_immediate_remote_dashboard_refresh(self) -> None:
        self.assertIn(".onReceive(sensorBio.syncCompleted)", DASHBOARD)
        completion_handler = DASHBOARD.split(".onReceive(sensorBio.syncCompleted)", 1)[1].split(".onReceive", 1)[0]
        self.assertIn("result?.acknowledge == true", completion_handler)
        self.assertIn("markSyncRefreshFailed()", completion_handler)
        self.assertIn("refreshAfterSync(bypassThrottle: true)", completion_handler)
        handler = DASHBOARD.split("private func refreshAfterSync(", 1)[1].split("private func markSyncRefreshFailed", 1)[0]
        self.assertIn("await refreshDashboard(force: true)", handler)
        immediate = handler.split("await refreshDashboard(force: true)", 1)[0]
        self.assertNotIn("Task.sleep", immediate)
        self.assertIn("isApplyingSyncUpdate = true", handler)
        self.assertIn("showsSyncUpdated = true", handler)
        self.assertIn("activeSyncRefreshID == refreshID", handler)
        self.assertIn("guard dashboard.errorMessage == nil", handler)
        self.assertIn("if !bypassThrottle", handler)

    def test_sync_issue_is_cause_specific_and_not_sticky(self) -> None:
        self.assertIn("syncIssue = .deviceUpload", DASHBOARD)
        self.assertIn("syncIssue = .dashboardRefresh", DASHBOARD)
        self.assertIn(".refreshable { await refreshDashboardFromUser() }", DASHBOARD)
        manual = DASHBOARD.split("private func refreshDashboardFromUser()", 1)[1].split("private func refreshAfterSync", 1)[0]
        self.assertIn("if syncIssue == .dashboardRefresh, dashboard.errorMessage == nil", manual)
        self.assertIn("syncIssue = nil", manual)
        self.assertIn(".onReceive(sensorBio.$deviceSyncing)", DASHBOARD)
        new_cycle = DASHBOARD.split(".onReceive(sensorBio.$deviceSyncing)", 1)[1].split(".onReceive", 1)[0]
        self.assertIn("if isSyncing", new_cycle)
        self.assertIn("syncIssue = nil", new_cycle)

    def test_background_sync_matches_sdk_v013_contract(self) -> None:
        self.assertIn("bluetooth-central", INFO.get("UIBackgroundModes", []))
        self.assertNotIn("fetch", INFO.get("UIBackgroundModes", []))
        self.assertNotIn("processing", INFO.get("UIBackgroundModes", []))
        self.assertNotIn("BGTaskSchedulerPermittedIdentifiers", INFO)
        self.assertNotIn("registerBGTasks", README)
        self.assertIn("no `BGTaskScheduler` registration is required", README)

    def test_missing_metrics_use_specific_inviting_copy_not_open(self) -> None:
        metrics = DASHBOARD.split("private func dashboardMetrics", 1)[1].split("private var inflammationMetricTile", 1)[0]
        self.assertNotIn('value: "Open"', metrics)
        self.assertNotIn('?? "Open"', metrics)
        for snippet in (
            'caption: "Your sleep story starts tonight"',
            'value: "—"',
        ):
            self.assertIn(snippet, metrics)
        self.assertIn('missingMetricCaption(for: label)', DASHBOARD)

    def test_no_sleep_states_are_a_guided_first_night_experience(self) -> None:
        for snippet in (
            "struct NoomFirstNightCard",
            'var title: String = "Tonight is night one"',
            'title: "Wear your band"',
            'title: "Wake & sync"',
            'title: "Meet your sleep story"',
        ):
            self.assertIn(snippet, MAIN_TAB)
        no_session = MAIN_TAB.split("private var noSessionCard", 1)[1].split("private func sleepHeroSummary", 1)[0]
        self.assertIn("NoomFirstNightCard", no_session)
        self.assertNotIn('"Reconnect Noom Band"', no_session)
        self.assertIn("bandReadyForTonight", no_session)
        self.assertIn('case "sleep_empty_preview"', CONTENT)
        self.assertIn('case "dashboard_no_sleep_preview"', CONTENT)
        self.assertIn("NoomFirstNightCard", SLEEP_DETAIL)
        self.assertIn("shouldShowFirstNight", SLEEP_DETAIL)
        self.assertIn("No sleep session for this date", SLEEP_DETAIL)
        self.assertIn("NoomSleepHistory.hasRecordedSleep(for:", SLEEP_DETAIL)
        self.assertIn("NoomSleepHistory.recordSleep(for: requestUserID)", STATE)
        self.assertIn("recordedSleepKey(for userID: String?)", MAIN_TAB)
        self.assertIn('return "noomHasRecordedSleep.\\(account)"', MAIN_TAB)
        self.assertIn(".onReceive(sensorBio.sleepStored.merge(with: sensorBio.sleepUploaded))", MAIN_TAB)
        self.assertIn(".onReceive(sensorBio.syncCompleted)", SLEEP_DETAIL)
        self.assertIn("activeRequestID == requestID", MAIN_TAB)
        self.assertIn("activeRequestID == requestID", SLEEP_DETAIL)
        self.assertIn("forceRemote: forceRemote", MAIN_TAB)
        self.assertIn("load(forceRemote: true)", SLEEP_DETAIL)


if __name__ == "__main__":
    unittest.main()
