import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
MAIN_TAB = (SRC / "MainTabView.swift").read_text()
RECORDING = (SRC / "RecordingExperienceView.swift").read_text()
DASHBOARD = (SRC / "DashboardView.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()
DESIGN = (ROOT / "NoomApp/Docs/DESIGN_BRIEF.md").read_text()
NAVIGATION = (ROOT / "NoomApp/Docs/NAVIGATION_MAP.md").read_text()
STATES = (ROOT / "NoomApp/Docs/SCREEN_STATES.md").read_text()


class NoomRecordingExperienceContracts(unittest.TestCase):
    def recording_source(self) -> str:
        return RECORDING.split("enum NoomRecordingExperience", 1)[1]

    def test_recording_entry_is_a_floating_home_action_not_a_header_icon(self) -> None:
        header = DASHBOARD.split("NoomDayNavigator", 1)[0]
        self.assertNotIn("RecordActivityView()", header)
        self.assertIn(".overlay(alignment: .bottomTrailing)", DASHBOARD)
        self.assertIn("NoomRecordingFloatingButton", DASHBOARD)
        self.assertIn('accessibilityLabel("Record a session")', DASHBOARD)

    def test_recording_hub_offers_two_distinct_experiences(self) -> None:
        source = self.recording_source()
        for snippet in (
            "case spotCheck",
            "case activity",
            "private var recordingHub",
            'Text("Spot check")',
            'Text("Activity tracking")',
            "spotCheckExperience",
            "activityExperience",
        ):
            self.assertIn(snippet, source)
        self.assertNotIn('Picker("Recording type"', source)

    def test_spot_check_uses_fixed_sdk_capture_and_real_live_streams(self) -> None:
        source = self.recording_source()
        for snippet in (
            "recordDetailedBiometrics(duration: 60, minDuration: 30)",
            "sensorBio.ppg.throttle",
            "sensorBio.hr.receive(on: RunLoop.main)",
            "sensorBio.hrv.receive(on: RunLoop.main)",
            "sensorBio.bbi.receive(on: RunLoop.main)",
            "sensorBio.rr.receive(on: RunLoop.main)",
            "sensorBio.spo2.receive(on: RunLoop.main)",
            "sensorBio.snr.receive(on: RunLoop.main)",
            'title: "Live PPG"',
            'label: "HRV"',
            'label: "IBI"',
            'Text("PPG is a light-based pulse signal, not an ECG or diagnosis.")',
        ):
            self.assertIn(snippet, source)

    def test_activity_tracking_is_open_ended_and_has_real_session_controls(self) -> None:
        source = self.recording_source()
        for snippet in (
            "fetchActivityList()",
            "recordActivity(activityName: activityName, minDuration: 30)",
            "sensorBio.pauseRecording()",
            "sensorBio.resumeRecording()",
            "sensorBio.finishCurrentRecording()",
            'Text(isPaused ? "Paused" : "Recording")',
            'Text("HEART RATE")',
            'Text("RECENT HR TREND")',
            "NoomRecordingHeartRateChart",
        ):
            self.assertIn(snippet, source)

    def test_live_samples_are_finite_and_memory_bounded_before_rendering(self) -> None:
        source = self.recording_source()
        self.assertIn("guard value.isFinite else { return }", source)
        self.assertIn("appendBounded", source)
        self.assertIn("limit: 140", source)
        self.assertIn("let finiteSamples = samples.filter { $0.value.isFinite }", source)
        chart = source.split("struct NoomRecordingSignalWaveform", 1)[1]
        self.assertIn("finiteSamples", chart)

    def test_recording_failures_are_friendly_and_cancel_is_real(self) -> None:
        source = self.recording_source()
        self.assertIn("private func recordingErrorMessage", source)
        self.assertIn("switch recordingError", source)
        self.assertNotIn("completionMessage = error.localizedDescription", source)
        cancel = source[source.index("private func cancelRecording"):source.index("private func completeRecording")]
        self.assertIn("if isAwaitingRestoredRecording", cancel)
        self.assertIn("sensorBio.cancelCurrentRecording()", cancel)
        self.assertIn("recordingTask?.cancel()", cancel)
        self.assertIn("recordingRequestID = nil", cancel)
        self.assertIn(".confirmationDialog", source)

    def test_restore_preserves_supported_kind_and_rejects_meditation_coercion(self) -> None:
        source = self.recording_source()
        restore = source[source.index("private func restorePersistedRecordingIfNeeded"):source.index("private var currentElapsed")]
        self.assertIn("case .biometrics:", restore)
        self.assertIn("case .meditation:", restore)
        self.assertIn("unsupportedRestoredKind = .meditation", restore)
        self.assertNotIn("case .biometrics, .meditation:", restore)
        self.assertIn("isAwaitingRestoredRecording = true", restore)
        self.assertIn("recordingRequestID = requestID", restore)
        self.assertIn("guard recordingRequestID == requestID", restore)

    def test_restored_activity_name_survives_catalog_refresh(self) -> None:
        source = self.recording_source()
        self.assertIn("preservesRestoredActivityName = true", source)
        self.assertIn("if preservesRestoredActivityName", source)
        self.assertIn("activityChoices = [activityName] + choices", source)

    def test_cancel_hides_stale_controls_until_sdk_reports_idle(self) -> None:
        source = self.recording_source()
        cancel = source[source.index("private func cancelRecording"):source.index("private func completeRecording")]
        self.assertIn("isCancellationPending = true", cancel)
        self.assertIn("guard !isCancellationPending else { return false }", source)
        self.assertIn("if case .idle = state", source)
        self.assertIn(".disabled(!bandConnected || recordingTask != nil || isCancellationPending)", source)
        self.assertIn('title: "Ending previous recording"', source)

    def test_fresh_start_owns_navigation_until_sdk_leaves_idle(self) -> None:
        source = self.recording_source()
        begin = source[source.index("private func beginRecording"):source.index("private func cancelRecording")]
        self.assertIn("isStartingRecording = true", begin)
        self.assertIn("if isStartingRecording { return true }", source)
        self.assertIn("startingRecordingControlDock", source)
        self.assertIn('title: "Starting recording"', source)
        self.assertIn("isStartingRecording = false", begin)
        self.assertIn("guard isStartingRecording, !isPreview else { return }", source)

    def test_restore_finalization_and_completion_are_explicit(self) -> None:
        source = self.recording_source()
        for snippet in (
            "sensorBio.activeRecording",
            "sensorBio.awaitActiveRecordingCompletion()",
            "case .stoppingDevice:",
            "case .syncingDevice:",
            "case .submitting:",
            'Text("Session saved")',
            'Text("Processing continues securely in the background.")',
        ):
            self.assertIn(snippet, source)

    def test_debug_routes_cover_hub_and_both_live_experiences(self) -> None:
        for route in (
            'case "recording_hub_preview"',
            'case "recording_spot_preview"',
            'case "recording_activity_preview"',
        ):
            self.assertIn(route, CONTENT)
        self.assertIn("#if DEBUG", CONTENT)
        self.assertIn("enum NoomRecordingPreview", RECORDING)

    def test_recording_design_docs_capture_real_capabilities_and_mobbin_sources(self) -> None:
        for label in ("PPG", "IBI", "HRV", "HR", "SNR", "SpO₂"):
            self.assertIn(label, DESIGN)
        self.assertIn("mobbin.com/explore/screens/90c1b4a8", DESIGN)
        self.assertIn("mobbin.com/explore/flows/1fa13090", DESIGN)
        self.assertIn("Floating recording action", NAVIGATION)
        self.assertIn("Spot check", NAVIGATION)
        self.assertIn("Activity tracking", NAVIGATION)
        self.assertIn("Weak or missing signal", STATES)
        self.assertIn("Finalizing", STATES)
        self.assertIn("Restored after relaunch", STATES)


if __name__ == "__main__":
    unittest.main()
