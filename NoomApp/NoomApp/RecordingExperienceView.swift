import SwiftUI
import Charts
import Combine
import SensorBioSDK

/// The two SDK-owned recording paths intentionally have different information hierarchies.
enum NoomRecordingExperience: String, Equatable {
    case spotCheck
    case activity
}

#if DEBUG
enum NoomRecordingPreview {
    case hub
    case spotCheck
    case activity
}
#endif

private struct NoomRecordingSample: Identifiable, Equatable {
    let index: Int
    let value: Double
    /// Timestamp of when the sample was recorded. Used for time‑based rendering of the PPG waveform.
    let timestamp: Date
    var id: Int { index }
}

private let noomSpotCheckDuration: TimeInterval = 180
private let noomPPGWindowDuration: TimeInterval = 5

private struct NoomRecordingCompletion {
    let experience: NoomRecordingExperience
    let activityName: String?
    let duration: TimeInterval
    let heartRate: Int?
    let hrv: Int?
    let ibi: Int?
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
    @State private var recordingTask: Task<Void, Never>?
    @State private var recordingRequestID: UUID?
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
    @State private var latestSNR: Double?
    @State private var ppgSamples: [NoomRecordingSample] = []
    @State private var heartRateSamples: [NoomRecordingSample] = []
    @State private var showsMoreSignals = false

    @State private var completion: NoomRecordingCompletion?
    @State private var errorMessage: String?
    @State private var showsCancelConfirmation = false

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
            if isCancellationPending {
                if case .idle = state {
                    isCancellationPending = false
                    recordingState = .idle
                    canFinalize = false
                    isPaused = false
                }
                return
            }
            if isStartingRecording {
                if case .idle = state {
                    // Keep startup ownership until the SDK leaves idle.
                } else {
                    isStartingRecording = false
                }
            }
            if case let .recording(elapsed, _) = state {
                lastElapsed = max(lastElapsed, elapsed)
            }
            recordingState = state
        }
        .onReceive(sensorBio.$canFinalize.receive(on: RunLoop.main)) { value in
            guard !isPreview, !isCancellationPending else { return }
            canFinalize = value
        }
        .onReceive(sensorBio.$isRecordingPaused.receive(on: RunLoop.main)) { value in
            guard !isPreview, !isCancellationPending else { return }
            isPaused = value
        }
        .onReceive(sensorBio.ppg.throttle(for: .milliseconds(40), scheduler: RunLoop.main, latest: true)) { _, rawValue in
            guard !isPreview else { return }
            let value = Double(rawValue)
            guard value.isFinite else { return }
            // Append with timestamp and keep only the most recent 5 seconds of data for a smooth window.
            let now = Date()
            appendPPGSample(value, timestamp: now)
        }
        .onReceive(sensorBio.hr.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestHeartRate = value
            appendBounded(Double(value), to: &heartRateSamples, limit: 80)
        }
        .onReceive(sensorBio.hrv.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestHRV = value
        }
        .onReceive(sensorBio.bbi.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestIBI = value
        }
        .onReceive(sensorBio.rr.receive(on: RunLoop.main)) { _, value in
            guard !isPreview, value > 0 else { return }
            latestRR = value
        }
        .onReceive(sensorBio.spo2.receive(on: RunLoop.main)) { _, rawValue in
            guard !isPreview else { return }
            let value = Double(rawValue)
            guard value.isFinite, value > 0 else { return }
            latestSpO2 = value
        }
        .onReceive(sensorBio.snr.receive(on: RunLoop.main)) { _, rawValue in
            guard !isPreview else { return }
            let value = Double(rawValue)
            guard value.isFinite else { return }
            latestSNR = value
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
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear {
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
                    title: bandConnected ? "Band connected" : "Band needed",
                    color: bandConnected ? NoomTheme.mint : NoomTheme.rose,
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
                Text("Choose a one-minute check or track a longer activity with live Noom Band signals.")
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
            .accessibilityHint("Opens the guided sixty-second biometrics capture")

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
                Text("One quiet minute.")
                    .noomSerifTitle(size: 40)
                Text("Sit comfortably, rest your arm, and keep the Band snug. Your live values appear only when the Band emits them.")
                    .noomBody()
            }

            NoomCard(fill: Color.white.opacity(0.92), padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("60-second spot check")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                            Text("Finish unlocks after 30 seconds and a valid heart-rate sample.")
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
        VStack(alignment: .leading, spacing: 16) {
            NoomCard(fill: NoomTheme.ink, padding: 18) {
                VStack(spacing: 12) {
                    HStack {
                        Label(latestHeartRate == nil ? "Finding your signal" : "Live signal", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(latestHeartRate == nil ? .white.opacity(0.72) : NoomTheme.mint)
                        Spacer()
                        if let latestSNR {
                            Text("Signal \(latestSNR.formatted(.number.precision(.fractionLength(1)))) dB")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.64))
                        }
                    }

                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 15)
                        Circle()
                            .trim(from: 0, to: spotCheckProgress)
                            .stroke(NoomTheme.red, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 3) {
                            Text("\(spotCheckSecondsRemaining)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("SEC")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .frame(width: 146, height: 146)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Spot check, \(spotCheckSecondsRemaining) seconds remaining")

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
                    NoomRecordingSignalWaveform(samples: ppgSamples)
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
                    NoomRecordingMetricTile(label: "Signal", value: latestSNR.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: "dB", systemImage: "antenna.radiowaves.left.and.right", tint: NoomTheme.metricAmber)
                }
            }
        }
    }

    @ViewBuilder
    private var activityExperience: some View {
        if let completion, completion.experience == .activity {
            completionCard(completion)
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
                        Text("LIVE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.68))
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
                        Text("Live samples")
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
                NoomRecordingMetricTile(label: "Signal", value: latestSNR.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: "dB", systemImage: "antenna.radiowaves.left.and.right", tint: NoomTheme.metricAmber, compact: true)
            }

            Text("Live values are provisional. Processed session insights may differ after saving.")
                .font(.footnote)
                .foregroundStyle(NoomTheme.muted)
        }
    }

    @ViewBuilder
    private var unsupportedRestoredRecording: some View {
        if isFinalizing {
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
                    Text("Session saved")
                        .noomSerifTitle(size: 36)
                    Text("Processing continues securely in the background.")
                        .noomBody()
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
                        if isPaused {
                            sensorBio.resumeRecording()
                        } else {
                            sensorBio.pauseRecording()
                        }
                    } label: {
                        Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(NoomSecondaryButtonStyle())
                } else {
                    Button("Cancel") { showsCancelConfirmation = true }
                        .buttonStyle(NoomSecondaryButtonStyle())
                }

                Button {
                    sensorBio.finishCurrentRecording()
                } label: {
                    Label("Finish & save", systemImage: "stop.fill")
                }
                .buttonStyle(NoomPrimaryButtonStyle())
                .disabled(!canFinalize)
            }

            if !canFinalize {
                Text("Finish unlocks after 30 seconds and a valid heart-rate sample.")
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
            .disabled(!bandConnected || recordingTask != nil || isCancellationPending)

            if !bandConnected {
                NavigationLink { NoomBandSetupEntryView() } label: {
                    Label(sensorBio.haveDevice ? "Reconnect Noom Band" : "Set up Noom Band", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(NoomSecondaryButtonStyle())

                Text(sensorBio.haveDevice ? "Your paired Band must reconnect before recording." : "Set up and connect a Noom Band before recording.")
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
        if isStartingRecording { return true }
        guard !isCancellationPending else { return false }
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

    private var bandConnected: Bool { isPreview || sensorBio.connected }

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

    private var spotCheckSecondsRemaining: Int {
        max(0, Int(ceil(noomSpotCheckDuration - spotCheckWallClockElapsed)))
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
        let now = Date()
        spotCheckStartDate = now
        spotCheckNow = now
        beginRecording(.spotCheck)
    }

    private func startActivity() {
        selectedExperience = .activity
        beginRecording(.activity)
    }

    private func beginRecording(_ experience: NoomRecordingExperience) {
        guard !isCancellationPending else { return }
        clearSessionFeedback()
        clearLiveMetrics()
        unsupportedRestoredKind = nil
        isAwaitingRestoredRecording = false
        preservesRestoredActivityName = false
        isStartingRecording = true
        lastElapsed = 0

        let requestID = UUID()
        recordingRequestID = requestID
        recordingTask = Task { @MainActor in
            defer {
                if recordingRequestID == requestID {
                    recordingTask = nil
                    recordingRequestID = nil
                }
            }
            do {
                switch experience {
                case .spotCheck:
                    try await sensorBio.recordDetailedBiometrics(
                        duration: noomSpotCheckDuration,
                        minDuration: noomSpotCheckDuration
                    )
                case .activity:
                    try await sensorBio.recordActivity(activityName: activityName, minDuration: 30)
                }
                guard recordingRequestID == requestID else { return }
                completeRecording(experience)
            } catch is CancellationError {
                if isCancellationPending {
                    isCancellationPending = false
                    recordingState = .idle
                    canFinalize = false
                    isPaused = false
                }
                if recordingRequestID == requestID {
                    isStartingRecording = false
                }
                return
            } catch {
                guard recordingRequestID == requestID else { return }
                isStartingRecording = false
                errorMessage = recordingErrorMessage(error)
            }
        }
    }

    private func cancelRecording() {
        isCancellationPending = true
        isStartingRecording = false
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
        recordingTask = nil
        isAwaitingRestoredRecording = false
        unsupportedRestoredKind = nil
        preservesRestoredActivityName = false
        completion = nil
        errorMessage = nil
        selectedExperience = nil
        lastElapsed = 0
        spotCheckStartDate = nil
        clearLiveMetrics()
    }

    private func completeRecording(_ experience: NoomRecordingExperience) {
        completion = NoomRecordingCompletion(
            experience: experience,
            activityName: experience == .activity ? activityName : nil,
            duration: lastElapsed,
            heartRate: latestHeartRate,
            hrv: latestHRV,
            ibi: latestIBI
        )
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
        let requestID = UUID()
        recordingRequestID = requestID
        isAwaitingRestoredRecording = true
        recordingTask = Task { @MainActor in
            defer {
                if recordingRequestID == requestID {
                    recordingTask = nil
                    recordingRequestID = nil
                    isAwaitingRestoredRecording = false
                }
            }
            do {
                try await sensorBio.awaitActiveRecordingCompletion()
                guard recordingRequestID == requestID else { return }
                if let experience {
                    completeRecording(experience)
                } else {
                    unsupportedRestoredKind = nil
                }
            } catch is CancellationError {
                if isCancellationPending {
                    isCancellationPending = false
                    recordingState = .idle
                    canFinalize = false
                    isPaused = false
                }
                return
            } catch {
                guard recordingRequestID == requestID else { return }
                unsupportedRestoredKind = nil
                errorMessage = recordingErrorMessage(error)
            }
        }
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
        samples.append(NoomRecordingSample(index: (samples.last?.index ?? -1) + 1, value: value, timestamp: Date()))
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    /// Appends a PPG sample with a timestamp and retains only the most recent five seconds.
    /// A high hard limit protects memory if timestamps arrive out of order.
    private func appendPPGSample(_ value: Double, timestamp: Date) {
        guard value.isFinite else { return }
        ppgSamples.append(
            NoomRecordingSample(
                index: (ppgSamples.last?.index ?? -1) + 1,
                value: value,
                timestamp: timestamp
            )
        )
        let cutoff = timestamp.addingTimeInterval(-5)
        ppgSamples.removeAll { $0.timestamp < cutoff }
        if ppgSamples.count > 1_000 {
            ppgSamples.removeFirst(ppgSamples.count - 1_000)
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
        latestSNR = nil
        ppgSamples = []
        heartRateSamples = []
    }

    #if DEBUG
    private func applyPreviewIfNeeded() {
        guard let preview else { return }
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
            latestSNR = 18.6
            ppgSamples = (0..<140).map { index in
                let x = Double(index)
                let pulse = sin(x * 0.31) + 0.24 * sin(x * 0.91) + 0.08 * sin(x * 2.1)
                return NoomRecordingSample(index: index, value: pulse, timestamp: Date().addingTimeInterval(Double(index - 139) / 28))
            }
        case .activity:
            selectedExperience = .activity
            activityName = "Walk"
            recordingState = .recording(elapsed: 742, target: nil)
            lastElapsed = 742
            canFinalize = true
            latestHeartRate = 118
            latestHRV = 31
            latestIBI = 508
            latestSNR = 14.2
            heartRateSamples = (0..<56).map { index in
                let value = 105 + Double(index) * 0.22 + sin(Double(index) * 0.38) * 7
                return NoomRecordingSample(index: index, value: value, timestamp: Date().addingTimeInterval(Double(index - 55) * 5))
            }
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

    var body: some View {
        let finiteSamples = samples.filter { $0.value.isFinite }
        Canvas { context, size in
            guard finiteSamples.count > 1 else {
                var idle = Path()
                idle.move(to: CGPoint(x: 0, y: size.height / 2))
                idle.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(idle, with: .color(NoomTheme.softLine), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
                return
            }
            let sortedValues = finiteSamples.map(\.value).sorted()
            let lowerIndex = Int(Double(sortedValues.count - 1) * 0.05)
            let upperIndex = Int(Double(sortedValues.count - 1) * 0.95)
            let low = sortedValues[lowerIndex]
            let high = sortedValues[upperIndex]
            let range = max(high - low, 0.000_001)
            guard let latestTimestamp = finiteSamples.last?.timestamp else { return }
            let windowStart = latestTimestamp.addingTimeInterval(-noomPPGWindowDuration)
            var path = Path()
            for (offset, sample) in finiteSamples.enumerated() {
                let elapsed = sample.timestamp.timeIntervalSince(windowStart)
                let x = size.width * CGFloat(min(max(elapsed / noomPPGWindowDuration, 0), 1))
                let normalized = min(max((sample.value - low) / range, 0), 1)
                let y = size.height - CGFloat(normalized) * size.height * 0.76 - size.height * 0.12
                let point = CGPoint(x: x, y: y)
                if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .linearGradient(Gradient(colors: [NoomTheme.red.opacity(0.55), NoomTheme.red]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finiteSamples.isEmpty ? "Live PPG waveform, waiting for signal" : "Live PPG waveform, \(finiteSamples.count) recent samples")
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
