import SwiftUI
import SensorBioSDK

/// Renders `sensorBio.pairingState` and makes the three pairing calls. The
/// switch below is the whole flow — one case per state the SDK publishes.
struct PairDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = PairDeviceState()

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if case .scanning(let devices) = state.pairingState {
                    deviceListSection(devices)
                }
                if case .paired(let device) = state.pairingState {
                    Section("Paired") {
                        LabeledContent("Device", value: device.name)
                        LabeledContent("Type", value: device.type.name)
                    }
                }
            }
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        state.close()
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

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch state.pairingState {
            case .scanning:
                HStack {
                    ProgressView()
                    Text("Scanning\u{2026}")
                        .foregroundStyle(.secondary)
                }
            case .connecting(let device):
                HStack {
                    ProgressView()
                    Text("Connecting to \(device.name)\u{2026}")
                        .foregroundStyle(.secondary)
                }
            case .awaitingConfirmation:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Press the button on your device to confirm.",
                          systemImage: "hand.tap.fill")
                        .foregroundStyle(.blue)
                    Text("The light should blink blue.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            case .paired:
                Label("All set! Tap Done to finish.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let reason):
                Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case nil:
                Text("Idle")
            }
        }
    }

    @ViewBuilder
    private func deviceListSection(_ devices: [SB_DiscoveredDevice]) -> some View {
        Section("Devices Found (\(devices.count))") {
            if devices.isEmpty {
                Text("Looking for nearby devices\u{2026}")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices, id: \.id) { device in
                    Button {
                        state.select(device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name).foregroundStyle(.primary)
                                Text(device.deviceType.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        switch state.pairingState {
        case .paired:
            // `endPairing()` — same call as Cancel. The pair is already
            // persisted and registered by the time `.paired` is published;
            // Done just closes the transaction.
            Button("Done") {
                state.close()
                dismiss()
            }
            .bold()
        case .failed:
            Button("Retry") {
                state.start()
            }
        default:
            EmptyView()
        }
    }
}

#Preview {
    PairDeviceView()
}
