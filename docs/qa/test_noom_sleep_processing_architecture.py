import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NoomApp" / "NoomApp"


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


class NoomSleepProcessingArchitectureTests(unittest.TestCase):
    def test_root_owns_and_injects_one_sleep_processing_coordinator(self) -> None:
        app = source("NoomApp.swift")
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertIn("SleepProcessingCoordinator", app)
        self.assertIn(".environment(sleepProcessing)", app)
        self.assertRegex(coordinator, r"@(?:MainActor\s+)?@Observable|@Observable\s+@MainActor")

    def test_sdk_lifecycle_publishers_are_not_owned_by_feature_views(self) -> None:
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertIn("sleepDetected", coordinator)
        self.assertIn("sleepStored", coordinator)
        self.assertIn("sleepUploaded", coordinator)
        for file_name in ("DashboardView.swift", "MainTabView.swift", "SleepDetailView.swift"):
            text = source(file_name)
            self.assertNotRegex(text, r"\.onReceive\(sensorBio\.sleep(?:Detected|Stored|Uploaded)")

    def test_coordinator_owns_atomic_snapshots_and_exact_race_key(self) -> None:
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertIn("SleepAtomicSnapshot", coordinator)
        self.assertRegex(coordinator, r"selectedSnapshot")
        self.assertRegex(coordinator, r"lastCompleted")
        self.assertRegex(coordinator, r"pendingCandidates")
        self.assertIn("SleepRequestKey", coordinator)
        for field in ("account", "day", "session", "generation"):
            self.assertRegex(coordinator, field)
        self.assertIn("fetchSleepSessions", coordinator)

    def test_daily_sleep_detail_is_not_committed_by_independent_surface_loaders(self) -> None:
        self.assertNotIn("fetchSleepDetail", source("DashboardState.swift"))
        self.assertNotIn("fetchSleepDetail", source("MainTabView.swift"))
        detail = source("SleepDetailView.swift")
        self.assertNotIn("fetchSleepDetail", detail)
        self.assertRegex(detail, r"selectedSnapshot|SleepAtomicSnapshot")

    def test_coordinator_is_the_only_daily_sleep_fetch_owner(self) -> None:
        owners = []
        for path in sorted(APP.glob("*.swift")):
            if "fetchSleepDetail(" in path.read_text(encoding="utf-8"):
                owners.append(path.name)
        self.assertEqual(owners, ["SleepProcessingCoordinator.swift"])

    def test_legacy_raw_account_sleep_history_defaults_are_removed(self) -> None:
        for file_name in (
            "DashboardState.swift",
            "DashboardView.swift",
            "MainTabView.swift",
            "SleepDetailView.swift",
            "NoomProductScreens.swift",
        ):
            text = source(file_name)
            self.assertNotIn("NoomSleepHistory", text)
            self.assertNotIn("noomHasRecordedSleep", text)
            self.assertNotIn("Data(userID.utf8).base64EncodedString()", text)

    def test_root_forwards_account_date_and_foreground_lifecycle(self) -> None:
        app = source("NoomApp.swift")
        content = source("ContentView.swift")
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertRegex(content, r"setAccount(?:Identifier|Scope)")
        self.assertRegex(content, r"setAccount(?:Identifier|Scope)[\s\S]{0,300}selectDate")
        self.assertRegex(app + content, r"scenePhase|isForeground")
        self.assertRegex(app + content, r"selectedDate|selectDate")
        self.assertIn("SHA256", coordinator)

    def test_reconciliation_is_bounded_and_generation_guarded(self) -> None:
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertRegex(coordinator, r"max(?:imum)?(?:Poll|Retry|Reconciliation)|retryLimit|maxAttempts")
        self.assertRegex(coordinator, r"generation|requestID")
        self.assertRegex(coordinator, r"250_000_000|milliseconds\(250\)|\.milliseconds\(250\)")
        self.assertRegex(coordinator, r"\b60(?:\.0)?\b")
        self.assertIn("Task.isCancelled", coordinator)

    def test_pending_metadata_is_protected_and_notifications_never_prompt(self) -> None:
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertIn("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly", coordinator)
        self.assertRegex(coordinator, r"SHA256|CryptoKit")
        self.assertRegex(coordinator, r"version")
        self.assertIn("getNotificationSettings", coordinator)
        self.assertNotIn("requestAuthorization", coordinator)
        self.assertRegex(coordinator, r"processedSuccessfully|permitsBodyStatus")
        self.assertRegex(coordinator, r"background|isForeground")
        self.assertRegex(coordinator, r"removePendingNotificationRequests|removeDeliveredNotifications")

    def test_home_and_sleep_hub_render_shared_processing_status(self) -> None:
        dashboard = source("DashboardView.swift")
        sleep_hub = source("MainTabView.swift")
        self.assertIn("SleepProcessingBanner", dashboard)
        self.assertIn("SleepProcessingBanner", sleep_hub)

    def test_body_status_requires_typed_success(self) -> None:
        dashboard = source("DashboardView.swift")
        self.assertRegex(dashboard, r"permitsBodyStatus|processedSuccessfully")

    def test_completed_sleep_is_preserved_with_original_source_date(self) -> None:
        coordinator = source("SleepProcessingCoordinator.swift")
        dashboard = source("DashboardView.swift")
        sleep_hub = source("MainTabView.swift")
        self.assertRegex(coordinator, r"lastCompleted")
        self.assertRegex(coordinator, r"sourceDate")
        self.assertRegex(dashboard, r"lastCompleted|displaySnapshot")
        self.assertRegex(dashboard, r"sourceDate")
        self.assertRegex(sleep_hub, r"lastCompleted|displaySnapshot")
        self.assertRegex(sleep_hub, r"sourceDate")

    def test_daily_detail_uses_typed_outcome_not_boolean_only_completion(self) -> None:
        detail = source("SleepDetailView.swift")
        self.assertRegex(detail, r"SleepAnalysisOutcome|processState")
        self.assertNotRegex(detail, r"if\s+detail\.processing\s*\{[^}]+\}\s*else\s*\{\s*sleepHero")

    def test_session_selection_is_explicit_and_detection_timing_stays_provisional(self) -> None:
        coordinator = source("SleepProcessingCoordinator.swift")
        self.assertRegex(coordinator, r"SleepSessionIdentity")
        self.assertRegex(coordinator, r"selectedSession")
        self.assertRegex(coordinator, r"pendingCandidates")
        self.assertIn("fetchSleepSessions", coordinator)
        for field in ("endDate", "endTimestamp", "timezone"):
            self.assertIn(field, coordinator)
        sleep_hub = source("MainTabView.swift")
        self.assertRegex(sleep_hub, r"availableSessions|sessions")
        self.assertRegex(sleep_hub, r"selectSession|selectedSession")
        for file_name in ("DashboardState.swift", "MainTabView.swift", "SleepDetailView.swift"):
            text = source(file_name)
            self.assertNotIn("sleeps.first", text)
        for file_name in ("DashboardView.swift", "MainTabView.swift", "SleepDetailView.swift"):
            text = source(file_name)
            self.assertNotIn("startEpochInms", text)
            self.assertNotIn("endEpochms", text)


if __name__ == "__main__":
    unittest.main()
