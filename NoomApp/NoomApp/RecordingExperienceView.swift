import SwiftUI
import Charts
import Combine
import SensorBioSDK

/// The two SDK-owned recording paths intentionally have different information hierarchies.
enum NoomRecordingExperience: String, Equatable, Sendable {
    case spotCheck
    case activity
}

#if DEBUG
enum NoomRecordingPreview {
    case hub
    case spotCheck
    case activity
    case delayedSync
}
#endif

private struct NoomRecordingSample: Identifiable, Equatable {
    let index: Int
    let value: Double
    var id: Int { index }
}

private let noomSpotCheckDuration: TimeInterval = 180
private let noomSpotCheckMinimumDuration: TimeInterval = 30
private let noomRenderedPPGSampleLimit = 300

private struct NoomRecordingCompletion {
    let experience: NoomRecordingExperience
    let activityName: String?
    let duration: TimeInterval
    let heartRate: Int?
    let hrv: Int?
    let ibi: Int?
    let evidence: NoomRecordingResolution.Terminal
}

/// Extended floating action inspired by Oura's lower-right recording entry, translated into Noom tokens.
struct NoomRecordingFloatingButton: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 17, weight: .bold))
            Text("Record")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(
            LinearGradient(
                colors: [NoomTheme.red, NoomTheme.red.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay { Capsule().stroke(Color.white.opacity(0.24), lineWidth: 1) }
        .shadow(color: NoomTheme.red.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

@MainActor
struct RecordActivityView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExperience: NoomRecordingExperience?
    @State private var activityName = "Walk"
    @State private var activityChoices = ["Walk", "Run", "Cycle", "Strength"]
    @State private var isLoadingActivities = false

    @State private var recordingState: SB_RecordingState = sensorBio.recordingState
    @State private var canFinalize = sensorBio.canFinalize
    @State private var isPaused = sensorBio.isRecordingPaused
    @State private var isBandReady = sensorBio.isFullyConfigured
    @State private var recordingTask: Task<Void, Never>?
    @State private var recordingRequestID: UUID?
    @State private var activeRecordingAttempt: NoomRecordingAttempt?
    @State private var ppgCaptureRequestID: UUID?
    @State private var isAwaitingRestoredRecording = false
    @State private var unsupportedRestoredKind: SB_PersistedRecordingKind?
    @State private var preservesRestoredActivityName = false
    @State private var isCancellationPending = false
    @State private var isStartingRecording = false
    @State private var lastElapsed: TimeInterval = 0
    @State private var spotCheckStartDate: Date?
    @State private var spotCheckNow = Date()

    @State private var latestHeartRate: Int?
    @State private var latestHRV: Int?
    @State private var latestIBI: Int?
    @State private var latestRR: Int?
    @State private var latestSpO2: Double?
    @State private var latestSNRDecibels: Double?
    @State private var telemetryFreshness = NoomLiveTelemetryFreshness()
    @State private var telemetryNow = Date()
    @Environment(\.scenePhase) private var scenePhase
    @State private var ppgInterpolator = NoomPPGSampleInterpolator()
    @State private var ppgYRangeSmoother = NoomPPGYRangeSmoother()
    @State private var ppgDisplayRange: ClosedRange<Double>?
    @State private var ppgDisplayTask: Task<Void, Never>?
    @State private var ppgDisplayToken: UUID?
    @State private var ppgSamples: [NoomRecordingSample] = []
    @State private var heartRateSamples: [NoomRecordingSample] = []
    @State private var showsMoreSignals = false

    @State private var completion: NoomRecordingCompletion?
    @State private var errorMessage: String?
    @State private var showsCancelConfirmation = false
    @State private var showsDelayedDiscardConfirmation = false
    @State private var finalizationPhase: NoomRecordingFinalizationPhase?
    @State private var finalizationRecovery: NoomRecordingResolution.Recoverable?
    @State private var finalizationWatchdogValue: NoomRecordingFinalizationWatchdog?
    @State private var finalizationWatchdogToken: UUID?
    @State private var finalizationWatchdogTask: Task<Void, Never>?
    @State private var failedSubmissionLocalID: UUID?
    @State private var delayedRetryTask: Task<Void, Never>?
    @State private var delayedRetryToken: UUID?

    private let finalizationPolicy = NoomRecordingFinalizationPolicy(
        phaseBounds: [
            .stoppingDevice: 30,
            .syncingDevice: 45,
            .submitting: 105,
        ],
        correlationToleranceMilliseconds: 15_000
    )

    #if DEBUG
    private let preview: NoomRecordingPreview?

    init(preview: NoomRecordingPreview? = nil) {
        self.preview = preview
    }
    #else
    init() {}
    #endif

    var body: some View {
        NoomScreen(spacing: 16, bottomPadding: 44) {
            recordingTopBar

            if unsupportedRestoredKind != nil {
                unsupportedRestoredRecording
            } else if selectedExperience == nil {
                recordingHub
            } else if selectedExperience == .spotCheck {
                spotCheckExperience
            } else {
                activityExperience
            }

            if isCancellationPending {
                NoomStateBanner(
                    title: "Ending previous recording",
                    detail: "Waiting for the Band to confirm the session has stopped.",
                    systemImage: "hourglass",
                    tint: NoomTheme.metricAmber
                )
            }

            if isStartingRecording {
                NoomStateBanner(
                    title: "Starting recording",
                    detail: "Keep this screen open while the Band begins capture.",
                    systemImage: "waveform",
                    tint: NoomTheme.mint
                )
            }

            if let errorMessage {
                NoomStateBanner(
                    title: "Recording didn't finish",
                    detail: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: NoomTheme.rose
                )
                .accessibilityElement(children: .combine)
            }
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isActive)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isStartingRecording {
                startingRecordingControlDock
            } else if isRecording {
                if unsupportedRestoredKind != nil {
                    unsupportedRecordingControlDock
                } else {
                    recordingControlDock
                }
            }
        }
        .onReceive(sensorBio.$recordingState.receive(on: RunLoop.main)) { state in
            guard !isPreview else { return }
            handleSDKRecordingState(state)
        }
        .onReceive(sensorBio.$canFinalize.receive(on: RunLoop.main)) { value in
            guard !isPreview, !isCancellationPending else { return }
            canFinalize = value
        }
        .onReceive(sensorBio.$isRecordingPaused.receive(on: RunLoop.main)) { value in
            guard !isPreview, !isCancellationPending else { return }
            isPaused = value
        }
        .onReceive(sensorBio.$isFullyConfigured.receive(on: RunLoop.main)) { value in
            guard !isPreview else { return }
            isBandReady = value
        }
        .onReceive(sensorBio.pendingSubmissionsPublisher.receive(on: RunLoop.main)) { submissions in
            guard !isPreview, let attempt = activeRecordingAttempt else { return }
            for submission in submissions {
                guard let evidence: NoomRecordingSubmissionEvidence = recordingSubmissionEvidence(
                    from: submission,
                    requestID: attempt.requestID
                ) else { continue }
                let resolution = finalizationPolicy.resolve(
                    submission: evidence,
                    for: attempt
                )
                if case .recoverable(.submissionFailed) = resolution {
                    failedSubmissionLocalID = submission.localId
                } else if resolution != .unresolved {
                    failedSubmissionLocalID = nil
                }
                handleFinalizationResolution(resolution, for: attempt)
                guard activeRecordingAttempt == attempt else { break }
            }
        }
        .onReceive(sensorBio.biometricRecordResult.receive(on: RunLoop.main)) { result in
            guard !isPreview, let attempt = activeRecordingAttempt else { return }
            let evidence = NoomBiometricResultEvidence(
                requestID: attempt.requestID,
                startEpoch: result.startEpoch,
                outcome: result.error == nil
                    ? .success(resultID: result.id)
                    : .failure
            )
            let resolution = finalizationPolicy.resolve(
                biometricResult: evidence,
                for: attempt
            )
            handleFinalizationResolution(resolution, for: attempt)
        }
        .onReceive(sensorBio.ppg.receive(on: RunLoop.main)) { _, rawValue in
            guard !isPreview,
                  let attempt = activeRecordingAttempt,
                  attempt.experience == .spotCheck,
                  recordingRequestID == attempt.requestID,
                  ppgCaptureRequestID == attempt.requestID else { return }
            let value = Double(rawValue)
            guard value.isFinite else { return }
            ppgInterpolator.enqueue(value)
        }
        .onReceive(sensorBio.hr.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestHeartRate = value
            recordTelemetrySample()
            appendBounded(Double(value), to: &heartRateSamples, limit: 80)
        }
        .onReceive(sensorBio.hrv.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestHRV = value
            recordTelemetrySample()
        }
        .onReceive(sensorBio.bbi.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestIBI = value
            recordTelemetrySample()
        }
        .onReceive(sensorBio.rr.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestRR = value
            recordTelemetrySample()
        }
        .onReceive(sensorBio.spo2.receive(on: RunLoop.main)) { _, rawValue in
            guard !isPreview else { return }
            let value = Double(rawValue)
            guard value.isFinite, value > 0 else { return }
            latestSpO2 = value
        }
        .onReceive(sensorBio.snr.receive(on: RunLoop.main)) { _, rawValue in
            guard !isPreview else { return }
            latestSNRDecibels = NoomSignalQuality.displayDecibels(
                rawSNR: Double(rawValue)
            )
            if latestSNRDecibels != nil {
                recordTelemetrySample()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isPreview else { return }
            telemetryFreshness.setForeground(phase == .active, at: Date())
            telemetryNow = Date()
            if phase == .active, isActive {
                // The SDK-owned recording continued while suspended; rebind
                // to it so elapsed truth and completion ownership resume,
                // and let stale live values show their stale treatment
                // until fresh samples arrive.
                restorePersistedRecordingIfNeeded()
            }
        }
        .task(id: telemetryFreshnessTickToken) {
            // Freshness can decay without any new event (Band out of range).
            // A 1-second truth tick keeps the stale banner honest while a
            // recording is active; it renders nothing when idle.
            guard telemetryFreshnessTickToken != nil, !isPreview else { return }
            while !Task.isCancelled {
                telemetryNow = Date()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
        .task {
            #if DEBUG
            applyPreviewIfNeeded()
            #endif
            guard !isPreview else { return }
            restorePersistedRecordingIfNeeded()
            await loadActivityChoices()
        }
        .task(id: spotCheckStartDate) {
            guard spotCheckStartDate != nil, !isPreview else { return }
            while !Task.isCancelled {
                spotCheckNow = Date()
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
        .onDisappear {
            ppgCaptureRequestID = nil
            stopPPGDisplay(reset: true)
            cancelFinalizationWatchdog(clearPhase: false)
            cancelDelayedRetry()
            guard isStartingRecording, !isPreview else { return }
            cancelRecording()
        }
        .confirmationDialog(
            "Cancel this recording?",
            isPresented: $showsCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel recording", role: .destructive) { cancelRecording() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("This session will not be saved.")
        }
        .confirmationDialog(
            "Discard this delayed session?",
            isPresented: $showsDelayedDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard session", role: .destructive) { cancelRecording() }
            Button("Keep waiting", role: .cancel) {}
        } message: {
            Text("Discard only if you no longer want this session. Noom+ will not discard it automatically.")
        }
    }

    private var recordingTopBar: some View {
        HStack(spacing: 12) {
            if !isActive {
                Button {
                    if selectedExperience == nil {
                        dismiss()
                    } else {
                        completion = nil
                        errorMessage = nil
                        selectedExperience = nil
                    }
                } label: {
                    Image(systemName: selectedExperience == nil ? "xmark" : "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NoomTheme.logoBlack)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.84), in: Circle())
                        .overlay { Circle().stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedExperience == nil ? "Close recording" : "Back to recording choices")
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NoomTheme.red)
                    .frame(width: 44, height: 44)
                    .background(NoomTheme.rose, in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("RECORD")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(NoomTheme.muted)
                Text(topBarTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.logoBlack)
            }

            Spacer()

            if isPreview {
                NoomPill(title: "QA sample", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
            } else {
                NoomPill(
                    title: finalizationRecovery != nil || isFinalizing
                        ? (isBandReady ? "Band available · finalizing" : "Band unavailable · finalizing")
                        : (isBandReady ? "Band ready" : (sensorBio.haveDevice ? "Band getting ready" : "Band not ready")),
                    color: isBandReady ? NoomTheme.mint : NoomTheme.rose,
                    foreground: NoomTheme.logoBlack
                )
            }
        }
    }

    private var topBarTitle: String {
        if unsupportedRestoredKind != nil { return "Active recording" }
        switch selectedExperience {
        case .spotCheck: return "Spot check"
        case .activity: return activityName
        case nil: return "Choose a session"
        }
    }

    private var recordingHub: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A clearer look at your body, right now.")
                    .noomSerifTitle(size: 32)
                Text("Choose a three-minute check or track a longer activity with live Noom Band signals.")
                    .noomBody()
            }

            NoomRecordingAmbientHero()

            Button {
                selectedExperience = .spotCheck
                clearSessionFeedback()
            } label: {
                NoomCard(fill: Color.white.opacity(0.92), padding: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        recordingIcon("waveform.path.ecg", tint: NoomTheme.red, fill: NoomTheme.rose)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Spot check")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Spacer()
                                NoomPill(title: "3 min", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
                            }
                            Text("Live PPG, heart rate, HRV, IBI, breathing, and signal context while you stay still.")
                                .noomBody()
                            Label("Best for a quick body check", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(NoomTheme.red)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(NoomTheme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the guided three-minute biometrics capture")

            Button {
                selectedExperience = .activity
                clearSessionFeedback()
            } label: {
                NoomCard(fill: NoomTheme.ink, padding: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        recordingIcon("figure.run", tint: .white, fill: Color.white.opacity(0.12))
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Activity tracking")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                NoomPill(title: "Open ended", color: NoomTheme.red, foreground: .white)
                            }
                            Text("Elapsed time and live heart rate stay in focus. Pause, resume, or finish anytime.")
                                .font(.system(size: 15))
                                .lineSpacing(3)
                                .foregroundStyle(.white.opacity(0.76))
                            Label("Best for walks, runs, rides, and training", systemImage: "timer")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(NoomTheme.rose)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens open-ended activity tracking")
        }
    }

    @ViewBuilder
    private var spotCheckExperience: some View {
        if let completion, completion.experience == .spotCheck {
            completionCard(completion)
        } else if finalizationRecovery != nil {
            delayedFinalizationCard
        } else if isFinalizing {
            finalizingCard
        } else if isRecording {
            spotCheckLive
        } else {
            spotCheckReady
        }
    }

    private var spotCheckReady: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Three quiet minutes.")
                    .noomSerifTitle(size: 40)
                Text("Sit comfortably, rest your arm, and keep the Band snug. Your live values appear only when the Band emits them.")
                    .noomBody()
            }

            NoomCard(fill: Color.white.opacity(0.92), padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("3-minute spot check")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                            Text("Finish is available after 30 seconds when the SDK's signal criteria are met.")
                                .noomLabel()
                        }
                        Spacer()
                        ZStack {
                            Circle().fill(NoomTheme.rose).frame(width: 66, height: 66)
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(NoomTheme.red)
                        }
                    }
                    Divider().overlay(NoomTheme.softLine)
                    NoomRecordingFeatureRow(title: "Live PPG", detail: "A moving pulse waveform", systemImage: "waveform")
                    NoomRecordingFeatureRow(title: "Beat timing", detail: "HR, HRV, and IBI as available", systemImage: "heart.fill")
                    NoomRecordingFeatureRow(title: "Breathing & oxygen", detail: "RR and SpO₂ when emitted", systemImage: "lungs.fill")
                }
            }

            Text("PPG is a light-based pulse signal, not an ECG or diagnosis.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NoomTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            recordingStartControls(title: "Start spot check", systemImage: "waveform.path.ecg", action: startSpotCheck)
        }
    }

    private var spotCheckLive: some View {
        let timerPresentation = NoomSpotCheckTimerPresentation(
            elapsed: spotCheckWallClockElapsed,
            target: noomSpotCheckDuration
        )
        return VStack(alignment: .leading, spacing: 16) {
            NoomCard(fill: NoomTheme.ink, padding: 18) {
                VStack(spacing: 12) {
                    HStack {
                        Label(
                            isTelemetryStale
                                ? "Waiting for fresh samples"
                                : (latestHeartRate == nil ? "Finding your signal" : "Live signal"),
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                isTelemetryStale
                                    ? NoomTheme.metricAmber
                                    : (latestHeartRate == nil ? .white.opacity(0.72) : NoomTheme.mint)
                            )
                        Spacer()
                        Text(latestSNRDecibels.map {
                            "Signal \($0.formatted(.number.precision(.fractionLength(1)))) dB"
                        } ?? "Signal —")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    if isTelemetryStale {
                        Text("Recording continues on your Band. Live values will refresh when fresh samples arrive.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NoomTheme.metricAmber)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("recording-telemetry-stale")
                    }

                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 15)
                        Circle()
                            .trim(from: 0, to: spotCheckProgress)
                            .stroke(NoomTheme.red, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 3) {
                            Text(timerPresentation.text)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(timerPresentation.unit)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .frame(width: 146, height: 146)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(timerPresentation.accessibilityLabel)

                    Text("Stay still and breathe normally")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .frame(maxWidth: .infinity)
            }

            NoomCard(fill: Color.white.opacity(0.92), padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Live PPG")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text(ppgSamples.isEmpty ? "Finding the pulse waveform" : "Recent live samples")
                                .noomLabel()
                        }
                        Spacer()
                        Image(systemName: "waveform.path")
                            .foregroundStyle(NoomTheme.red)
                    }
                    NoomRecordingSignalWaveform(samples: ppgSamples, yRange: ppgDisplayRange)
                        .frame(height: 82)
                        .animation(.linear(duration: 0.04), value: ppgSamples.last?.index)
                    Text("Light-based pulse signal · for wellness context, not ECG or medical diagnosis")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(NoomTheme.muted)
                }
            }

            spotCheckMetricGrid

            Text("Live estimates update only when the Band emits a valid sample. Final insights may change after processing.")
                .font(.footnote)
                .foregroundStyle(NoomTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spotCheckMetricGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live metrics")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Provisional until processing completes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NoomTheme.muted)
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { showsMoreSignals.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(showsMoreSignals ? "Fewer signals" : "More live signals")
                        Image(systemName: showsMoreSignals ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.red)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows IBI, breathing, oxygen, and signal strength")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NoomRecordingMetricTile(label: "HR", value: latestHeartRate.map(String.init), unit: "bpm", systemImage: "heart.fill", tint: NoomTheme.red)
                NoomRecordingMetricTile(label: "HRV", value: latestHRV.map(String.init), unit: "ms", systemImage: "waveform.path.ecg", tint: NoomTheme.metricPurple)
            }

            if showsMoreSignals {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NoomRecordingMetricTile(label: "IBI", value: latestIBI.map(String.init), unit: "ms", systemImage: "metronome.fill", tint: NoomTheme.metricBlue)
                    NoomRecordingMetricTile(label: "Breathing", value: latestRR.map(String.init), unit: "/min", systemImage: "lungs.fill", tint: NoomTheme.metricGreen)
                    NoomRecordingMetricTile(label: "SpO₂", value: latestSpO2.map { $0.formatted(.number.precision(.fractionLength(0...1))) }, unit: "%", systemImage: "drop.fill", tint: NoomTheme.metricBlue)
                    NoomRecordingMetricTile(label: "Signal", value: latestSNRDecibels.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: latestSNRDecibels == nil ? "" : "dB", systemImage: "antenna.radiowaves.left.and.right", tint: NoomTheme.metricAmber)
                }
            }
        }
    }

    @ViewBuilder
    private var activityExperience: some View {
        if let completion, completion.experience == .activity {
            completionCard(completion)
        } else if finalizationRecovery != nil {
            delayedFinalizationCard
        } else if isFinalizing {
            finalizingCard
        } else if isRecording {
            activityLive
        } else {
            activityReady
        }
    }

    private var activityReady: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Move with the signals that matter.")
                    .noomSerifTitle(size: 38)
                Text("Track elapsed time and live heart rhythm without inventing distance, pace, or calories your Band has not provided.")
                    .noomBody()
            }

            NoomCard(fill: NoomTheme.ink, padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Choose an activity")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(isLoadingActivities ? "Loading recent activities" : "Recent and featured options")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer()
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 31))
                            .foregroundStyle(NoomTheme.red)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(activityChoices.prefix(6)), id: \.self) { choice in
                            Button {
                                activityName = choice
                            } label: {
                                Text(choice)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(activityName == choice ? NoomTheme.logoBlack : .white.opacity(0.82))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(activityName == choice ? NoomTheme.rose : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(activityName == choice ? NoomTheme.red.opacity(0.24) : Color.white.opacity(0.08), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            NoomCard(fill: Color.white.opacity(0.92), padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("While you move")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    NoomRecordingFeatureRow(title: "Elapsed time", detail: "Count-up recording that survives relaunch", systemImage: "timer")
                    NoomRecordingFeatureRow(title: "Live heart rate", detail: "Current HR and bounded recent trend", systemImage: "heart.fill")
                    NoomRecordingFeatureRow(title: "Rhythm context", detail: "HRV, IBI, and SNR when available", systemImage: "waveform.path.ecg")
                }
            }

            recordingStartControls(title: "Start \(activityName)", systemImage: "figure.run", action: startActivity)
        }
    }

    private var activityLive: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoomCard(fill: NoomTheme.ink, padding: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isPaused ? NoomTheme.metricAmber : NoomTheme.red)
                                .frame(width: 9, height: 9)
                            Text(isPaused ? "Paused" : "Recording")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Text(isTelemetryStale ? "RECONNECTING" : "LIVE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(isTelemetryStale ? NoomTheme.metricAmber : .white.opacity(0.68))
                            .accessibilityLabel(isTelemetryStale ? "Waiting for fresh Band samples" : "Live")
                    }

                    if isTelemetryStale {
                        Text("Recording continues on your Band. Live values will refresh when fresh samples arrive.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NoomTheme.metricAmber)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("recording-telemetry-stale")
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ELAPSED")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.66))
                        Text(timerText)
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .minimumScaleFactor(0.7)
                            .accessibilityLabel("Elapsed time \(spokenDuration(lastElapsed))")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HEART RATE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.66))
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(NoomTheme.red)
                            Text(latestHeartRate.map(String.init) ?? "—")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("bpm")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    HStack {
                        Text("RECENT HR TREND")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                        Spacer()
                        Text(isTelemetryStale ? "Waiting for fresh samples" : "Live samples")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.62))

                    NoomRecordingHeartRateChart(samples: heartRateSamples)
                        .frame(height: 94)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NoomRecordingMetricTile(label: "HRV", value: latestHRV.map(String.init), unit: "ms", systemImage: "waveform.path.ecg", tint: NoomTheme.metricPurple, compact: true)
                NoomRecordingMetricTile(label: "IBI", value: latestIBI.map(String.init), unit: "ms", systemImage: "metronome.fill", tint: NoomTheme.metricBlue, compact: true)
                NoomRecordingMetricTile(label: "Signal", value: latestSNRDecibels.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: latestSNRDecibels == nil ? "" : "dB", systemImage: "antenna.radiowaves.left.and.right", tint: NoomTheme.metricAmber, compact: true)
            }

            Text("Live values are provisional. Processed session insights may differ after saving.")
                .font(.footnote)
                .foregroundStyle(NoomTheme.muted)
        }
    }

    @ViewBuilder
    private var unsupportedRestoredRecording: some View {
        if finalizationRecovery != nil {
            delayedFinalizationCard
        } else if isFinalizing {
            finalizingCard
        } else {
            VStack(alignment: .leading, spacing: 16) {
                NoomCard(fill: NoomTheme.ink, padding: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        NoomPill(title: "SDK-OWNED SESSION", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
                        Text(unsupportedRestoredTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(timerText)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("Noom+ keeps this session separate instead of presenting it as a Spot check or Activity. Keep the Band nearby while the SDK finishes, or cancel below.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                NoomStateBanner(
                    title: "This recording type is not available here",
                    detail: "The active session remains SDK-owned and will continue without fabricated metrics or controls.",
                    systemImage: "waveform.badge.exclamationmark",
                    tint: NoomTheme.metricAmber
                )
            }
        }
    }

    private var unsupportedRestoredTitle: String {
        switch unsupportedRestoredKind {
        case .meditation: return "Meditation recording"
        case .activity: return "Activity recording"
        case .biometrics: return "Biometrics recording"
        case nil: return "Active recording"
        @unknown default: return "Unsupported recording"
        }
    }

    private var finalizingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoomCard(fill: NoomTheme.ink, padding: 24) {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: finalizationProgress)
                            .stroke(NoomTheme.red, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "waveform.badge.checkmark")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 118, height: 118)

                    VStack(spacing: 7) {
                        Text(finalizationTitle)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Keep the Band nearby. Noom+ is securing this session before you leave.")
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    HStack(spacing: 8) {
                        finalizationStep("Stop", step: 1)
                        finalizationStep("Sync", step: 2)
                        finalizationStep("Save", step: 3)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var delayedFinalizationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoomCard(fill: NoomTheme.ink, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(NoomTheme.metricAmber)
                            .frame(width: 54, height: 54)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(delayedFinalizationTitle)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(delayedFinalizationDetail)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.12))

                    HStack(spacing: 8) {
                        Circle()
                            .fill(isBandReady ? NoomTheme.mint : NoomTheme.metricAmber)
                            .frame(width: 9, height: 9)
                        Text(isBandReady ? "Band available · finalizing" : "Band unavailable · finalizing")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .accessibilityElement(children: .combine)

                    HStack(spacing: 10) {
                        Button("Keep waiting") {
                            rearmWatchdog()
                        }
                        .buttonStyle(NoomSecondaryButtonStyle())

                        Button("Try again") {
                            retryDelayedFinalization()
                        }
                        .buttonStyle(NoomPrimaryButtonStyle())
                        .disabled(delayedRetryToken != nil)
                    }

                    Button("Discard session", role: .destructive) {
                        showsDelayedDiscardConfirmation = true
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.rose)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }

            Text("Noom+ has not marked this session complete or discarded it. You choose whether to keep waiting, retry, or discard.")
                .font(.footnote)
                .foregroundStyle(NoomTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var delayedFinalizationTitle: String {
        guard let finalizationRecovery else { return "This session needs more time" }
        switch finalizationRecovery {
        case let .phaseTimedOut(phase):
            switch phase {
            case .stoppingDevice: return "Stopping is taking longer"
            case .syncingDevice: return "Still syncing your Band"
            case .submitting: return "Saving is taking longer"
            }
        case .submissionFailed:
            return "Saving needs another try"
        case .biometricResultFailed:
            return "This Spot check needs more time"
        }
    }

    private var delayedFinalizationDetail: String {
        guard let finalizationRecovery else {
            return "Keep your Band nearby while Noom+ waits for a durable completion update."
        }
        switch finalizationRecovery {
        case .phaseTimedOut(.syncingDevice):
            return "Band sync is taking longer than expected. Noom+ has not yet confirmed this session as saved or processed."
        case .phaseTimedOut(.stoppingDevice):
            return "The Band is taking longer to stop capture. Keep it nearby while Noom+ waits for confirmation."
        case .phaseTimedOut(.submitting):
            return "Noom+ is still waiting for a secure queue or processing update."
        case .submissionFailed:
            return "The durable submission needs another attempt. Noom+ has kept the retry action without exposing technical error text."
        case .biometricResultFailed:
            return "Noom+ received a Spot check failure signal. Retry or keep waiting for a durable submission update."
        }
    }

    private func finalizationStep(_ title: String, step: Int) -> some View {
        let activeStep = finalizationStepNumber
        return VStack(spacing: 6) {
            Circle()
                .fill(step <= activeStep ? NoomTheme.red : Color.white.opacity(0.14))
                .frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(step <= activeStep ? .white : .white.opacity(0.46))
        }
        .frame(maxWidth: .infinity)
    }

    private func completionCard(_ completion: NoomRecordingCompletion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            NoomCard(fill: NoomTheme.mint.opacity(0.78), padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.72)).frame(width: 72, height: 72)
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(NoomTheme.logoBlack)
                    }
                    completionStatusCopy(completion.evidence)
                }
            }

            NoomCard(fill: Color.white.opacity(0.92), padding: 18) {
                VStack(spacing: 0) {
                    NoomDetailValueRow(label: completion.experience == .activity ? "Activity" : "Type", value: completion.activityName ?? "Spot check", verticalPadding: 9)
                    NoomDetailValueRow(label: "Duration", value: durationText(completion.duration), verticalPadding: 9)
                    NoomDetailValueRow(label: "Last HR", value: completion.heartRate.map { "\($0) bpm" } ?? "—", verticalPadding: 9)
                    NoomDetailValueRow(label: "Last HRV", value: completion.hrv.map { "\($0) ms" } ?? "—", verticalPadding: 9)
                    NoomDetailValueRow(label: "Last IBI", value: completion.ibi.map { "\($0) ms" } ?? "—", verticalPadding: 9)
                }
            }

            Text("These are the last live values received during capture, not a medical interpretation or final processed analysis.")
                .font(.footnote)
                .foregroundStyle(NoomTheme.muted)

            Button("Done") {
                self.completion = nil
                selectedExperience = nil
                preservesRestoredActivityName = false
                clearLiveMetrics()
            }
            .buttonStyle(NoomPrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private func completionStatusCopy(_ evidence: NoomRecordingResolution.Terminal) -> some View {
        switch evidence {
        case .submissionPending:
            Text("Session secured locally")
                .noomSerifTitle(size: 36)
            Text("Your session is queued for secure upload. It is not processed yet.")
                .noomBody()
        case .submissionUploaded:
            Text("Session uploaded")
                .noomSerifTitle(size: 36)
            Text("Your session is uploaded and processing securely in the background.")
                .noomBody()
        case .submissionProcessed, .biometricResult:
            Text("Session ready")
                .noomSerifTitle(size: 36)
            Text("Your session has a completed processing result.")
                .noomBody()
        case .orchestrationReturned:
            Text("Session saved")
                .noomSerifTitle(size: 36)
            Text("Processing continues securely in the background.")
                .noomBody()
        }
    }

    private var startingRecordingControlDock: some View {
        Button("Cancel start", role: .cancel) {
            cancelRecording()
        }
        .buttonStyle(NoomSecondaryButtonStyle())
        .padding(.horizontal, NoomTheme.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(NoomTheme.ink.opacity(0.08)).frame(height: 1) }
    }

    private var unsupportedRecordingControlDock: some View {
        Button("Cancel active recording", role: .destructive) {
            showsCancelConfirmation = true
        }
        .buttonStyle(NoomSecondaryButtonStyle())
        .padding(.horizontal, NoomTheme.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(NoomTheme.ink.opacity(0.08)).frame(height: 1) }
    }

    private var recordingControlDock: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                if selectedExperience == .activity {
                    Button {
                        showsCancelConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NoomTheme.red)
                            .frame(width: 52, height: 52)
                            .background(Color.white, in: Circle())
                            .overlay { Circle().stroke(NoomTheme.red.opacity(0.18), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel activity")

                    Button {
                        toggleRecordingPause()
                    } label: {
                        Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(NoomSecondaryButtonStyle())
                } else {
                    Button("Cancel") { showsCancelConfirmation = true }
                        .buttonStyle(NoomSecondaryButtonStyle())
                }

                Button {
                    finishRecording()
                } label: {
                    Label("Finish & save", systemImage: "stop.fill")
                }
                .buttonStyle(NoomPrimaryButtonStyle())
                .disabled(!canFinalize || !isBandReady)
            }

            if !isBandReady {
                Text("Band getting ready. Finish will be available when the Band is fully configured.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
            } else if !canFinalize {
                Text("Finish is available after 30 seconds when the SDK's signal criteria are met.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
            }
        }
        .padding(.horizontal, NoomTheme.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(NoomTheme.ink.opacity(0.08)).frame(height: 1) }
    }

    private func recordingStartControls(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(NoomPrimaryButtonStyle())
            .disabled(!isBandReady || recordingTask != nil || isCancellationPending)

            if !isBandReady {
                NavigationLink { NoomBandSetupEntryView() } label: {
                    Label(sensorBio.haveDevice ? "Check Noom Band" : "Set up Noom Band", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(NoomSecondaryButtonStyle())

                Text(sensorBio.haveDevice ? "Band getting ready. Recording starts only after full configuration." : "Band not ready. Set up a Noom Band before recording.")
                    .font(.footnote)
                    .foregroundStyle(NoomTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func recordingIcon(_ name: String, tint: Color, fill: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 56, height: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var isActive: Bool {
        if completion != nil { return false }
        if finalizationRecovery != nil { return true }
        if isStartingRecording { return true }
        if isCancellationPending { return true }
        if case .idle = recordingState { return false }
        return true
    }

    private var isRecording: Bool {
        guard !isCancellationPending else { return false }
        if case .recording = recordingState { return true }
        return false
    }

    private var isFinalizing: Bool {
        guard !isCancellationPending else { return false }
        if case .finalizing = recordingState { return true }
        return false
    }

    private var isPreview: Bool {
        #if DEBUG
        return preview != nil
        #else
        return false
        #endif
    }

    private var spotCheckWallClockElapsed: TimeInterval {
        guard let start = spotCheckStartDate else { return 0 }
        return max(0, spotCheckNow.timeIntervalSince(start))
    }

    private var spotCheckProgress: Double {
        min(max(spotCheckWallClockElapsed / noomSpotCheckDuration, 0), 1)
    }

    private var timerText: String { durationText(lastElapsed) }

    private func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        if seconds >= 3600 {
            return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func spokenDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return "\(seconds / 60) minutes, \(seconds % 60) seconds"
    }

    private var finalizationTitle: String {
        guard case let .finalizing(phase) = recordingState else { return "Saving session" }
        switch phase {
        case .stoppingDevice:
            return "Stopping capture"
        case .syncingDevice:
            return "Syncing your Band"
        case .submitting:
            return "Saving session"
        @unknown default:
            return "Finishing session"
        }
    }

    private var finalizationStepNumber: Int {
        guard case let .finalizing(phase) = recordingState else { return 1 }
        switch phase {
        case .stoppingDevice: return 1
        case .syncingDevice: return 2
        case .submitting: return 3
        @unknown default: return 1
        }
    }

    private var finalizationProgress: Double {
        Double(finalizationStepNumber) / 3
    }

    private func startSpotCheck() {
        selectedExperience = .spotCheck
        beginRecording(.spotCheck)
    }

    private func startActivity() {
        selectedExperience = .activity
        beginRecording(.activity)
    }

    private func beginRecording(_ experience: NoomRecordingExperience) {
        guard !isPreview else { return }
        guard !isCancellationPending, recordingTask == nil else { return }
        guard finalizationPolicy.canStartRecording(
            connected: false,
            isFullyConfigured: isBandReady
        ) else {
            errorMessage = sensorBio.haveDevice
                ? "Band getting ready. Keep it nearby and try again when it is fully configured."
                : "Band not ready. Set up a Noom Band before recording."
            return
        }

        cancelFinalizationWatchdog(clearPhase: true)
        cancelDelayedRetry()
        ppgCaptureRequestID = nil
        stopPPGDisplay(reset: true)
        clearSessionFeedback()
        clearLiveMetrics()
        unsupportedRestoredKind = nil
        isAwaitingRestoredRecording = false
        preservesRestoredActivityName = false
        isStartingRecording = true
        lastElapsed = 0

        let requestID = UUID()
        let now = Date()
        let attempt = NoomRecordingAttempt(
            requestID: requestID,
            experience: experience,
            startedAtMilliseconds: epochMilliseconds(for: now)
        )
        recordingRequestID = requestID
        activeRecordingAttempt = attempt
        ppgCaptureRequestID = experience == .spotCheck ? requestID : nil
        if experience == .spotCheck {
            spotCheckStartDate = now
            spotCheckNow = now
        } else {
            spotCheckStartDate = nil
        }

        recordingTask = Task { @MainActor in
            do {
                switch experience {
                case .spotCheck:
                    try await sensorBio.recordDetailedBiometrics(
                        duration: noomSpotCheckDuration,
                        minDuration: noomSpotCheckMinimumDuration
                    )
                case .activity:
                    try await sensorBio.recordActivity(activityName: activityName, minDuration: 30)
                }
                guard recordingRequestID == requestID,
                      activeRecordingAttempt == attempt else { return }
                let resolution = finalizationPolicy.resolve(
                    orchestrationReturn: attempt,
                    for: attempt
                )
                handleFinalizationResolution(resolution, for: attempt)
            } catch is CancellationError {
                guard recordingRequestID == requestID,
                      activeRecordingAttempt == attempt else { return }
                isStartingRecording = false
            } catch {
                guard recordingRequestID == requestID,
                      activeRecordingAttempt == attempt else { return }
                failRecordingAttempt(attempt, message: recordingErrorMessage(error))
            }
        }
    }

    private func toggleRecordingPause() {
        guard !isPreview else { return }
        if isPaused {
            sensorBio.resumeRecording()
        } else {
            sensorBio.pauseRecording()
        }
    }

    private func finishRecording() {
        guard !isPreview else { return }
        guard isBandReady else {
            errorMessage = "Band getting ready. Keep it nearby until it is fully configured before finishing."
            return
        }
        guard canFinalize,
              let attempt = activeRecordingAttempt,
              recordingRequestID == attempt.requestID else { return }
        sensorBio.finishCurrentRecording()
    }

    private func cancelRecording() {
        isCancellationPending = true
        isStartingRecording = false
        ppgCaptureRequestID = nil
        stopPPGDisplay(reset: true)
        cancelFinalizationWatchdog(clearPhase: true)
        cancelDelayedRetry()
        spotCheckStartDate = nil

        if isPreview {
            recordingTask?.cancel()
            recordingState = .idle
            isCancellationPending = false
        } else if isAwaitingRestoredRecording {
            sensorBio.cancelCurrentRecording()
        } else {
            recordingTask?.cancel()
        }

        recordingRequestID = nil
        activeRecordingAttempt = nil
        recordingTask = nil
        isAwaitingRestoredRecording = false
        unsupportedRestoredKind = nil
        preservesRestoredActivityName = false
        completion = nil
        errorMessage = nil
        selectedExperience = nil
        lastElapsed = 0
        failedSubmissionLocalID = nil
        clearLiveMetrics()
    }

    private func completeRecording(
        _ attempt: NoomRecordingAttempt,
        evidence: NoomRecordingResolution.Terminal
    ) {
        guard recordingRequestID == attempt.requestID,
              activeRecordingAttempt == attempt,
              completion == nil else { return }

        let capturedDuration = max(lastElapsed, attempt.experience == .spotCheck ? spotCheckWallClockElapsed : 0)
        ppgCaptureRequestID = nil
        stopPPGDisplay(reset: true)
        cancelFinalizationWatchdog(clearPhase: true)
        cancelDelayedRetry()
        spotCheckStartDate = nil
        recordingState = .idle
        canFinalize = false
        isPaused = false
        isStartingRecording = false
        finalizationRecovery = nil
        failedSubmissionLocalID = nil
        completion = NoomRecordingCompletion(
            experience: attempt.experience,
            activityName: attempt.experience == .activity ? activityName : nil,
            duration: capturedDuration,
            heartRate: latestHeartRate,
            hrv: latestHRV,
            ibi: latestIBI,
            evidence: evidence
        )

        recordingRequestID = nil
        activeRecordingAttempt = nil
        recordingTask = nil
        isAwaitingRestoredRecording = false
        unsupportedRestoredKind = nil
    }

    private func failRecordingAttempt(_ attempt: NoomRecordingAttempt, message: String) {
        guard recordingRequestID == attempt.requestID,
              activeRecordingAttempt == attempt else { return }
        ppgCaptureRequestID = nil
        stopPPGDisplay(reset: true)
        cancelFinalizationWatchdog(clearPhase: true)
        cancelDelayedRetry()
        spotCheckStartDate = nil
        recordingState = .idle
        canFinalize = false
        isPaused = false
        isStartingRecording = false
        finalizationRecovery = nil
        failedSubmissionLocalID = nil
        errorMessage = message
        recordingRequestID = nil
        activeRecordingAttempt = nil
        recordingTask = nil
        isAwaitingRestoredRecording = false
    }

    private func restorePersistedRecordingIfNeeded() {
        guard let persisted = sensorBio.activeRecording else { return }
        preservesRestoredActivityName = false

        let experience: NoomRecordingExperience?
        switch persisted.kind {
        case .activity:
            experience = .activity
            selectedExperience = .activity
            if let restoredName = persisted.activityName, !restoredName.isEmpty {
                activityName = restoredName
                preservesRestoredActivityName = true
            }
        case .biometrics:
            experience = .spotCheck
            selectedExperience = .spotCheck
            spotCheckStartDate = persisted.startDate
            spotCheckNow = Date()
        case .meditation:
            experience = nil
            selectedExperience = nil
            unsupportedRestoredKind = .meditation
        @unknown default:
            experience = nil
            selectedExperience = nil
            unsupportedRestoredKind = persisted.kind
        }
        lastElapsed = currentElapsed

        guard recordingTask == nil else { return }
        ppgCaptureRequestID = nil
        stopPPGDisplay(reset: true)
        cancelDelayedRetry()
        let requestID = UUID()
        let attempt = experience.map {
            NoomRecordingAttempt(
                requestID: requestID,
                experience: $0,
                startedAtMilliseconds: persisted.startEpochMs
            )
        }
        recordingRequestID = requestID
        activeRecordingAttempt = attempt
        ppgCaptureRequestID = attempt?.experience == .spotCheck ? requestID : nil
        isAwaitingRestoredRecording = true
        recordingTask = Task { @MainActor in
            do {
                try await sensorBio.awaitActiveRecordingCompletion()
                guard recordingRequestID == requestID else { return }
                if let attempt {
                    guard activeRecordingAttempt == attempt else { return }
                    let resolution = finalizationPolicy.resolve(
                        orchestrationReturn: attempt,
                        for: attempt
                    )
                    handleFinalizationResolution(resolution, for: attempt)
                } else {
                    unsupportedRestoredKind = nil
                    recordingState = .idle
                    ppgCaptureRequestID = nil
                    recordingRequestID = nil
                    recordingTask = nil
                    isAwaitingRestoredRecording = false
                }
            } catch is CancellationError {
                guard recordingRequestID == requestID else { return }
            } catch {
                guard recordingRequestID == requestID else { return }
                if let attempt {
                    guard activeRecordingAttempt == attempt else { return }
                    failRecordingAttempt(attempt, message: recordingErrorMessage(error))
                } else {
                    unsupportedRestoredKind = nil
                    errorMessage = recordingErrorMessage(error)
                    ppgCaptureRequestID = nil
                    recordingRequestID = nil
                    recordingTask = nil
                    isAwaitingRestoredRecording = false
                }
            }
        }

        handleSDKRecordingState(recordingState)
        if let attempt {
            resolvePendingSubmissionSnapshot(for: attempt)
        }
    }

    private func handleSDKRecordingState(_ state: SB_RecordingState) {
        if isCancellationPending {
            if case .idle = state {
                isCancellationPending = false
                recordingState = .idle
                canFinalize = false
                isPaused = false
                ppgCaptureRequestID = nil
                stopPPGDisplay(reset: true)
                cancelFinalizationWatchdog(clearPhase: true)
            }
            return
        }

        if completion != nil, activeRecordingAttempt == nil {
            if case .idle = state {
                recordingState = .idle
            }
            return
        }

        if isStartingRecording {
            if case .idle = state {
                // Initial SDK idle still belongs to startup. Keep capture ownership and
                // any early Spot check packets until the SDK leaves idle.
                recordingState = .idle
                return
            }
            isStartingRecording = false
        }

        switch state {
        case .idle:
            if selectedExperience == .spotCheck, spotCheckStartDate != nil {
                lastElapsed = max(lastElapsed, spotCheckWallClockElapsed)
            }

            if !isStartingRecording,
               !isCancellationPending,
               completion == nil,
               recordingTask != nil,
               let attempt = activeRecordingAttempt,
               recordingRequestID == attempt.requestID {
                // The SDK has handed off capture while the exact awaited orchestration
                // remains unresolved. Preserve attempt ownership and reconcile durable
                // evidence under the app-owned submitting watchdog.
                recordingState = .finalizing(phase: .submitting)
                canFinalize = false
                isPaused = false
                spotCheckStartDate = nil
                ppgCaptureRequestID = nil
                stopPPGDisplay(reset: true)
                advanceFinalization(to: .submitting, for: attempt)
                resolvePendingSubmissionSnapshot(for: attempt)
                return
            }

            recordingState = .idle
            spotCheckStartDate = nil
            ppgCaptureRequestID = nil
            stopPPGDisplay(reset: true)
            cancelFinalizationWatchdog(clearPhase: finalizationRecovery == nil)
        case let .recording(elapsed, _):
            recordingState = state
            lastElapsed = max(lastElapsed, elapsed)
            finalizationRecovery = nil
            cancelFinalizationWatchdog(clearPhase: true)
            startPPGDisplayIfNeeded()
        case let .finalizing(sdkPhase):
            if selectedExperience == .spotCheck, spotCheckStartDate != nil {
                lastElapsed = max(lastElapsed, spotCheckWallClockElapsed)
            }
            recordingState = state
            spotCheckStartDate = nil
            ppgCaptureRequestID = nil
            stopPPGDisplay(reset: true)
            guard let attempt = activeRecordingAttempt,
                  recordingRequestID == attempt.requestID,
                  let phase = appFinalizationPhase(sdkPhase) else { return }
            advanceFinalization(to: phase, for: attempt)
        }
    }

    private func appFinalizationPhase(
        _ phase: SB_RecordingFinalizationPhase
    ) -> NoomRecordingFinalizationPhase? {
        switch phase {
        case .stoppingDevice: return .stoppingDevice
        case .syncingDevice: return .syncingDevice
        case .submitting: return .submitting
        @unknown default: return nil
        }
    }

    private var isActiveRealSpotCheckDisplay: Bool {
        guard !isPreview,
              let attempt = activeRecordingAttempt,
              attempt.experience == .spotCheck,
              recordingRequestID == attempt.requestID,
              ppgCaptureRequestID == attempt.requestID else { return false }
        if case .recording = recordingState { return true }
        return false
    }

    private func startPPGDisplayIfNeeded() {
        guard isActiveRealSpotCheckDisplay, ppgDisplayTask == nil else { return }
        let token = UUID()
        ppgDisplayToken = token
        ppgDisplayTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      ppgDisplayToken == token,
                      isActiveRealSpotCheckDisplay else { return }
                guard let frame = ppgInterpolator.nextFrame(), frame.isFinite else { continue }
                ppgSamples.append(
                    NoomRecordingSample(
                        index: (ppgSamples.last?.index ?? -1) + 1,
                        value: frame
                    )
                )
                if ppgSamples.count > noomRenderedPPGSampleLimit {
                    ppgSamples.removeFirst(ppgSamples.count - noomRenderedPPGSampleLimit)
                }
                ppgDisplayRange = ppgYRangeSmoother.update(
                    with: ppgSamples.map(\.value)
                )
            }
        }
    }

    private func stopPPGDisplay(reset: Bool) {
        ppgDisplayTask?.cancel()
        ppgDisplayTask = nil
        ppgDisplayToken = nil
        guard reset else { return }
        ppgInterpolator.reset()
        ppgYRangeSmoother.reset()
        ppgDisplayRange = nil
        ppgSamples = []
    }

    private func advanceFinalization(
        to phase: NoomRecordingFinalizationPhase,
        for attempt: NoomRecordingAttempt
    ) {
        guard recordingRequestID == attempt.requestID,
              activeRecordingAttempt == attempt else { return }
        if finalizationPhase == phase,
           finalizationWatchdogValue?.requestID == attempt.requestID {
            return
        }

        let enteredAt = ProcessInfo.processInfo.systemUptime
        let token = UUID()
        let nextWatchdog: NoomRecordingFinalizationWatchdog
        if let previous = finalizationWatchdogValue,
           previous.requestID == attempt.requestID {
            nextWatchdog = finalizationPolicy.advanceWatchdog(
                previous,
                to: phase,
                at: enteredAt,
                token: token
            )
        } else {
            nextWatchdog = finalizationPolicy.armWatchdog(
                for: attempt,
                phase: phase,
                enteredAt: enteredAt,
                token: token
            )
        }

        finalizationWatchdogTask?.cancel()
        finalizationPhase = phase
        finalizationRecovery = nil
        failedSubmissionLocalID = nil
        finalizationWatchdogValue = nextWatchdog
        finalizationWatchdogToken = token
        scheduleFinalizationWatchdog(nextWatchdog)
    }

    private func scheduleFinalizationWatchdog(
        _ watchdog: NoomRecordingFinalizationWatchdog
    ) {
        finalizationWatchdogTask?.cancel()
        let token = watchdog.token
        let attempt = watchdog.attempt
        let phase = watchdog.phase
        finalizationWatchdogTask = Task { @MainActor in
            do {
                try await Task.sleep(for: finalizationDelay(for: phase))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  finalizationWatchdogToken == token,
                  finalizationWatchdogValue == watchdog,
                  recordingRequestID == attempt.requestID,
                  activeRecordingAttempt == attempt,
                  finalizationPhase == phase else { return }
            let resolution = finalizationPolicy.resolve(
                timeout: watchdog,
                firedToken: token,
                requestID: attempt.requestID,
                phase: phase,
                now: ProcessInfo.processInfo.systemUptime
            )
            handleFinalizationResolution(resolution, for: attempt)
        }
    }

    private func finalizationDelay(
        for phase: NoomRecordingFinalizationPhase
    ) -> Duration {
        switch phase {
        case .stoppingDevice: return .seconds(30)
        case .syncingDevice: return .seconds(45)
        case .submitting: return .seconds(105)
        }
    }

    private func cancelFinalizationWatchdog(clearPhase: Bool) {
        finalizationWatchdogTask?.cancel()
        finalizationWatchdogTask = nil
        finalizationWatchdogToken = nil
        if clearPhase {
            finalizationWatchdogValue = nil
            finalizationPhase = nil
            finalizationRecovery = nil
        }
    }

    private func rearmWatchdog() {
        guard let attempt = activeRecordingAttempt,
              recordingRequestID == attempt.requestID else { return }
        let recoveryPhase: NoomRecordingFinalizationPhase?
        switch finalizationRecovery {
        case let .phaseTimedOut(phase): recoveryPhase = phase
        case .submissionFailed, .biometricResultFailed: recoveryPhase = .submitting
        case nil: recoveryPhase = finalizationPhase
        }
        guard let phase = recoveryPhase else { return }

        if isPreview {
            finalizationPhase = phase
            finalizationRecovery = nil
            return
        }

        let enteredAt = ProcessInfo.processInfo.systemUptime
        let token = UUID()
        let nextWatchdog: NoomRecordingFinalizationWatchdog
        if let previous = finalizationWatchdogValue,
           previous.requestID == attempt.requestID,
           previous.phase == phase {
            nextWatchdog = finalizationPolicy.rearmWatchdog(
                previous,
                at: enteredAt,
                token: token
            )
        } else {
            nextWatchdog = finalizationPolicy.armWatchdog(
                for: attempt,
                phase: phase,
                enteredAt: enteredAt,
                token: token
            )
        }

        finalizationWatchdogTask?.cancel()
        finalizationPhase = phase
        finalizationRecovery = nil
        finalizationWatchdogValue = nextWatchdog
        finalizationWatchdogToken = token
        scheduleFinalizationWatchdog(nextWatchdog)
    }

    private func retryDelayedFinalization() {
        guard let attempt = activeRecordingAttempt else { return }
        guard delayedRetryTask == nil,
              delayedRetryToken == nil,
              recordingRequestID == attempt.requestID else { return }

        let token = UUID()
        delayedRetryToken = token

        if isPreview {
            rearmWatchdog()
            delayedRetryToken = nil
            return
        }

        if let localID = failedSubmissionLocalID {
            sensorBio.retrySubmission(localId: localID)
            failedSubmissionLocalID = nil
            rearmWatchdog()
            delayedRetryToken = nil
            return
        }

        delayedRetryTask = Task { @MainActor in
            defer {
                if delayedRetryToken == token {
                    delayedRetryTask = nil
                    delayedRetryToken = nil
                }
            }

            // Reconcile on a later actor turn so repeated taps cannot race the same
            // durable snapshot or re-arm a stale attempt.
            await Task.yield()
            guard !Task.isCancelled,
                  delayedRetryToken == token,
                  recordingRequestID == attempt.requestID,
                  activeRecordingAttempt == attempt else { return }

            resolvePendingSubmissionSnapshot(for: attempt)

            let recoveryRemainsUnresolved = finalizationRecovery != nil
                || finalizationPhase != nil
            guard !Task.isCancelled,
                  delayedRetryToken == token,
                  recordingRequestID == attempt.requestID,
                  activeRecordingAttempt == attempt,
                  completion == nil,
                  recoveryRemainsUnresolved else { return }
            rearmWatchdog()
        }
    }

    private func cancelDelayedRetry() {
        delayedRetryTask?.cancel()
        delayedRetryTask = nil
        delayedRetryToken = nil
    }

    private func handleFinalizationResolution(
        _ resolution: NoomRecordingResolution,
        for attempt: NoomRecordingAttempt
    ) {
        guard recordingRequestID == attempt.requestID,
              activeRecordingAttempt == attempt else { return }
        switch resolution {
        case .unresolved:
            return
        case let .terminal(evidence):
            completeRecording(attempt, evidence: evidence)
        case let .recoverable(recovery):
            if selectedExperience == .spotCheck, spotCheckStartDate != nil {
                lastElapsed = max(lastElapsed, spotCheckWallClockElapsed)
            }
            spotCheckStartDate = nil
            ppgCaptureRequestID = nil
            stopPPGDisplay(reset: true)
            canFinalize = false
            isPaused = false
            finalizationWatchdogTask?.cancel()
            finalizationWatchdogTask = nil
            finalizationWatchdogToken = nil
            finalizationRecovery = recovery
            switch recovery {
            case let .phaseTimedOut(phase):
                finalizationPhase = phase
            case .submissionFailed, .biometricResultFailed:
                recordingState = .finalizing(phase: .submitting)
                if finalizationPhase == nil {
                    finalizationPhase = .submitting
                }
            }
        }
    }

    private func recordingSubmissionEvidence(
        from submission: SB_RecordingSubmissionInfo,
        requestID: UUID
    ) -> NoomRecordingSubmissionEvidence? {
        let experience: NoomRecordingExperience
        let type: NoomRecordingSubmissionEvidence.SubmissionType
        switch submission.type {
        case .biometricRecord:
            experience = .spotCheck
            type = .biometrics
        case .routine, .generalCardio, .gymWorkout:
            experience = .activity
            type = .activity
        case .vo2maxAssessment, .meditation:
            return nil
        @unknown default:
            return nil
        }

        let status: NoomRecordingSubmissionEvidence.Status
        switch submission.status {
        case .pendingUpload: status = .pending
        case .uploaded: status = .uploaded
        case .processed: status = .processed
        case .failed: status = .failed
        @unknown default: return nil
        }

        return NoomRecordingSubmissionEvidence(
            requestID: requestID,
            experience: experience,
            type: type,
            status: status,
            startedAtMilliseconds: submission.startTsMillis
        )
    }

    private func resolvePendingSubmissionSnapshot(for attempt: NoomRecordingAttempt) {
        for submission in sensorBio.pendingSubmissions() {
            guard recordingRequestID == attempt.requestID,
                  activeRecordingAttempt == attempt,
                  let evidence = recordingSubmissionEvidence(
                    from: submission,
                    requestID: attempt.requestID
                  ) else { continue }
            let resolution = finalizationPolicy.resolve(
                submission: evidence,
                for: attempt
            )
            if case .recoverable(.submissionFailed) = resolution {
                failedSubmissionLocalID = submission.localId
            } else if resolution != .unresolved {
                failedSubmissionLocalID = nil
            }
            handleFinalizationResolution(resolution, for: attempt)
        }
    }

    private func epochMilliseconds(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private var currentElapsed: TimeInterval {
        if case let .recording(elapsed, _) = recordingState { return elapsed }
        return lastElapsed
    }

    private func loadActivityChoices() async {
        isLoadingActivities = true
        defer { isLoadingActivities = false }
        do {
            let list = try await sensorBio.fetchActivityList()
            var seen = Set<String>()
            let choices = (list.recent + list.featured).filter { value in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return false }
                return seen.insert(cleaned.localizedLowercase).inserted
            }
            guard !choices.isEmpty else { return }
            if preservesRestoredActivityName {
                if choices.contains(where: { $0.caseInsensitiveCompare(activityName) == .orderedSame }) {
                    activityChoices = choices
                } else {
                    activityChoices = [activityName] + choices
                }
                return
            }
            activityChoices = choices
            if !choices.contains(where: { $0.caseInsensitiveCompare(activityName) == .orderedSame }) {
                activityName = choices[0]
            }
        } catch {
            // Generic local choices remain available; this lookup does not block recording.
        }
    }

    private func recordingErrorMessage(_ error: Error) -> String {
        guard let recordingError = error as? SB_RecordingError else {
            return "We couldn't complete this recording. Keep your Band nearby and try again."
        }
        switch recordingError {
        case .alreadyRecording:
            return "Another recording is already active. Return to it before starting a new one."
        case .noPairedDevice:
            return "Connect your Noom Band before starting a recording."
        case .bleStartFailed:
            return "The Band couldn't begin capture. Check the fit and connection, then try again."
        case .bleStopFailed:
            return "The Band stopped responding while finishing. Keep it nearby and try syncing again."
        case let .tooShort(_, minimum):
            return "Record for at least \(Int(minimum)) seconds before finishing."
        case .insufficientData:
            return "The Band didn't receive enough usable signal. Adjust the fit and try another spot check."
        @unknown default:
            return "We couldn't complete this recording. Keep your Band nearby and try again."
        }
    }

    private func appendBounded(_ value: Double, to samples: inout [NoomRecordingSample], limit: Int) {
        guard value.isFinite else { return }
        samples.append(
            NoomRecordingSample(
                index: (samples.last?.index ?? -1) + 1,
                value: value
            )
        )
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    private func clearSessionFeedback() {
        completion = nil
        errorMessage = nil
    }

    private func clearLiveMetrics() {
        latestHeartRate = nil
        latestHRV = nil
        latestIBI = nil
        latestRR = nil
        latestSpO2 = nil
        latestSNRDecibels = nil
        telemetryFreshness.reset()
        telemetryNow = Date()
        ppgInterpolator.reset()
        ppgYRangeSmoother.reset()
        ppgDisplayRange = nil
        ppgSamples = []
        heartRateSamples = []
    }

    private func recordTelemetrySample() {
        let now = Date()
        telemetryFreshness.recordSample(at: now)
        telemetryNow = now
    }

    /// Non-nil while a live recording surface is visible, so the freshness
    /// truth tick runs only when it can affect what the user sees.
    private var telemetryFreshnessTickToken: String? {
        guard !isPreview, isRecording, selectedExperience != nil else { return nil }
        return "recording-freshness"
    }

    private var telemetryPresentation: NoomLiveTelemetryFreshness.Presentation {
        telemetryFreshness.presentation(at: telemetryNow)
    }

    private var isTelemetryStale: Bool {
        telemetryPresentation == .stale
    }

    #if DEBUG
    private func applyPreviewIfNeeded() {
        guard let preview else { return }
        isBandReady = true
        switch preview {
        case .hub:
            selectedExperience = nil
        case .spotCheck:
            selectedExperience = .spotCheck
            recordingState = .recording(elapsed: 42, target: noomSpotCheckDuration)
            lastElapsed = 42
            spotCheckStartDate = Date().addingTimeInterval(-42)
            spotCheckNow = Date()
            canFinalize = true
            latestHeartRate = 68
            latestHRV = 47
            latestIBI = 882
            latestRR = 14
            latestSpO2 = 98
            latestSNRDecibels = NoomSignalQuality.displayDecibels(rawSNR: 72)
            ppgSamples = (0..<140).map { index in
                let x = Double(index)
                let pulse = sin(x * 0.31) + 0.24 * sin(x * 0.91) + 0.08 * sin(x * 2.1)
                return NoomRecordingSample(index: index, value: pulse)
            }
            ppgDisplayRange = ppgYRangeSmoother.update(with: ppgSamples.map(\.value))
        case .activity:
            selectedExperience = .activity
            activityName = "Walk"
            recordingState = .recording(elapsed: 742, target: nil)
            lastElapsed = 742
            canFinalize = true
            latestHeartRate = 118
            latestHRV = 31
            latestIBI = 508
            latestSNRDecibels = NoomSignalQuality.displayDecibels(rawSNR: 64)
            heartRateSamples = (0..<56).map { index in
                let value = 105 + Double(index) * 0.22 + sin(Double(index) * 0.38) * 7
                return NoomRecordingSample(index: index, value: value)
            }
        case .delayedSync:
            let requestID = UUID(uuidString: "D31A9ED0-5A7E-4E63-940D-6F01F87D9A11")!
            let attempt = NoomRecordingAttempt(
                requestID: requestID,
                experience: .spotCheck,
                startedAtMilliseconds: 1_700_000_000_000
            )
            recordingRequestID = requestID
            activeRecordingAttempt = attempt
            selectedExperience = .spotCheck
            recordingState = .finalizing(phase: .syncingDevice)
            lastElapsed = noomSpotCheckDuration
            finalizationPhase = .syncingDevice
            finalizationRecovery = .phaseTimedOut(.syncingDevice)
        }
    }
    #endif
}

private struct NoomRecordingAmbientHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [NoomTheme.rose.opacity(0.92), NoomTheme.mint.opacity(0.54)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(NoomTheme.red.opacity(0.12), lineWidth: 1)
                .frame(width: 102, height: 102)
                .scaleEffect(breathes ? 1.06 : 0.94)
            Circle()
                .fill(Color.white.opacity(0.62))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(NoomTheme.red)
                }
                .shadow(color: NoomTheme.ink.opacity(0.08), radius: 18, y: 10)
        }
        .frame(height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(NoomTheme.ink.opacity(0.06), lineWidth: 1) }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathes = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct NoomRecordingFeatureRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NoomTheme.red)
                .frame(width: 34, height: 34)
                .background(NoomTheme.rose.opacity(0.82), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.logoBlack)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NoomTheme.muted)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NoomRecordingMetricTile: View {
    let label: String
    let value: String?
    let unit: String
    let systemImage: String
    let tint: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(label)
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(.system(size: compact ? 22 : 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NoomTheme.logoBlack)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(.system(size: compact ? 9 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 82 : 98, alignment: .topLeading)
        .padding(compact ? 13 : 16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NoomTheme.ink.opacity(0.07), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value.map { "\($0) \(unit)" } ?? "not available")")
    }
}

private struct NoomRecordingSignalWaveform: View {
    let samples: [NoomRecordingSample]
    let yRange: ClosedRange<Double>?

    /// Low-intensity neighboring-point controls approximate the authoritative Charts
    /// `cubicBezier` geometry while keeping every segment bounded by real endpoints.
    private let cubicCurveIntensity: CGFloat = 0.1

    var body: some View {
        let finiteSamples = samples.filter { $0.index >= 0 && $0.value.isFinite }
        Canvas { context, size in
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else { return }

            guard !finiteSamples.isEmpty else {
                var idle = Path()
                idle.move(to: CGPoint(x: 0, y: size.height / 2))
                idle.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(
                    idle,
                    with: .color(NoomTheme.softLine),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 6])
                )
                return
            }

            guard let displayRange = resolvedYRange(for: finiteSamples),
                  let lastIndex = finiteSamples.last?.index else { return }
            let range = displayRange.upperBound - displayRange.lowerBound
            let fixedDomainSpan = Double(max(noomRenderedPPGSampleLimit - 1, 1))
            guard range.isFinite,
                  range > 0,
                  fixedDomainSpan.isFinite,
                  fixedDomainSpan > 0 else { return }

            // Indices 0...299 fill the fixed domain from left to right. From index
            // 300 onward, the start advances one point at a time instead of rescaling
            // the history by its current count.
            let viewportWindowStart = max(
                0,
                lastIndex - max(noomRenderedPPGSampleLimit - 1, 1)
            )
            let points = finiteSamples.compactMap { sample -> CGPoint? in
                let relativeIndex = Double(sample.index) - Double(viewportWindowStart)
                guard relativeIndex.isFinite,
                      relativeIndex >= 0,
                      relativeIndex <= fixedDomainSpan else { return nil }

                let normalized = (sample.value - displayRange.lowerBound) / range
                guard normalized.isFinite else { return nil }
                let boundedY = min(max(normalized, 0), 1)
                let x = size.width * CGFloat(
                    (Double(sample.index) - Double(viewportWindowStart)) / fixedDomainSpan
                )
                let y = size.height
                    - CGFloat(boundedY) * size.height * 0.76
                    - size.height * 0.12
                guard x.isFinite, y.isFinite else { return nil }
                return CGPoint(x: x, y: y)
            }

            guard let firstPoint = points.first else { return }
            if points.count == 1 {
                let radius = min(2.4, min(size.width / 2, size.height / 2))
                guard radius.isFinite, radius > 0 else { return }
                let marker = CGRect(
                    x: firstPoint.x - radius,
                    y: firstPoint.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: marker), with: .color(NoomTheme.red))
                return
            }

            var path = Path()
            path.move(to: firstPoint)
            for segmentIndex in 0..<(points.count - 1) {
                let segmentStart = points[segmentIndex]
                let segmentEnd = points[segmentIndex + 1]
                let priorPoint = segmentIndex > 0
                    ? points[segmentIndex - 1]
                    : segmentStart
                let followingPoint = segmentIndex + 2 < points.count
                    ? points[segmentIndex + 2]
                    : segmentEnd

                let minimumX = min(segmentStart.x, segmentEnd.x)
                let maximumX = max(segmentStart.x, segmentEnd.x)
                let minimumY = min(segmentStart.y, segmentEnd.y)
                let maximumY = max(segmentStart.y, segmentEnd.y)

                let rawControl1 = CGPoint(
                    x: segmentStart.x
                        + (segmentEnd.x - priorPoint.x) * cubicCurveIntensity,
                    y: segmentStart.y
                        + (segmentEnd.y - priorPoint.y) * cubicCurveIntensity
                )
                let rawControl2 = CGPoint(
                    x: segmentEnd.x
                        - (followingPoint.x - segmentStart.x) * cubicCurveIntensity,
                    y: segmentEnd.y
                        - (followingPoint.y - segmentStart.y) * cubicCurveIntensity
                )
                let control1 = CGPoint(
                    x: clamped(rawControl1.x, lower: minimumX, upper: maximumX),
                    y: clamped(rawControl1.y, lower: minimumY, upper: maximumY)
                )
                let control2 = CGPoint(
                    x: clamped(rawControl2.x, lower: minimumX, upper: maximumX),
                    y: clamped(rawControl2.y, lower: minimumY, upper: maximumY)
                )
                path.addCurve(
                    to: segmentEnd,
                    control1: control1,
                    control2: control2
                )
            }
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [NoomTheme.red.opacity(0.55), NoomTheme.red]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            finiteSamples.isEmpty
                ? "Live PPG waveform, waiting for signal"
                : "Live PPG waveform, \(finiteSamples.count) recent samples"
        )
    }

    private func clamped(
        _ value: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func resolvedYRange(
        for finiteSamples: [NoomRecordingSample]
    ) -> ClosedRange<Double>? {
        if let yRange,
           yRange.lowerBound.isFinite,
           yRange.upperBound.isFinite,
           yRange.lowerBound < yRange.upperBound {
            return yRange
        }

        guard let minimum = finiteSamples.map(\.value).min(),
              let maximum = finiteSamples.map(\.value).max() else {
            return nil
        }
        let observedRange = maximum - minimum
        guard observedRange.isFinite else { return nil }
        let effectiveRange = max(observedRange, 0.5)
        let center = minimum + observedRange / 2
        let padding = effectiveRange * 0.1
        let lower = center - effectiveRange / 2 - padding
        let upper = center + effectiveRange / 2 + padding
        guard lower.isFinite, upper.isFinite, lower < upper else { return nil }
        return lower...upper
    }
}

private struct NoomRecordingHeartRateChart: View {
    let samples: [NoomRecordingSample]

    var body: some View {
        let finiteSamples = samples.filter { $0.value.isFinite }
        Group {
            if finiteSamples.count > 1 {
                Chart(finiteSamples) { sample in
                    AreaMark(
                        x: .value("Sample", sample.index),
                        yStart: .value("Base", chartDomain.lowerBound),
                        yEnd: .value("Heart rate", sample.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NoomTheme.red.opacity(0.34), NoomTheme.red.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Sample", sample.index), y: .value("Heart rate", sample.value))
                        .foregroundStyle(NoomTheme.red)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    if sample.index == finiteSamples.last?.index {
                        PointMark(x: .value("Latest sample", sample.index), y: .value("Latest heart rate", sample.value))
                            .foregroundStyle(.white)
                            .symbolSize(42)
                    }
                }
                .chartXScale(domain: (finiteSamples.first?.index ?? 0)...(finiteSamples.last?.index ?? 1))
                .chartYScale(domain: chartDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { $0.background(.clear) }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Heart-rate trend appears as samples arrive")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartAccessibilityLabel(finiteSamples))
    }

    private var chartDomain: ClosedRange<Double> {
        let finite = samples.map(\.value).filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return 40...180 }
        let padding = max(8, (high - low) * 0.25)
        return max(0, low - padding)...(high + padding)
    }

    private func chartAccessibilityLabel(_ finiteSamples: [NoomRecordingSample]) -> String {
        guard let latest = finiteSamples.last?.value else { return "Live heart-rate trend, waiting for samples" }
        return "Live heart-rate trend, latest \(Int(latest.rounded())) beats per minute"
    }
}
