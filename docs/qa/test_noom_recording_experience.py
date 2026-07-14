import re
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
CAPABILITY_MATRIX = (ROOT / "NoomApp/Docs/CAPABILITY_MATRIX.md").read_text()


class NoomRecordingExperienceContracts(unittest.TestCase):
    def recording_source(self) -> str:
        return RECORDING.split("enum NoomRecordingExperience", 1)[1]

    def source_neighborhood(
        self,
        source: str,
        marker: str,
        before: int = 400,
        after: int = 2_400,
    ) -> str:
        index = source.index(marker)
        return source[max(0, index - before):index + after]

    def publisher_handler(self, source: str, publisher: str) -> str:
        publisher_index = source.index(publisher)
        handler_start = source.rfind(".onReceive(", 0, publisher_index)
        self.assertGreaterEqual(
            handler_start,
            0,
            f"{publisher} must be consumed by a SwiftUI subscription",
        )

        boundaries = []
        for marker in (".onReceive(", "\n        .task", "\n        .onDisappear"):
            boundary = source.find(marker, publisher_index + len(publisher))
            if boundary >= 0:
                boundaries.append(boundary)
        handler_end = min(boundaries) if boundaries else len(source)
        return source[handler_start:handler_end]

    def swift_function_body(self, source: str, name: str):
        signature = re.search(rf"\bfunc\s+{re.escape(name)}\s*\(", source)
        if signature is None:
            return None
        opening_brace = source.find("{", signature.end())
        if opening_brace < 0:
            return None

        depth = 0
        for index in range(opening_brace, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    return source[opening_brace:index + 1]
        return None

    def swift_computed_property_body(self, source: str, name: str):
        signature = re.search(
            rf"\bvar\s+{re.escape(name)}\b[^{{\n]*\{{",
            source,
        )
        if signature is None:
            return None
        opening_brace = source.find("{", signature.start())

        depth = 0
        for index in range(opening_brace, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    return source[opening_brace:index + 1]
        return None

    def expanded_swift_predicates(
        self,
        source: str,
        snippet: str,
        depth: int = 2,
    ) -> str:
        expanded = snippet
        frontier = snippet
        visited = set()
        identifier_pattern = re.compile(r"\b([a-z][A-Za-z0-9_]*)\b")

        for _ in range(depth):
            bodies = []
            for name in identifier_pattern.findall(frontier):
                if name in visited:
                    continue
                visited.add(name)
                body = self.swift_computed_property_body(source, name)
                if body is not None:
                    bodies.append(body)
            if not bodies:
                break
            frontier = "\n".join(bodies)
            expanded += "\n" + frontier
        return expanded

    def expanded_swift_route(self, source: str, snippet: str, depth: int = 2) -> str:
        expanded = snippet
        frontier = snippet
        visited = set()
        call_pattern = re.compile(
            r"(?<![\w.])(?:self\.)?([a-z][A-Za-z0-9_]*)\s*\("
        )

        for _ in range(depth):
            bodies = []
            for match in call_pattern.finditer(frontier):
                name = match.group(1)
                if name in visited:
                    continue
                visited.add(name)
                body = self.swift_function_body(source, name)
                if body is not None:
                    bodies.append(body)
            if not bodies:
                break
            frontier = "\n".join(bodies)
            expanded += "\n" + frontier
        return expanded

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
            "private let noomSpotCheckMinimumDuration: TimeInterval = 30",
            "duration: noomSpotCheckDuration",
            "minDuration: noomSpotCheckMinimumDuration",
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
        self.assertNotIn("minDuration: noomSpotCheckDuration", source)

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

    def test_ppg_ingestion_and_rendering_use_interpolation_at_display_cadence(self) -> None:
        source = self.recording_source()
        handler = self.publisher_handler(source, "sensorBio.ppg")
        pipeline = handler.split("{", 1)[0]
        self.assertRegex(
            pipeline,
            r"sensorBio\.ppg\s*\.receive\(\s*on:\s*RunLoop\.main\s*\)",
        )
        self.assertNotIn(
            ".throttle",
            pipeline,
            "PPG samples must reach the app buffer before display-cadence rendering",
        )
        self.assertIn("NoomPPGSampleInterpolator", source)

        finite_check = handler.find(".isFinite")
        self.assertGreaterEqual(
            finite_check,
            0,
            "The PPG subscription must reject non-finite raw samples",
        )
        ingestion_route = self.expanded_swift_route(
            source,
            handler[finite_check:],
            depth=2,
        )
        self.assertRegex(
            ingestion_route,
            r"\.enqueue\s*\(",
            "Every finite raw PPG sample must enter NoomPPGSampleInterpolator",
        )
        self.assertNotIn(
            "Date()",
            ingestion_route,
            "Burst arrival time must not be fabricated as the PPG sample timeline",
        )

        display_route = None
        for match in re.finditer(
            r"\.milliseconds\(\s*(?P<milliseconds>\d+(?:\.\d+)?)\s*\)",
            source,
        ):
            milliseconds = float(match.group("milliseconds"))
            if not 15.5 <= milliseconds <= 17.5:
                continue
            neighborhood = source[
                max(0, match.start() - 1_600):match.end() + 1_600
            ]
            route = self.expanded_swift_route(source, neighborhood, depth=3)
            if re.search(r"\.nextFrame\s*\(\s*\)", route):
                display_route = route
                break

        self.assertIsNotNone(
            display_route,
            "PPG rendering must consume interpolated frames at roughly display cadence",
        )
        display_route = display_route or ""
        self.assertRegex(
            display_route,
            r"Task\.(?:isCancelled|checkCancellation)",
            "The display-cadence task must stop when its view/task ownership is cancelled",
        )
        self.assertRegex(display_route, r"\.nextFrame\s*\(\s*\)")
        self.assertRegex(
            display_route,
            r"\.append\s*\(",
            "Each display frame must append a rendered sample",
        )
        self.assertRegex(
            display_route,
            r"\.(?:removeFirst|removeAll|suffix)\s*\(",
            "Rendered PPG samples must remain memory bounded",
        )

        self.assertIn("NoomPPGYRangeSmoother", source)
        waveform = source.split("struct NoomRecordingSignalWaveform", 1)[1].split(
            "struct NoomRecordingHeartRateChart",
            1,
        )[0]
        self.assertRegex(
            display_route + "\n" + waveform,
            r"\.update\s*\(\s*with\s*:",
            "Rendered PPG values must update the smoothed Y range",
        )
        self.assertRegex(
            waveform,
            r"\b[A-Za-z_]\w*\.addCurve\s*\(",
            "The PPG waveform must render cubic Path curves",
        )

    def test_spot_check_attempt_ownership_buffers_ppg_before_sdk_recording(self) -> None:
        source = self.recording_source()
        handler = self.publisher_handler(source, "sensorBio.ppg")
        enqueue_marker = "ppgInterpolator.enqueue"
        self.assertIn(enqueue_marker, handler)
        enqueue_index = handler.index(enqueue_marker)
        finite_index = handler.find(".isFinite")
        self.assertGreaterEqual(finite_index, 0)
        self.assertLess(finite_index, enqueue_index)

        intake_route = self.expanded_swift_predicates(
            source,
            handler[:enqueue_index],
            depth=2,
        )
        self.assertIn("activeRecordingAttempt", intake_route)
        self.assertIn(".spotCheck", intake_route)
        with self.subTest("request ownership is correlated"):
            self.assertRegex(
                intake_route,
                r"recordingRequestID\s*==\s*(?:attempt\.requestID|"
                r"activeRecordingAttempt\??\.requestID)",
                "PPG intake must belong to the same active Spot check request",
            )
        with self.subTest("intake is not gated on SDK recording state"):
            self.assertNotRegex(
                intake_route,
                r"(?s)(?:if|guard)\b.{0,240}?case\s+\.recording\s*=\s*recordingState",
                "Attempt-owned PPG can arrive during startup before SDK .recording",
            )

        display = self.swift_function_body(source, "startPPGDisplayIfNeeded") or ""
        display_route = self.expanded_swift_predicates(source, display, depth=2)
        self.assertIn("ppgDisplayTask = Task", display)
        self.assertIn("!isPreview", display_route)
        self.assertRegex(
            display_route,
            r"case\s+\.recording\s*=\s*recordingState",
            "Display cadence must still start only for a real SDK recording",
        )

        for terminal_path in (
            "cancelRecording",
            "completeRecording",
            "failRecordingAttempt",
        ):
            body = self.swift_function_body(source, terminal_path) or ""
            with self.subTest(terminal_path=terminal_path):
                self.assertIn("recordingRequestID = nil", body)
                self.assertIn("activeRecordingAttempt = nil", body)

    def test_ppg_waveform_uses_monotonic_indices_in_a_fixed_300_point_viewport(self) -> None:
        source = self.recording_source()
        display = self.swift_function_body(source, "startPPGDisplayIfNeeded") or ""
        waveform = source.split("struct NoomRecordingSignalWaveform", 1)[1].split(
            "struct NoomRecordingHeartRateChart",
            1,
        )[0]

        self.assertIn("private let noomRenderedPPGSampleLimit = 300", source)
        self.assertRegex(
            display,
            r"index:\s*\(\s*ppgSamples\.last\?\.index\s*\?\?\s*-1\s*\)\s*\+\s*1",
            "Rendered sample indices must remain monotonically increasing as old points roll off",
        )
        window_start = re.search(
            r"(?is)\b(?:let|var)\s+"
            r"(?P<name>[A-Za-z_]\w*(?:window|viewport)\w*)"
            r"\s*(?::[^=\n]+)?=.{0,320}?noomRenderedPPGSampleLimit",
            waveform,
        )
        self.assertIsNotNone(
            window_start,
            "Waveform X positions need a fixed 300-point viewport/window start",
        )
        window_name = window_start.group("name") if window_start else ""
        if window_name:
            self.assertRegex(
                waveform,
                re.compile(
                    rf"\blet\s+x\s*=.{{0,320}}?sample\.index"
                    rf".{{0,320}}?\b{re.escape(window_name)}\b",
                    re.DOTALL,
                ),
                "Waveform X must derive from each monotonic sample index and window start",
            )

        self.assertNotRegex(
            waveform,
            r"CGFloat\(\s*offset\s*\)\s*/",
            "A partial window must not be stretched to full width by enumerated offset",
        )
        self.assertNotRegex(
            waveform,
            r"finiteSamples\.count\s*-\s*1",
            "X scale must stay fixed while the 300-point viewport fills",
        )
        self.assertIn("let yRange: ClosedRange<Double>?", waveform)
        self.assertIn("resolvedYRange(for: finiteSamples)", waveform)
        self.assertRegex(display, r"ppgYRangeSmoother\.update\s*\(")
        self.assertRegex(waveform, r"\b[A-Za-z_]\w*\.addCurve\s*\(")

    def test_ppg_cubic_renderer_uses_explicit_low_intensity_control_points(self) -> None:
        source = self.recording_source()
        waveform = source.split("struct NoomRecordingSignalWaveform", 1)[1].split(
            "struct NoomRecordingHeartRateChart",
            1,
        )[0]
        self.assertRegex(waveform, r"\b[A-Za-z_]\w*\.addCurve\s*\(")

        assignments = list(
            re.finditer(
                r"\b(?:let|var)\s+"
                r"(?P<name>[A-Za-z_]\w*(?:cubic|curve|intensity|tension)\w*)"
                r"\s*(?::\s*CGFloat)?\s*=\s*(?P<value>\d*\.\d+)",
                waveform,
                re.IGNORECASE,
            )
        )
        low_intensity = [
            match
            for match in assignments
            if abs(float(match.group("value")) - 0.1) <= 0.02
        ]
        self.assertTrue(
            low_intensity,
            "Cubic control-point intensity must be explicit and approximately 0.1",
        )
        if low_intensity:
            intensity = low_intensity[0]
            control_math = waveform[intensity.end():]
            self.assertRegex(
                control_math,
                re.compile(
                    rf"(?:CGPoint|control\w*).{{0,500}}?"
                    rf"\b{re.escape(intensity.group('name'))}\b",
                    re.DOTALL,
                ),
                "The explicit cubic intensity must participate in control-point math",
            )

    def test_spot_check_is_three_minutes_with_wall_clock_elapsed_presentation(self) -> None:
        source = self.recording_source()
        for snippet in (
            "private let noomSpotCheckDuration: TimeInterval = 180",
            "spotCheckNow.timeIntervalSince(start)",
            "Task.sleep(for: .milliseconds(100))",
            'NoomPill(title: "3 min"',
        ):
            self.assertIn(snippet, source)

        timer_constructor_pattern = (
            r"NoomSpotCheckTimerPresentation\(\s*"
            r"elapsed:\s*spotCheckWallClockElapsed\s*,\s*"
            r"target:\s*noomSpotCheckDuration\s*\)"
        )
        constructor = re.search(timer_constructor_pattern, source)
        self.assertIsNotNone(
            constructor,
            "The live timer must derive display copy from wall-clock elapsed time",
        )

        text_presentations = set(
            re.findall(r"Text\(\s*([A-Za-z_]\w*)\.text\s*\)", source)
        )
        unit_presentations = set(
            re.findall(r"Text\(\s*([A-Za-z_]\w*)\.unit\s*\)", source)
        )
        accessibility_presentations = set(
            re.findall(
                r"\.accessibilityLabel\(\s*([A-Za-z_]\w*)\.accessibilityLabel\s*\)",
                source,
            )
        )
        bound_presentation = (
            text_presentations
            & unit_presentations
            & accessibility_presentations
        )
        direct_presentation = (
            re.search(
                r"Text\(\s*" + timer_constructor_pattern + r"\s*\.text\s*\)",
                source,
            )
            and re.search(
                r"Text\(\s*" + timer_constructor_pattern + r"\s*\.unit\s*\)",
                source,
            )
            and re.search(
                r"\.accessibilityLabel\(\s*"
                + timer_constructor_pattern
                + r"\s*\.accessibilityLabel\s*\)",
                source,
            )
        )
        self.assertTrue(
            bound_presentation or direct_presentation,
            "The timer must render presentation text, unit, and accessibility label",
        )
        self.assertNotIn("spotCheckSecondsRemaining", source)
        self.assertNotIn("SECONDS REMAINING", source.upper())
        self.assertNotRegex(source, r'Text\(\s*"SEC"\s*\)')

    def test_snr_display_uses_the_current_raw_packet_without_ema(self) -> None:
        source = self.recording_source()
        handler = self.publisher_handler(source, "sensorBio.snr")
        pipeline = handler.split("{", 1)[0]
        self.assertRegex(
            pipeline,
            r"sensorBio\.snr\s*\.receive\(\s*on:\s*RunLoop\.main\s*\)",
        )
        route = self.expanded_swift_route(source, handler, depth=2)
        self.assertRegex(
            route,
            r"NoomSignalQuality\.displayDecibels\(\s*rawSNR\s*:",
            "The visible SNR must be derived from the current raw SDK packet",
        )
        executable_route = re.sub(r"//.*", "", route)
        self.assertNotRegex(
            executable_route,
            re.compile(
                r"\b[A-Za-z_]*ema[A-Za-z_]*\b|exponential\s*moving\s*average",
                re.IGNORECASE,
            ),
        )
        self.assertNotIn(".scan(", executable_route)

    def test_recording_failures_are_friendly_and_cancel_is_real(self) -> None:
        source = self.recording_source()
        self.assertIn("private func recordingErrorMessage", source)
        self.assertIn("switch recordingError", source)
        cancel = source[source.index("private func cancelRecording"):source.index("private func completeRecording")]
        self.assertIn("if isAwaitingRestoredRecording", cancel)
        self.assertIn("sensorBio.cancelCurrentRecording()", cancel)
        self.assertIn("recordingTask?.cancel()", cancel)
        self.assertIn("recordingRequestID = nil", cancel)
        self.assertIn(".confirmationDialog", source)

    def test_recording_readiness_is_seeded_and_subscribed_from_full_configuration(self) -> None:
        source = self.recording_source()
        seed = re.search(
            r"@State\s+private\s+var\s+(?P<state>[A-Za-z_]\w*)"
            r"(?:\s*:\s*Bool)?\s*=\s*sensorBio\.isFullyConfigured\b",
            source,
        )
        self.assertIsNotNone(
            seed,
            "Recording readiness must be seeded from sensorBio.isFullyConfigured",
        )
        readiness_state = seed.group("state")
        subscription = re.search(
            rf"(?s)\.onReceive\(\s*sensorBio\.\$isFullyConfigured\b.*?\)\s*\{{"
            rf".*?\b{re.escape(readiness_state)}\s*=",
            source,
        )
        self.assertIsNotNone(
            subscription,
            "Recording readiness must follow sensorBio.$isFullyConfigured",
        )

        status = source[
            source.index("private var recordingTopBar"):
            source.index("private var topBarTitle")
        ]
        start_controls = source[
            source.index("private func recordingStartControls"):
            source.index("private func recordingIcon")
        ]
        self.assertIn(readiness_state, status)
        self.assertIn(readiness_state, start_controls)
        self.assertNotIn(
            "sensorBio.connected",
            source,
            "Loose SDK connectivity must not gate recording readiness or status",
        )

    def test_sdk_completion_publishers_route_through_app_owned_correlation_policy(self) -> None:
        source = self.recording_source()
        for symbol in (
            "NoomRecordingAttempt",
            "NoomRecordingFinalizationPolicy",
            "NoomRecordingResolution",
        ):
            self.assertIn(symbol, source)

        publisher_evidence_pairs = (
            ("sensorBio.pendingSubmissionsPublisher", "NoomRecordingSubmissionEvidence"),
            ("sensorBio.biometricRecordResult", "NoomBiometricResultEvidence"),
        )
        resolution_pattern = re.compile(
            r"\b(?:policy|[A-Za-z_]\w*[Pp]olicy)\.resolve\("
        )
        for publisher, evidence in publisher_evidence_pairs:
            self.assertIn(publisher, source)
            neighborhood = self.source_neighborhood(source, publisher)
            self.assertIn(
                evidence,
                neighborhood,
                f"{publisher} must be translated to {evidence} before resolution",
            )
            resolution = resolution_pattern.search(neighborhood)
            self.assertIsNotNone(
                resolution,
                f"{publisher} must route through app-owned resolution policy",
            )
            self.assertLess(neighborhood.index(evidence), resolution.start())
            completion = neighborhood.find("completeRecording(")
            if completion >= 0:
                self.assertLess(
                    resolution.start(),
                    completion,
                    f"{publisher} must not blindly complete the current attempt",
                )

    def test_finalization_watchdog_is_cancellable_and_request_phase_keyed(self) -> None:
        source = self.recording_source()
        for symbol in (
            "NoomRecordingFinalizationPhase",
            "NoomRecordingFinalizationPolicy",
            "armWatchdog",
            "firedToken:",
            "requestID:",
            "phase:",
        ):
            self.assertIn(symbol, source)
        self.assertRegex(
            source,
            r"\b[A-Za-z_]\w*[Ww]atchdog\w*\?\.cancel\(\)",
            "The phase watchdog must be cancellable when phase/request ownership changes",
        )
        self.assertRegex(
            source,
            r"(?s)resolve\(\s*timeout:.{0,800}?firedToken:.{0,800}?requestID:.{0,800}?phase:",
            "Timeout resolution must carry token, request, and phase identity",
        )

    def test_owned_attempt_receiving_idle_after_capture_advances_to_submitting_watchdog(self) -> None:
        source = self.recording_source()
        handler = self.swift_function_body(source, "handleSDKRecordingState") or ""
        self.assertIn("case .idle:", handler)
        idle_case = handler.split("case .idle:", 1)[1].split(
            "case let .recording",
            1,
        )[0]
        idle_route = self.expanded_swift_route(source, idle_case, depth=3)

        self.assertIn("activeRecordingAttempt", idle_route)
        self.assertRegex(
            idle_route,
            r"recordingRequestID\s*==\s*attempt\.requestID",
            "Idle liveness must stay correlated to the unresolved app-owned request",
        )
        self.assertRegex(
            idle_route,
            re.compile(
                r"!isStartingRecording|"
                r"(?:has|did|was)[A-Za-z_]*(?:recording|capture|startup)",
                re.IGNORECASE,
            ),
            "Initial SDK idle and idle after startup/capture must remain distinct",
        )
        self.assertRegex(
            idle_route,
            r"recordingState\s*=\s*\.finalizing\s*\(\s*phase:\s*\.submitting\s*\)",
            "Post-capture idle must remain in app-owned submitting, not show Ready",
        )
        self.assertRegex(
            idle_route,
            r"advanceFinalization\s*\(\s*to:\s*\.submitting\s*,\s*for:\s*attempt\s*\)",
            "Post-capture idle must arm or advance the submitting watchdog",
        )
        self.assertIn("case .submitting: return .seconds(105)", source)
        self.assertNotIn("recordingRequestID = nil", idle_case)
        self.assertNotIn("activeRecordingAttempt = nil", idle_case)

        cancel = self.swift_function_body(source, "cancelRecording") or ""
        self.assertIn("isCancellationPending = true", cancel)
        self.assertIn("recordingRequestID = nil", cancel)
        self.assertIn("activeRecordingAttempt = nil", cancel)
        for terminal_path in ("completeRecording", "failRecordingAttempt"):
            body = self.swift_function_body(source, terminal_path) or ""
            with self.subTest(terminal_path=terminal_path):
                self.assertIn("recordingState = .idle", body)
                self.assertIn("recordingRequestID = nil", body)
                self.assertIn("activeRecordingAttempt = nil", body)

    def test_try_again_reconciles_same_attempt_before_rearming_without_local_id(self) -> None:
        source = self.recording_source()
        retry = self.swift_function_body(source, "retryDelayedFinalization") or ""
        self.assertRegex(
            retry,
            r"guard\s+let\s+attempt\s*=\s*activeRecordingAttempt",
            "Try Again must retain the active attempt while reconciling durable state",
        )
        self.assertIn("recordingRequestID == attempt.requestID", retry)
        self.assertRegex(
            retry,
            r"if\s+let\s+localID\s*=\s*failedSubmissionLocalID",
        )
        self.assertIn("sensorBio.retrySubmission(localId: localID)", retry)

        snapshot = re.search(
            r"(?:[A-Za-z_]\w*(?:Pending|Submission)[A-Za-z_]*"
            r"\(\s*for:\s*attempt\s*\)|"
            r"sensorBio\.pendingSubmissions\s*\(\s*\))",
            retry,
        )
        self.assertIsNotNone(
            snapshot,
            "Without a failed local ID, Try Again must first reconcile pendingSubmissions()",
        )
        if snapshot:
            snapshot_route = self.expanded_swift_route(
                source,
                snapshot.group(0),
                depth=2,
            )
            self.assertIn("sensorBio.pendingSubmissions()", snapshot_route)
            fallback_rearm = retry.rfind("rearmWatchdog(")
            self.assertGreater(fallback_rearm, snapshot.end())
            between = retry[snapshot.end():fallback_rearm]
            guarded_call = retry[max(0, snapshot.start() - 120):snapshot.end() + 120]
            explicitly_unresolved = re.search(
                r"unresolved|didResolve|hasResolved|isResolved",
                between,
                re.IGNORECASE,
            )
            boolean_resolution_guard = re.search(
                r"guard\s+!?\s*[^\n]{0,120}"
                + re.escape(snapshot.group(0))
                + r"[^\n]{0,120}else\s*\{\s*return",
                guarded_call,
            )
            self.assertTrue(
                explicitly_unresolved or boolean_resolution_guard,
                "Try Again may rearm only when snapshot reconciliation stays unresolved",
            )

        keep_start = source.index('Button("Keep waiting")')
        keep_end = source.index(".buttonStyle", keep_start)
        keep_action = source[keep_start:keep_end]
        self.assertIn("rearmWatchdog()", keep_action)
        self.assertNotIn("retryDelayedFinalization", keep_action)
        self.assertNotIn("pendingSubmissions", keep_action)
        self.assertNotIn("retrySubmission", keep_action)

    def test_delayed_finalization_requires_explicit_wait_retry_or_confirmed_discard(self) -> None:
        source = self.recording_source()
        self.assertRegex(source.lower(), r"taking longer|still syncing|needs more time")
        self.assertIn('"Keep waiting"', source)
        self.assertRegex(
            source,
            r"(?s)(?:Keep waiting.{0,1200}rearmWatchdog|rearmWatchdog.{0,1200}Keep waiting)",
            "Keep waiting must explicitly re-arm the watchdog",
        )
        self.assertRegex(source, r'"(?:Try again|Retry sync)"')
        self.assertRegex(source, r'"Discard(?: session| recording)?"')
        discard_state = re.search(
            r"@State\s+private\s+var\s+(?P<state>[A-Za-z_]\w*[Dd]iscard\w*)"
            r"(?:\s*:\s*Bool)?\s*=\s*false",
            source,
        )
        self.assertIsNotNone(discard_state, "Discard must have explicit confirmation state")
        self.assertRegex(
            source,
            rf"(?s)\.confirmationDialog\(.{{0,800}}?"
            rf"isPresented:\s*\${re.escape(discard_state.group('state'))}\b",
        )
        self.assertRegex(
            source,
            r"(?s)(?:Discard(?: session| recording)?.{0,600}?role:\s*\.destructive|"
            r"role:\s*\.destructive.{0,600}?Discard(?: session| recording)?)",
        )

    def test_debug_route_deterministically_previews_delayed_sync_recovery(self) -> None:
        self.assertIn('case "recording_delayed_sync_preview"', CONTENT)
        self.assertIn("RecordActivityView(preview: .delayedSync)", CONTENT)
        self.assertIn("case delayedSync", RECORDING)
        self.assertRegex(
            RECORDING,
            r"(?s)case \.delayedSync:.{0,1200}?\.syncingDevice"
            r".{0,1200}?(?:phaseTimedOut|finalizationRecovery|isFinalizationDelayed)",
            "The DEBUG route must deterministically show delayed syncing recovery",
        )

    def test_delayed_sync_preview_owns_correlated_attempt_without_sdk_writes(self) -> None:
        source = self.recording_source()
        preview_body = self.swift_function_body(source, "applyPreviewIfNeeded") or ""
        self.assertIn("case .delayedSync:", preview_body)
        delayed = preview_body.split("case .delayedSync:", 1)[1]

        attempt = re.search(
            r"(?s)(?:let\s+(?P<attempt>[A-Za-z_]\w*)\s*=\s*)?"
            r"NoomRecordingAttempt\(\s*"
            r"requestID:\s*(?P<request>[A-Za-z_]\w*)\s*,.{0,500}?"
            r"experience:\s*\.spotCheck",
            delayed,
        )
        self.assertIsNotNone(
            attempt,
            "Delayed preview must create app-owned Spot check attempt identity",
        )
        if attempt:
            request_name = attempt.group("request")
            self.assertRegex(
                delayed,
                rf"recordingRequestID\s*=\s*{re.escape(request_name)}\b",
            )
            if attempt.group("attempt"):
                self.assertRegex(
                    delayed,
                    rf"activeRecordingAttempt\s*=\s*"
                    rf"{re.escape(attempt.group('attempt'))}\b",
                )
            else:
                self.assertRegex(
                    delayed,
                    r"activeRecordingAttempt\s*=\s*NoomRecordingAttempt\(",
                )

        self.assertIn("recordingState = .finalizing(phase: .syncingDevice)", delayed)
        self.assertIn("finalizationRecovery = .phaseTimedOut(.syncingDevice)", delayed)
        self.assertNotRegex(
            delayed,
            r"sensorBio\.(?:record|finish|cancel|retry|pending)",
            "Preview recovery actions must be functional without SDK writes",
        )

        rearm = self.swift_function_body(source, "rearmWatchdog") or ""
        retry = self.swift_function_body(source, "retryDelayedFinalization") or ""
        self.assertIn("recordingRequestID == attempt.requestID", rearm)
        self.assertIn("if isPreview", rearm)
        self.assertIn("rearmWatchdog()", retry)

    def test_recording_recovery_never_exposes_raw_nserror_text(self) -> None:
        source = self.recording_source()
        self.assertNotRegex(source, r"\bNSError\b")
        self.assertNotIn("localizedDescription", source)

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
        start_controls = source[
            source.index("private func recordingStartControls"):
            source.index("private func recordingIcon")
        ]
        self.assertIn("isCancellationPending = true", cancel)
        self.assertIn("guard !isCancellationPending else { return false }", source)
        self.assertIn("if case .idle = state", source)
        self.assertIn(".disabled(", start_controls)
        self.assertIn("isCancellationPending", start_controls)
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
        self.assertIn("RecordActivityView(preview: .spotCheck)", CONTENT)
        self.assertIn("enum NoomRecordingPreview", RECORDING)
        self.assertRegex(
            RECORDING,
            r"(?s)case \.spotCheck:.{0,1200}?\.recording\(",
            "The Spot check debug route must remain an active live-recording preview",
        )

    def test_recording_source_and_docs_use_three_minute_spot_check_copy(self) -> None:
        source = self.recording_source()
        recording_docs = {
            "DESIGN_BRIEF": DESIGN.split("## Recording experiences", 1)[1].split(
                "## Accessibility and privacy",
                1,
            )[0],
            "NAVIGATION_MAP": NAVIGATION.split("Floating recording action", 1)[1].split(
                "Body Status",
                1,
            )[0],
            "SCREEN_STATES": STATES.split("## Recording states", 1)[1],
            "CAPABILITY_MATRIX": CAPABILITY_MATRIX.split(
                "| Home floating Record action",
                1,
            )[1],
        }
        documented_duration = re.compile(
            r"(?:spot check.{0,300}?(?:180-second|3-minute)|"
            r"(?:180-second|3-minute).{0,300}?spot check)",
            re.IGNORECASE | re.DOTALL,
        )
        for name, recording_section in recording_docs.items():
            self.assertRegex(
                recording_section,
                documented_duration,
                f"{name} must describe Spot check as 180 seconds / 3 minutes",
            )

        self.assertRegex(
            source,
            re.compile(
                r"(?:spot check.{0,300}?(?:180-second|3-minute|3\s+min)|"
                r"(?:180-second|3-minute|3\s+min).{0,300}?spot check)",
                re.IGNORECASE | re.DOTALL,
            ),
        )
        scoped_recording_copy = {"RecordingExperienceView": source, **recording_docs}
        for name, recording_copy in scoped_recording_copy.items():
            lowered = recording_copy.lower()
            for stale_copy in (
                "60-second spot check",
                "fixed 60-second",
                "one quiet minute",
            ):
                self.assertNotIn(
                    stale_copy,
                    lowered,
                    f"{name} still contains stale Spot check duration copy",
                )

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
