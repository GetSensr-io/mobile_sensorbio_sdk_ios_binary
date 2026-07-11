import SwiftUI
import Observation
import SensorBioSDK

struct NoomBandSetupEntryView: View {
    @State private var presentingPair = false
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var pairedDevice: SB_PairedDeviceState? = sensorBio.pairedDevice
    @State private var isReconnecting = false
    @State private var reconnectError: String? = nil

    private var bandState: NoomBandConnectionState {
        isReconnecting ? .connecting : .live(paired: haveDevice, connected: connected)
    }

    var body: some View {
        NoomScreen(spacing: 10, bottomPadding: 132) {
            NoomTopBar(label: "Setup") {
                NoomPill(title: bandState.title, color: bandState.isLiveReady ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect your Noom Band").noomSerifTitle(size: 34)
                Text("Noom uses your band to personalize daily guidance with sleep, Recovery, and movement signals.").noomBody()
            }

            NoomBandIllustration()

            VStack(spacing: 8) {
                NoomSetupStep(number: "1", title: "Keep it nearby", detail: "Place your Noom Band near your phone and make sure it has charge.")
                NoomSetupStep(number: "2", title: "Confirm the blink", detail: "When the band blinks, press the button to confirm it is yours.")
                NoomSetupStep(number: "3", title: "Let it sync", detail: "Your first Body State appears after Noom Band finishes the first sync.")
            }
            .fixedSize(horizontal: false, vertical: true)

            Button {
                handlePrimaryAction()
            } label: {
                if isReconnecting {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text(bandState.callToAction)
                }
            }
            .buttonStyle(NoomPrimaryButtonStyle())
            .disabled(connected || isReconnecting)

            if let reconnectError {
                Label(reconnectError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(NoomTheme.ink)
            }
        }
        .navigationTitle("Noom Band setup")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$pairedDevice) { pairedDevice = $0 }
        .sheet(isPresented: $presentingPair) { PairDeviceView() }
    }

    private func handlePrimaryAction() {
        reconnectError = nil
        if haveDevice {
            reconnectPairedDevice()
        } else {
            presentingPair = true
        }
    }

    private func reconnectPairedDevice() {
        guard let device = pairedDevice else {
            reconnectError = "No paired Noom Band found. Set up your band again."
            presentingPair = true
            return
        }
        isReconnecting = true
        sensorBio.connect(device.macAddress, pairing: false)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            isReconnecting = false
            if !sensorBio.connected {
                reconnectError = "Noom Band is still not connected. Keep it nearby and try again."
            }
        }
    }
}

struct NoomSleepRecoveryView: View {
    var body: some View {
        NoomScreen(spacing: 8, bottomPadding: 112) {
            NoomTopBar(label: "Recovery") {
                NoomPill(title: "SDK-backed", color: NoomTheme.ink)
            }

            NoomCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep & Recovery details").noomSerifTitle(size: 30)
                    Text("Open the SDK-backed detail screens below. Values appear only after Noom Band has synced real data.").noomBody()
                }
            }

            HStack(spacing: 8) {
                NavigationLink {
                    SleepDetailView()
                } label: {
                    NoomMetricTile(label: "Sleep", value: "Open", caption: "Details", minHeight: 72)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RecoveryDetailView()
                } label: {
                    NoomMetricTile(label: "Recovery", value: "Open", caption: "Details", minHeight: 72)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Sleep & Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@Observable
final class NoomProgressState {
    var recoveryRange: SB_RecoveryRangeTrending? = nil
    var sleepRange: SB_SleepDetailAggregated? = nil
    var isLoading = false
    var errorMessage: String? = nil

    private var activeRequestID: UUID?

    @MainActor
    func load(date: Date) async {
        let requestID = UUID()
        activeRequestID = requestID
        let requestUserID = sensorBio.session?.userId
        isLoading = true
        defer {
            if activeRequestID == requestID { isLoading = false }
        }

        var nextRecovery: SB_RecoveryRangeTrending?
        var nextSleep: SB_SleepDetailAggregated?
        var nextError: String?

        do {
            nextRecovery = try await sensorBio.fetchRangeRecovery(date: date, granularity: .week)
        } catch is CancellationError {
            return
        } catch {
            nextError = error.localizedDescription
        }

        do {
            nextSleep = try await sensorBio.fetchSleepAggregation(date: date, granularity: .week)
        } catch is CancellationError {
            return
        } catch {
            if nextError == nil { nextError = error.localizedDescription }
        }

        guard activeRequestID == requestID, !Task.isCancelled else { return }
        recoveryRange = nextRecovery
        sleepRange = nextSleep
        errorMessage = nextError
        if nextSleep?.sleepTimePoints.isEmpty == false { NoomSleepHistory.recordSleep(for: requestUserID) }
    }
}

struct NoomProgressSignalsView: View {
    @Environment(AppDateContext.self) private var dateContext
    @State private var state = NoomProgressState()

    private var recoveryPoints: [SB_DateValuePoint] {
        state.recoveryRange?.graph?.recoveryScoreSection?.scorePoints.sorted { $0.date < $1.date } ?? []
    }

    private var sleepPoints: [SB_DateValuePoint] {
        state.sleepRange?.sleepTimePoints.sorted { $0.date < $1.date } ?? []
    }

    var body: some View {
        @Bindable var ctx = dateContext
        NoomScreen(spacing: 12, bottomPadding: 112) {
            NoomTopBar(label: "Progress") {
                NoomPill(title: "Real data", color: NoomTheme.ink)
            }

            NoomDayNavigator(selection: $ctx.selectedDate)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep & Recovery progress").noomSerifTitle(size: 34)
                Text("Noom shows returned SDK history only. Missing dates are left blank; the app does not create a composite score or causal explanation.").noomBody()
            }

            if state.isLoading && recoveryPoints.isEmpty && sleepPoints.isEmpty {
                loadingCard
            } else if recoveryPoints.isEmpty && sleepPoints.isEmpty {
                NoomEmptyStateCard(
                    title: "No progress history yet",
                    message: state.errorMessage == nil ? "Wear Noom Band and sync across multiple nights to see Recovery and sleep history." : "Recovery and sleep history did not load. No sample values are shown.",
                    systemImage: "chart.xyaxis.line"
                )
            } else {
                coverageCard
                if !recoveryPoints.isEmpty { recoveryHistoryCard }
                if !sleepPoints.isEmpty { sleepHistoryCard }
                if recoveryPoints.isEmpty || sleepPoints.isEmpty {
                    NoomStateBanner(title: "Partial history", detail: "One history source is missing for this range. The other source remains visible as returned.", systemImage: "chart.bar.doc.horizontal", tint: NoomTheme.mint)
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dateContext.selectedDate) { await state.load(date: dateContext.selectedDate) }
        .refreshable { await state.load(date: dateContext.selectedDate) }
    }

    private var loadingCard: some View {
        NoomLoadingExperience(
            title: "Connecting the dots",
            detail: "Gathering your real history while keeping missing days honest.",
            systemImage: "chart.xyaxis.line",
            accent: NoomTheme.metricGreen
        )
    }

    private var coverageCard: some View {
        NoomCard(fill: Color.white.opacity(0.84), padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Coverage").font(.system(size: 18, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: coverageTitle, color: coverageCount >= 5 ? NoomTheme.mint : NoomTheme.rose, foreground: NoomTheme.logoBlack)
                }
                Text("Coverage is counted from dates actually returned by the SDK in this weekly range. Threshold for a fuller read is 5 of 7 days.").noomBody()
                VStack(spacing: 0) {
                    NoomDetailValueRow(label: "Recovery dates", value: "\(recoveryPoints.count)/7", verticalPadding: 8)
                    NoomDetailValueRow(label: "Sleep dates", value: "\(sleepPoints.count)/7", verticalPadding: 8)
                    NoomDetailValueRow(label: "Source", value: "SDK Recovery + Sleep", verticalPadding: 8)
                }
            }
        }
    }

    private var recoveryHistoryCard: some View {
        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recovery history").font(.system(size: 18, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: "Discontinuous", color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }
                NoomDiscontinuousPointTrend(points: recoveryPoints, valueFormatter: { "\(Int($0))" }, tint: NoomTheme.red)
            }
        }
    }

    private var sleepHistoryCard: some View {
        NoomCard(fill: Color.white.opacity(0.84), padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sleep history").font(.system(size: 18, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    NoomPill(title: "Returned dates", color: NoomTheme.mint, foreground: NoomTheme.logoBlack)
                }
                VStack(spacing: 0) {
                    ForEach(sleepPoints.prefix(7), id: \.date) { point in
                        NoomDetailValueRow(label: MetricFormatting.rangeDateLabel(packedDate: point.date, granularity: .week), value: duration(seconds: Int(point.value)), verticalPadding: 8)
                    }
                }
            }
        }
    }

    private var coverageCount: Int { max(recoveryPoints.count, sleepPoints.count) }

    private var coverageTitle: String {
        switch coverageCount {
        case 5...: return "Enough \(coverageCount)/7"
        case 1...: return "Partial \(coverageCount)/7"
        default: return "No coverage"
        }
    }

    private func duration(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }
}

private struct NoomSetupStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(NoomTheme.ink, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                Text(detail)
                    .noomBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1)
        }
    }
}
