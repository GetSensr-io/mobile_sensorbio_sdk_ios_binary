import SwiftUI
import SensorBioSDK

struct ProfileView: View {
    let session: SB_Session

    @Environment(\.dismiss) private var dismiss
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var pairedDevice: SB_PairedDeviceState? = sensorBio.pairedDevice
    @State private var lastSyncd: Date = sensorBio.lastSyncd
    @State private var syncing: Bool = sensorBio.deviceSyncing
    @State private var percentSynced: Int = sensorBio.percentSynced
    @State private var isSigningOut: Bool = false
    @State private var signOutError: String? = nil
    @State private var presentingPair: Bool = false
    @State private var unpairError: String? = nil
    @State private var now: Date = Date()

    private var bandState: NoomBandConnectionState {
        .live(paired: haveDevice, connected: connected)
    }

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Plan") {
                NoomPill(title: "Account", color: NoomTheme.ink)
            }

            NoomCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Noom plan").noomSerifTitle(size: 30)
                    NoomValueRowPublic(label: "Username", value: session.username)
                    NoomValueRowPublic(label: "Email", value: session.email)
                }
            }

            if haveDevice {
                NoomCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noom Band").noomSerifTitle(size: 28)
                        NoomValueRowPublic(label: "Device", value: "Noom Band")
                        NoomValueRowPublic(label: "Connection", value: bandState.isLiveReady ? "Connected" : "Not connected")
                        NoomValueRowPublic(label: "Last synced", value: formattedLastSynced(now: now))
                        if syncing {
                            NoomValueRowPublic(label: "Syncing", value: "\(percentSynced)%")
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                if !haveDevice {
                    Button("Set up Noom Band") { presentingPair = true }
                        .buttonStyle(NoomPrimaryButtonStyle())
                } else {
                    Button("Remove Noom Band") { unpair() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NoomTheme.logoBlack)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white, in: Capsule())
                        .overlay { Capsule().stroke(NoomTheme.ink.opacity(0.10), lineWidth: 1) }
                    if let unpairError {
                        Label(unpairError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(NoomTheme.ink)
                    }
                }
                Button {
                    Task { await signOut() }
                } label: {
                    HStack {
                        if isSigningOut { ProgressView() } else { Text("Sign out") }
                    }
                }
                .buttonStyle(NoomPrimaryButtonStyle())
                .disabled(isSigningOut)
                if let signOutError {
                    Label(signOutError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NoomTheme.ink)
                }
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { now = Date() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { now = Date() }
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$pairedDevice) { pairedDevice = $0 }
        .onReceive(sensorBio.$lastSyncd) { lastSyncd = $0 }
        .onReceive(sensorBio.$deviceSyncing) { syncing = $0 }
        .onReceive(sensorBio.$percentSynced) { percentSynced = $0 }
        .sheet(isPresented: $presentingPair) {
            PairDeviceView()
        }
    }

    private func formattedLastSynced(now: Date) -> String {
        if lastSyncd.timeIntervalSinceReferenceDate <= 0 {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSyncd, relativeTo: now)
    }

    private func unpair() {
        unpairError = nil
        guard let device = pairedDevice else {
            unpairError = "No Noom Band to remove."
            return
        }
        sensorBio.removeDeviceFromPairedDevices(device.macAddress)
        sensorBio.clearPairedDevice()
    }

    private func signOut() async {
        isSigningOut = true
        signOutError = nil
        defer { isSigningOut = false }
        do {
            try await sensorBio.signOut()
            dismiss()
            sensorBio.session = nil
        } catch {
            signOutError = error.localizedDescription
        }
    }
}
