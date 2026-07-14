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
COORDINATOR = (SRC / "SleepProcessingCoordinator.swift").read_text()
README = (ROOT / "NoomApp/README.md").read_text()
POD_LOCK = (ROOT / "NoomApp/Podfile.lock").read_text()
with (SRC / "Info.plist").open("rb") as handle:
    INFO = plistlib.load(handle)


class NoomSyncExperienceContracts(unittest.TestCase):
    def test_v013_is_integrated_and_forced_refresh_bypasses_sdk_cache(self) -> None:
        self.assertIn("SensorBioSDK (0.13.0)", POD_LOCK)
        load_body = STATE.split("func load(date: Date", 1)[1].split("private func snapshotForSameDay", 1)[0]
        for snippet in (
            "fetchDashboardData(date: date, tzOffset: tzOffset, forceRemote: forceRemote)",
            "fetchRangeRecovery(date: date, granularity: .week, forceRemote: forceRemote)",
            "fetchSleepAggregation(date: date, granularity: .week, forceRemote: forceRemote)",
        ):
            self.assertIn(snippet, load_body)
        self.assertNotIn("fetchSleepDetail(", STATE)
        self.assertIn("fetchSleepSessions", COORDINATOR)
        self.assertIn("fetchSleepDetail", COORDINATOR)
        self.assertIn("forceRemote", COORDINATOR)

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
            'if syncIssue == .dashboardRefresh',
            'Text("Data issue")',
            'Latest dashboard update failed',
            'Noom Band syncing, \\(clampedProgress) percent',
        ):
            self.assertIn(snippet, badge)
        self.assertNotIn('"Sync issue"', badge)
        self.assertNotIn('Latest data sync failed', badge)
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

    def test_sleep_detail_exposes_authoritative_processing_and_session_timing(self) -> None:
        for snippet in (
            "detail.processing",
            "detail.sleepOnset",
            "detail.wakeUpTime",
            "detail.timezone",
            'Text(isProcessing ? "Processing sleep" : "Sleep analysis complete")',
            'NoomPill(title: isProcessing ? "In progress" : "Complete"',
            'NoomDetailValueRow(label: "Sleep onset"',
            'NoomDetailValueRow(label: "Wake up"',
            "timestampMillis > 0",
            "Int(timezoneOffsetMinutes) * 60",
            "Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)",
        ):
            self.assertIn(snippet, SLEEP_DETAIL)
        self.assertNotIn("wakeUpTime - sleepTimeSec", SLEEP_DETAIL)
        self.assertNotIn("wakeUpTime - detail.sleepTimeSec", SLEEP_DETAIL)

    def test_sleep_detection_event_drives_a_truthful_root_pending_state(self) -> None:
        self.assertNotIn("sensorBio.sleepDetected", SLEEP_DETAIL)
        self.assertIn("sensorBio.sleepDetected", COORDINATOR)
        self.assertIn("recordDetectedSleep", COORDINATOR)
        self.assertIn("SleepProcessingBanner", SLEEP_DETAIL)
        self.assertIn("sleepProcessing.phase", SLEEP_DETAIL)
        self.assertNotIn("startEpochInms", SLEEP_DETAIL)
        self.assertNotIn("endEpochms", SLEEP_DETAIL)
        self.assertNotIn('title: "Turning last night into a story"', SLEEP_DETAIL)

    def test_sleep_processing_and_complete_states_have_debug_visual_routes(self) -> None:
        self.assertIn('case "sleep_detail_processing_preview", "sleep_detail_complete_preview"', CONTENT)
        self.assertIn('"sleep_detail_processing_preview", "sleep_detail_complete_preview"', SLEEP_DETAIL)
        self.assertIn('title: "Preview sample"', SLEEP_DETAIL)
        self.assertIn("#if DEBUG", SLEEP_DETAIL)

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
            "sleepProcessing.displaySnapshot",
            "snapshot.outcome == .processedSuccessfully",
            "caption: missingSleepCaption",
            'value: "—"',
        ):
            self.assertIn(snippet, metrics)
        self.assertIn('dashboardMetricHasData', DASHBOARD)
        self.assertIn('value: availableMetric.flatMap(dashboardMetricNumber) ?? "—"', DASHBOARD)
        self.assertIn('return "Waiting for today\'s sleep data"', DASHBOARD)
        self.assertIn('return "No sleep data for this day"', DASHBOARD)
        availability = DASHBOARD.split("private func dashboardMetricHasData", 1)[1].split("private func dashboardMetricNumber", 1)[0]
        self.assertIn("dashboardMetricNumber(metric) != nil", availability)
        formatter = DASHBOARD.split("private func dashboardMetricNumber", 1)[1].split("private func dashboardMetricUnit", 1)[0]
        self.assertIn("-> String?", formatter)
        self.assertIn("metric.valueFloat.isFinite && metric.valueFloat > 0", formatter)
        self.assertIn("guard metric.valueFloat == 0, metric.value > 0 else", formatter)
        self.assertIn('missingMetricCaption(for: label)', DASHBOARD)

    def test_home_progress_requires_three_unique_days(self) -> None:
        progress = DASHBOARD.split("private var progressPreviewSection", 1)[1].split("private func dashboardMetrics", 1)[0]
        self.assertIn("Set(recoveryPoints.map(\\.date) + sleepPoints.map(\\.date))", progress)
        self.assertIn("if coveredDays.count >= 3", progress)
        self.assertIn('Text("Progress")', progress)
        self.assertNotIn('Text("Progress from real history")', progress)
        self.assertNotIn('NoomStateBanner(title: "Progress unavailable"', progress)

    def test_empty_home_visual_fixture_matches_missing_data_rules(self) -> None:
        self.assertIn('case "dashboard_empty_tiles_preview"', CONTENT)
        fixture = CONTENT.split("private struct DashboardEmptyMetricTilesPreviewView", 1)[1].split("private struct NoomQAMetricPreview", 1)[0]
        self.assertGreaterEqual(fixture.count('value: "—"'), 6)
        self.assertIn('caption: "Waiting for today\'s sleep data"', fixture)
        self.assertNotIn('Text("Progress")', fixture)

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
        self.assertIn("sleepProcessing.lastCompleted == nil", SLEEP_DETAIL)
        self.assertIn("sleepProcessing.lastCompleted == nil", MAIN_TAB)
        self.assertNotIn("NoomSleepHistory", SLEEP_DETAIL + MAIN_TAB + STATE)
        self.assertNotIn("sensorBio.sleepStored", MAIN_TAB + SLEEP_DETAIL)
        self.assertNotIn("sensorBio.sleepUploaded", MAIN_TAB + SLEEP_DETAIL)
        self.assertIn("sensorBio.sleepStored", COORDINATOR)
        self.assertIn("sensorBio.sleepUploaded", COORDINATOR)
        self.assertRegex(COORDINATOR, r"requestGeneration|generation")
        self.assertIn("sleepProcessing.refresh(forceRemote: true)", SLEEP_DETAIL)


if __name__ == "__main__":
    unittest.main()
