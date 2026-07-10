import SwiftUI
import SensorBioSDK

struct MainTabView: View {
    let session: SB_Session

    var body: some View {
        TabView {
            NavigationStack { DashboardView(session: session) }
                .tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }

            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "sparkles") }

            NavigationStack { NoomProgressSignalsView() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            NavigationStack { SleepHomeView() }
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
        }
        .tint(NoomTheme.red)
    }
}

struct SleepHomeView: View {
    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Sleep") { NoomPill(title: "Details", color: NoomTheme.ink) }
            Text("Sleep and Recovery").noomSerifTitle(size: 38)
            Text("View available data from your latest Noom Band sync.").noomBody()
            NavigationLink { SleepDetailView() } label: {
                destinationCard(title: "Sleep details", detail: "Overnight sleep, stages, and biometrics", icon: "moon.zzz.fill")
            }
            NavigationLink { RecoveryDetailView() } label: {
                destinationCard(title: "Recovery details", detail: "Recovery trends and returned score factors", icon: "heart.text.square.fill")
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func destinationCard(title: String, detail: String, icon: String) -> some View {
        NoomCard {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(NoomTheme.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                    Text(detail).noomBody()
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(NoomTheme.muted)
            }
        }
    }
}

/// Compact band status shown beside the dashboard profile control.
struct BandBatteryBadge: View {
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var battery: Int? = sensorBio.batteryLevel
    @State private var charging: Bool? = sensorBio.charging

    var body: some View {
        Group {
            if haveDevice {
                HStack(spacing: 5) {
                    Image(systemName: batteryIcon())
                    if connected {
                        Text(battery.map { "\($0)%" } ?? "Live")
                        if charging == true {
                            Image(systemName: "bolt.fill")
                        }
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        Text("Offline")
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(connected ? NoomTheme.logoBlack : NoomTheme.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    connected ? NoomTheme.red.opacity(0.12) : NoomTheme.softLine.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityStatus)
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$batteryLevel) { battery = $0 }
        .onReceive(sensorBio.$charging) { charging = $0 }
    }

    private var accessibilityStatus: String {
        guard connected else { return "Noom Band not connected" }
        if let battery { return "Noom Band battery \(battery) percent" }
        return "Noom Band connected"
    }

    private func batteryIcon() -> String {
        guard let battery else { return "battery.0percent" }
        switch battery {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// A deliberate entry point for the SDK-owned live recording flows.
/// Spot check is a fixed, guided biometrics capture; activity is open-ended.
struct RecordActivityView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case spotCheck = "Spot check"
        case activity = "Activity"
        var id: Self { self }
    }

    @State private var mode: Mode = .spotCheck
    @State private var activityName = "Walk"
    @State private var recordingState: SB_RecordingState = sensorBio.recordingState
    @State private var canFinalize = sensorBio.canFinalize
    @State private var isPaused = sensorBio.isRecordingPaused
    @State private var completionMessage: String?
    @State private var recordingTask: Task<Void, Never>?

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Record") {
                NoomPill(title: sensorBio.connected ? "Band connected" : (sensorBio.haveDevice ? "Band disconnected" : "Band needed"), color: sensorBio.connected ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
            }
            Text(isActive ? "Recording" : "Record a session")
                .noomSerifTitle(size: 38)
            Text(isActive ? recordingDetail : "Choose a guided spot check or an open-ended activity. The band handles capture, sync, and submission.")
                .noomBody()

            if isActive {
                activeRecordingCard
            } else {
                Picker("Recording type", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .activity {
                    Picker("Activity", selection: $activityName) {
                        ForEach(["Walk", "Run", "Cycle", "Strength", "Other"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                NoomCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode == .spotCheck ? "One-minute body check" : "Live activity")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(mode == .spotCheck ? "Stay still while the band captures a short biometrics sample." : "Start when you begin. Pause or finish when you are done.")
                            .noomBody()
                        Text(mode == .spotCheck ? "Requires at least 30 seconds and valid signal." : "Runs until you choose Finish.")
                            .font(.footnote)
                            .foregroundStyle(NoomTheme.muted)
                    }
                }

                Button(action: startRecording) {
                    Label(mode == .spotCheck ? "Start spot check" : "Start activity", systemImage: mode == .spotCheck ? "waveform.path.ecg" : "figure.run")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NoomTheme.red)
                .disabled(!sensorBio.connected || recordingTask != nil)

                if !sensorBio.connected {
                    NavigationLink { NoomBandSetupEntryView() } label: {
                        Label(sensorBio.haveDevice ? "Reconnect Noom Band" : "Set up Noom Band", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Text(sensorBio.haveDevice ? "Your paired band is disconnected. Reconnect it before starting a recording." : "Set up and connect a Noom Band before starting a recording.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let completionMessage {
                NoomCard {
                    Label(completionMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NoomTheme.logoBlack)
                }
            }
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(sensorBio.$recordingState) { recordingState = $0 }
        .onReceive(sensorBio.$canFinalize) { canFinalize = $0 }
        .onReceive(sensorBio.$isRecordingPaused) { isPaused = $0 }
        .onAppear { resumePersistedRecordingIfNeeded() }
        .onDisappear { recordingTask?.cancel() }
    }

    @ViewBuilder
    private var activeRecordingCard: some View {
        NoomCard {
            VStack(spacing: 16) {
                Text(timerText)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(isPaused ? "Paused" : recordingDetail)
                    .noomBody()
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    if mode == .activity, !isFinalizing {
                        Button(isPaused ? "Resume" : "Pause") {
                            if isPaused { sensorBio.resumeRecording() } else { sensorBio.pauseRecording() }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Finish") { sensorBio.finishCurrentRecording() }
                        .buttonStyle(.borderedProminent)
                        .tint(NoomTheme.red)
                        .disabled(!canFinalize || isFinalizing)
                }
                if !canFinalize && !isFinalizing {
                    Text("Finish becomes available after the minimum duration and a valid heart-rate sample.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var isActive: Bool {
        if case .idle = recordingState { return false }
        return true
    }

    private var isFinalizing: Bool {
        if case .finalizing = recordingState { return true }
        return false
    }

    private var elapsed: TimeInterval {
        if case let .recording(value, _) = recordingState { return value }
        return 0
    }

    private var timerText: String {
        let seconds = Int(elapsed.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var recordingDetail: String {
        switch recordingState {
        case let .recording(_, target):
            return target == nil ? "Activity is recording" : "Spot check is recording"
        case let .finalizing(phase):
            return "Finishing: \(phase.rawValue)"
        case .idle:
            return ""
        @unknown default:
            return "Recording status unavailable"
        }
    }

    private func startRecording() {
        completionMessage = nil
        recordingTask = Task {
            do {
                switch mode {
                case .spotCheck:
                    try await sensorBio.recordDetailedBiometrics(duration: 60, minDuration: 30)
                case .activity:
                    try await sensorBio.recordActivity(activityName: activityName, minDuration: 30)
                }
                completionMessage = "Recording saved and queued for sync."
            } catch is CancellationError {
                return
            } catch {
                completionMessage = error.localizedDescription
            }
            recordingTask = nil
        }
    }

    private func resumePersistedRecordingIfNeeded() {
        guard sensorBio.activeRecording != nil, recordingTask == nil else { return }
        recordingTask = Task {
            do {
                try await sensorBio.awaitActiveRecordingCompletion()
                completionMessage = "Recording saved and queued for sync."
            } catch is CancellationError {
                return
            } catch {
                completionMessage = error.localizedDescription
            }
            recordingTask = nil
        }
    }
}
