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
    @State private var presentingToken: Bool = false
    // The token this launch minted, if the session came from a register rather
    // than from a keychain hydrate. In-memory only — see `SDKTokenRecord`.
    @State private var tokenRecord = SDKTokenRecord.shared

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Username", value: session.username)
            }

            Section {
                if let token = tokenRecord.token {
                    Button {
                        presentingToken = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("sdk_token")
                                    .foregroundStyle(.primary)
                                Text(token.sdkToken)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Label("Session restored — no register this launch",
                          systemImage: "key.slash")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Registered With")
            } footer: {
                Text(tokenRecord.token == nil
                     ? "A relaunch does not re-register: the SDK restored the access/refresh pair from the keychain, so no token was minted and none was needed. A token is a bootstrap credential, spent by the one register that used it. Sign out and register to see a fresh one."
                     : "The single-use token the register call presented, exchanged from your SDK Key. Tap to see the whole thing.")
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
        .sheet(isPresented: $presentingToken) {
            SDKTokenSheet(record: tokenRecord)
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

    /// `removeDeviceFromPairedDevices(_:)` clears the paired device on an
    /// explicit unpair — it drops the BLE-SDK paired list and wipes the
    /// SDK-owned paired snapshot so `pairedDevice` / `haveDevice` flip off.
    private func unpair() {
        unpairError = nil
        guard let device = pairedDevice else {
            unpairError = "No paired device to remove."
            return
        }
        sensorBio.removeDeviceFromPairedDevices(device.macAddress)
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
        }
        do {
            try await sensorBio.signOut()
        } catch {
            signOutError = error.localizedDescription
        }
    }
}
