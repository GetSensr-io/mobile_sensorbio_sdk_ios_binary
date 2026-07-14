import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NoomApp" / "NoomApp"
CONTENT = (APP / "ContentView.swift").read_text(encoding="utf-8")
CAPTURE_SCRIPT = (ROOT / "NoomApp" / "scripts" / "capture_sleep_processing_states.sh").read_text(encoding="utf-8")


class NoomSleepProcessingVisualContractTests(unittest.TestCase):
    routes = (
        "sleep_processing_detected",
        "sleep_processing_stored",
        "sleep_processing_uploaded",
        "sleep_processing_analyzing",
        "sleep_processing_ready",
        "sleep_processing_short",
        "sleep_processing_error",
        "sleep_processing_calibrating",
        "sleep_processing_stale",
        "sleep_processing_multiple_sessions",
        "sleep_processing_pending_with_history",
    )

    def test_every_sleep_lifecycle_state_has_a_debug_route(self) -> None:
        for route in self.routes:
            self.assertIn(route, CONTENT)
        host_start = CONTENT.index("private struct NoomQAHost")
        self.assertGreater(CONTENT.rfind("#if DEBUG", 0, host_start), CONTENT.rfind("#endif", 0, host_start))

    def test_capture_script_covers_every_route(self) -> None:
        for route in self.routes:
            self.assertIn(route, CAPTURE_SCRIPT)
        self.assertIn("SIMULATOR_UDID", CAPTURE_SCRIPT)
        self.assertIn("APP_PATH", CAPTURE_SCRIPT)

    def test_preview_state_and_banner_are_compile_time_debug_only(self) -> None:
        preview = (APP / "SleepProcessingPreview.swift").read_text(encoding="utf-8")
        self.assertTrue(preview.lstrip().startswith("#if DEBUG"))
        self.assertTrue(preview.rstrip().endswith("#endif"))
        self.assertIn("SleepProcessingBanner", preview)
        self.assertIn("accessibility", preview.lower())

    def test_real_surfaces_use_one_shared_status_component(self) -> None:
        for file_name in ("DashboardView.swift", "MainTabView.swift", "SleepDetailView.swift"):
            source = (APP / file_name).read_text(encoding="utf-8")
            self.assertIn("SleepProcessingBanner", source)


if __name__ == "__main__":
    unittest.main()
