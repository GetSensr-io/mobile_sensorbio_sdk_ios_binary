import SwiftUI
import Combine
import SensorBioSDK
import UserNotifications

struct ProfileView: View {
    let session: SB_Session

    @Environment(\.dismiss) private var dismiss
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var pairedDevice: SB_PairedDeviceState? = sensorBio.pairedDevice
    @State private var deviceIdentity = DeviceIdentityPresentation(
        deviceID: sensorBio.pairedDevice?.macAddress,
        serialNumber: sensorBio.connected ? sensorBio.serialNumber : nil
    )
    @State private var lastSyncd: Date = sensorBio.lastSyncd
    @State private var syncing: Bool = sensorBio.deviceSyncing
    @State private var percentSynced: Int = sensorBio.percentSynced
    @State private var isSigningOut: Bool = false
    @State private var signOutError: String? = nil
    @State private var presentingPair: Bool = false
    @State private var unpairError: String? = nil
    @State private var now: Date = Date()
    @AppStorage("productLoopDailyCheckInEnabled") private var dailyCheckInEnabled = false
    @AppStorage("productLoopExperimentReminderEnabled") private var experimentReminderEnabled = false
    @State private var notificationStatus = "Not enabled"
    @State private var notificationError: String? = nil

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

            NoomCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Experiment reminders").noomSerifTitle(size: 26)
                    Text("Choose whether Noom may ask you to check in on an active experiment. You can change this any time.").noomBody()
                    Toggle("Daily check-in", isOn: $dailyCheckInEnabled)
                    Toggle("Experiment reminders", isOn: $experimentReminderEnabled)
                    NoomDetailValueRow(label: "Notifications", value: notificationStatus, verticalPadding: 6)
                    if let notificationError {
                        Label(notificationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NoomTheme.ink)
                    }
                }
            }

            if haveDevice {
                NoomCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noom Band").noomSerifTitle(size: 28)
                        NoomValueRowPublic(label: "Device", value: "Noom Band")
                        NoomValueRowPublic(label: "Serial number", value: deviceIdentity.serialNumber ?? "Unavailable")
                        NoomValueRowPublic(label: "Device ID", value: deviceIdentity.deviceID ?? "Unavailable")
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
        .onAppear {
            now = Date()
            Task { await refreshNotificationStatus() }
        }
        .onChange(of: dailyCheckInEnabled) { _, enabled in
            Task { await updateReminderPreferences(requestPermissionIfNeeded: enabled) }
        }
        .onChange(of: experimentReminderEnabled) { _, enabled in
            Task { await updateReminderPreferences(requestPermissionIfNeeded: enabled) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { now = Date() }
            }
        }
        .onReceive(sensorBio.$haveDevice.receive(on: DispatchQueue.main)) { haveDevice = $0 }
        .onReceive(sensorBio.$connected.receive(on: DispatchQueue.main)) { isConnected in
            connected = isConnected
            if isConnected {
                deviceIdentity.connectionEstablished(
                    deviceID: pairedDevice?.macAddress,
                    currentSDKSerial: sensorBio.serialNumber
                )
            } else {
                deviceIdentity.begin(
                    deviceID: pairedDevice?.macAddress,
                    currentSDKSerial: sensorBio.serialNumber,
                    waitForConnection: true
                )
            }
        }
        .onReceive(sensorBio.$pairedDevice.receive(on: DispatchQueue.main)) { device in
            pairedDevice = device
            if device?.macAddress != deviceIdentity.deviceID {
                deviceIdentity.begin(
                    deviceID: device?.macAddress,
                    currentSDKSerial: sensorBio.serialNumber,
                    waitForConnection: true
                )
            }
            if connected {
                deviceIdentity.connectionEstablished(
                    deviceID: device?.macAddress,
                    currentSDKSerial: sensorBio.serialNumber
                )
            }
        }
        .onReceive(DeviceIdentityPresentation.serialsOnMain(sensorBio.$serialNumber)) { serialNumber in
            deviceIdentity.observe(
                serial: serialNumber,
                currentSDKSerial: sensorBio.serialNumber
            )
        }
        .onReceive(sensorBio.$lastSyncd.receive(on: DispatchQueue.main)) { lastSyncd = $0 }
        .onReceive(sensorBio.$deviceSyncing.receive(on: DispatchQueue.main)) { syncing = $0 }
        .onReceive(sensorBio.$percentSynced.receive(on: DispatchQueue.main)) { percentSynced = $0 }
        .sheet(isPresented: $presentingPair) {
            PairDeviceView()
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Enabled"
        case .denied: "Denied"
        case .notDetermined: "Not enabled"
        @unknown default: "Not enabled"
        }
    }

    private func updateReminderPreferences(requestPermissionIfNeeded: Bool) async {
        notificationError = nil
        if requestPermissionIfNeeded {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                do {
                    _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                } catch {
                    notificationError = "Notification permission could not be requested."
                }
            }
        }
        await refreshNotificationStatus()
        do {
            let payload: [String: Any] = [
                "dailyCheckInEnabled": dailyCheckInEnabled,
                "experimentReminderEnabled": experimentReminderEnabled
            ]
            let _: ProductLoopPreferenceSaved = try await ProductLoopAPI.shared.request(path: "/demo/v1/preferences", method: "PUT", body: payload)
        } catch {
            notificationError = ProductLoopAPI.displayError(error)
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
        pairedDevice = nil
        deviceIdentity.begin(
            deviceID: nil,
            currentSDKSerial: sensorBio.serialNumber,
            waitForConnection: true
        )
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
