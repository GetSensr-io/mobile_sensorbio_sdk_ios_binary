import SwiftUI
import SensorBioSDK

struct PairDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = PairDeviceState()

    var body: some View {
        NavigationStack {
            NoomScreen(bottomPadding: 24) {
                NoomTopBar(label: "Setup") {
                    NoomPill(title: phasePill, color: phaseColor, foreground: phaseForeground)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your Noom Band").noomSerifTitle(size: 38)
                    Text("Keep your band near your phone. The first sync helps Noom personalize sleep, recovery, and movement guidance.").noomBody()
                }

                NoomBandIllustration()
                statusCard

                if state.phase == .scanning || state.phase == .scanTimeout {
                    nearbyBandSection
                }

                if state.phase == .allSet {
                    pairedCard
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomCTA
            }
            .navigationTitle("Noom Band setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        state.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailingButton
                }
            }
            .task { state.start() }
        }
    }

    private var statusCard: some View {
        NoomCard(fill: statusFill) {
            VStack(alignment: .leading, spacing: 10) {
                switch state.phase {
                case .idle:
                    Text("Ready to find your Noom Band").noomSerifTitle(size: 24)
                    Text("We will look for your band nearby.").noomBody()
                case .scanning:
                    HStack(spacing: 12) {
                        ProgressView().tint(NoomTheme.red)
                        Text("Looking for your Noom Band").noomBody()
                    }
                case .scanTimeout:
                    Label("No Noom Band found. Bring it closer and try again.", systemImage: "wifi.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoomTheme.ink)
                case .connecting:
                    HStack(spacing: 12) {
                        ProgressView().tint(NoomTheme.red)
                        Text("Connecting to your Noom Band").noomBody()
                    }
                case .confirming:
                    Label("Press the button on your Noom Band to confirm it is yours.", systemImage: "hand.tap.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoomTheme.ink)
                    Text("The light should blink blue. You have 30 seconds.").noomBody()
                case .allSet:
                    Label("Noom Band is connected. Tap Done to finish.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoomTheme.ink)
                case .error(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoomTheme.ink)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private var nearbyBandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nearby Noom Bands").noomLabel()
            if state.devices.isEmpty {
                NoomCard {
                    Text("Looking nearby").noomBody()
                }
            } else {
                ForEach(state.devices, id: \.id) { device in
                    Button {
                        state.connect(device)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .foregroundStyle(NoomTheme.red)
                                .frame(width: 34, height: 34)
                                .background(NoomTheme.rose, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Noom Band")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(NoomTheme.logoBlack)
                                Text("Ready to connect")
                                    .font(.system(size: 12))
                                    .foregroundStyle(NoomTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(NoomTheme.muted)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pairedCard: some View {
        NoomCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paired").noomLabel()
                NoomValueRowPublic(label: "Device", value: "Noom Band")
                NoomValueRowPublic(label: "Status", value: "Ready")
            }
        }
    }

    private var bottomCTA: some View {
        Button {
            if state.phase == .allSet {
                state.finish()
                dismiss()
            } else {
                state.start()
            }
        } label: {
            Text(state.phase == .allSet ? "Done" : "Find my Noom Band")
        }
        .buttonStyle(NoomPrimaryButtonStyle())
        .padding(.horizontal, NoomTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var trailingButton: some View {
        switch state.phase {
        case .allSet:
            Button("Done") {
                state.finish()
                dismiss()
            }
            .bold()
        case .scanTimeout, .error:
            Button("Retry") { state.start() }
        default:
            EmptyView()
        }
    }

    private var phasePill: String {
        switch state.phase {
        case .allSet: return "Connected"
        case .scanning, .connecting, .confirming: return "In progress"
        default: return "Noom Band"
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case .allSet: return NoomTheme.mint
        case .scanTimeout, .error: return NoomTheme.rose
        default: return NoomTheme.red
        }
    }

    private var phaseForeground: Color {
        switch state.phase {
        case .allSet, .scanTimeout, .error: return NoomTheme.logoBlack
        default: return .white
        }
    }

    private var statusFill: Color {
        switch state.phase {
        case .scanTimeout, .error: return NoomTheme.rose
        default: return NoomTheme.card
        }
    }
}

struct NoomValueRowPublic: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(NoomTheme.muted)
            Spacer()
            Text(value).bold().foregroundStyle(NoomTheme.logoBlack)
        }
        .font(.system(size: 14))
        .padding(.vertical, 8)
    }
}

#Preview {
    PairDeviceView()
}
