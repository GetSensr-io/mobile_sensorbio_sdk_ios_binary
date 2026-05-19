import SwiftUI
import SensorBioSDK

struct ProfileView: View {
    let session: SB_Session

    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var pairedDevice: SB_PairedDeviceState? = sensorBio.pairedDevice
    @State private var lastSyncd: Date = sensorBio.lastSyncd
    @State private var syncing: Bool = sensorBio.deviceSyncing
    @State private var percentSynced: Int = sensorBio.percentSynced
    @State private var isSigningOut: Bool = false
    @State private var signOutError: String? = nil
    @State private var presentingPair: Bool = false
    @State private var unpairError: String? = nil
    @State private var now: Date = Date()

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Username", value: session.username)
                LabeledContent("Email", value: session.email)
            }

            if haveDevice, let device = pairedDevice {
                Section("Paired Device") {
                    LabeledContent("Name", value: device.name)
                    LabeledContent("Type", value: device.type.name)
                    LabeledContent("Last Synced", value: formattedLastSynced(now: now))
                    if syncing {
                        LabeledContent("Syncing", value: "\(percentSynced)%")
                    }
                }
            }

            Section {
                if !haveDevice {
                    Button {
                        presentingPair = true
                    } label: {
                        Label("Pair Device", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } else {
                    Button(role: .destructive) {
                        unpair()
                    } label: {
                        Label("Unpair Device", systemImage: "antenna.radiowaves.left.and.right.slash")
                    }
                    if let unpairError {
                        Label(unpairError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack {
                        if isSigningOut {
                            ProgressView()
                        } else {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
                .disabled(isSigningOut)
                if let signOutError {
                    Label(signOutError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Profile")
        .onAppear { now = Date() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { now = Date() }
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
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

    /// Two-step unpair surfaced as a Phase 6.14d.1 leak: the SDK
    /// requires both `removeDeviceFromPairedDevices(_:)` (drops the
    /// BLE-SDK paired list) AND `persistDeviceState([:])` (clears the
    /// app-side device dict so `pairedDevice` / `haveDevice` flip).
    /// A single `sensorBio.unpair()` API is slated as a follow-up.
    private func unpair() {
        unpairError = nil
        guard let device = pairedDevice else {
            unpairError = "No paired device to remove."
            return
        }
        sensorBio.removeDeviceFromPairedDevices(device.macAddress)
        sensorBio.persistDeviceState([:])
    }

    private func signOut() async {
        isSigningOut = true
        signOutError = nil
        defer { isSigningOut = false }
        // The SDK's signOut() clears the auth session but leaves the
        // paired device in place (it emits `signOutComplete` and expects
        // host apps to clean up themselves). Unpair first so the next
        // user signing in doesn't inherit the previous user's device.
        // Phase 6.14d.1 — slated as a follow-up SDK lift to make signOut
        // optionally unpair via a parameter.
        if let device = pairedDevice {
            sensorBio.removeDeviceFromPairedDevices(device.macAddress)
            sensorBio.persistDeviceState([:])
        }
        do {
            try await sensorBio.signOut()
        } catch {
            signOutError = error.localizedDescription
        }
    }
}
