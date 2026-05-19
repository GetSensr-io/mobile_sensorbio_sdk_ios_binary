import SwiftUI
import SensorBioSDK

struct PairDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = PairDeviceState()

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if state.phase == .scanning || state.phase == .scanTimeout {
                    deviceListSection
                }
                if state.phase == .allSet, let device = state.selectedDevice {
                    Section("Paired") {
                        LabeledContent("Device", value: device.name)
                        LabeledContent("Type", value: device.deviceType.name)
                    }
                }
            }
            .navigationTitle("Pair Device")
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

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch state.phase {
            case .idle:
                Text("Idle")
            case .scanning:
                HStack {
                    ProgressView()
                    Text("Scanning\u{2026}")
                        .foregroundStyle(.secondary)
                }
            case .scanTimeout:
                Label("No device found. Tap Retry to scan again.", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            case .connecting:
                HStack {
                    ProgressView()
                    Text("Connecting to \(state.selectedDevice?.name ?? "device")\u{2026}")
                        .foregroundStyle(.secondary)
                }
            case .confirming:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Press the button on your device to confirm.",
                          systemImage: "hand.tap.fill")
                        .foregroundStyle(.blue)
                    Text("The light should blink blue. You have 30s.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            case .allSet:
                Label("All set! Tap Done to finish.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                @unknown default:
                    EmptyView()
            }
        }
    }

    @ViewBuilder
    private var deviceListSection: some View {
        Section("Devices Found (\(state.devices.count))") {
            if state.devices.isEmpty {
                Text("Looking for nearby devices\u{2026}")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.devices, id: \.id) { device in
                    Button {
                        state.connect(device)
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
        switch state.phase {
        case .allSet:
            Button("Done") {
                state.finish()
                dismiss()
            }
            .bold()
        case .scanTimeout, .error:
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
