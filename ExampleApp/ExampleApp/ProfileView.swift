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

    // The signed-in user the SDK publishes. `registerUser` fills the demographics
    // it was given (and substitutes neutral values for the ones it wasn't), so this
    // is where a host sees what the platform actually holds for its user.
    @State private var profile: SB_UserProfile? = sensorBio.userProfile
    // Editable fields, prefilled from the profile once it arrives.
    @State private var birthYear: String = ""
    @State private var birthMonth: String = ""
    @State private var birthDay: String = ""
    @State private var heightCm: String = ""
    @State private var weightKg: String = ""
    @State private var prefilled: Bool = false
    @State private var saving: Bool = false
    @State private var saveMessage: String? = nil

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Signed in", value: session.username)
                LabeledContent("Name", value: display(profile?.fullName))
                LabeledContent("Email", value: display(profile?.email))
                LabeledContent("Sex", value: profile.map { genderName($0.sex) } ?? "—")
                LabeledContent("Age", value: profile?.age.map(String.init) ?? "—")
                LabeledContent("Units", value: profile.map { $0.imperialUnits ? "IMPERIAL" : "METRIC" } ?? "—")
                LabeledContent("SDK version", value: sensorBio.sdkVersion)
            }

            // Demographics are not decoration: the platform needs height/weight/sex/
            // birthday to compute recovery, calories and sleep scoring, and
            // `registerUser` substitutes neutral values for whatever it wasn't given.
            // An integration that collects them later writes them back here.
            Section("Edit Metrics") {
                LabeledContent("Birthday") {
                    HStack(spacing: 6) {
                        numberField("Year", text: $birthYear, width: 56)
                        numberField("Mo", text: $birthMonth, width: 40)
                        numberField("Day", text: $birthDay, width: 40)
                    }
                }
                LabeledContent("Height (cm)") {
                    numberField("cm", text: $heightCm, width: 80, decimal: true)
                }
                LabeledContent("Weight (kg)") {
                    numberField("kg", text: $weightKg, width: 80, decimal: true)
                }
                Button {
                    Task { await saveMetrics() }
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Text("Save Changes")
                    }
                }
                .disabled(profile == nil || saving)
                if let saveMessage {
                    Text(saveMessage).foregroundStyle(.secondary)
                }
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
        .onReceive(sensorBio.$userProfile) { incoming in
            profile = incoming
            guard let incoming, !prefilled else { return }
            // A nil birthday means the server holds none — leave the fields empty
            // rather than showing a sentinel date the user never entered.
            birthYear = incoming.birthday?.year.map(String.init) ?? ""
            birthMonth = incoming.birthday?.month.map(String.init) ?? ""
            birthDay = incoming.birthday?.day.map(String.init) ?? ""
            heightCm = incoming.metricHeight > 0 ? String(format: "%.0f", incoming.metricHeight) : ""
            weightKg = incoming.metricWeight > 0 ? String(format: "%.1f", incoming.metricWeight) : ""
            prefilled = true
        }
        .sheet(isPresented: $presentingPair) {
            PairDeviceView()
        }
        .sheet(isPresented: $presentingToken) {
            SDKTokenSheet(record: tokenRecord)
        }
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }

    private func genderName(_ sex: SB_Gender) -> String {
        switch sex {
        case .male: return "MALE"
        case .female: return "FEMALE"
        case .undisclosed: return "UNDISCLOSED"
        }
    }

    private func numberField(
        _ prompt: String,
        text: Binding<String>,
        width: CGFloat,
        decimal: Bool = false
    ) -> some View {
        TextField(prompt, text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
    }

    @MainActor
    private func saveMetrics() async {
        guard let current = profile else { return }
        saving = true
        saveMessage = nil
        defer { saving = false }

        // The update RPC always writes a birthday, so an edit has to state one:
        // fall back to the profile's, then to the neutral date `registerUser`
        // substitutes. Every other field is carried through unchanged — this is a
        // whole-profile write, not a patch, so omitting one would erase it.
        var birthday = DateComponents()
        birthday.year = Int(birthYear) ?? current.birthday?.year ?? 1990
        birthday.month = Int(birthMonth) ?? current.birthday?.month ?? 6
        birthday.day = Int(birthDay) ?? current.birthday?.day ?? 15

        let update = SB_UserProfileUpdate(
            fullName: current.fullName,
            birthday: birthday,
            gender: current.sex,
            heightCm: Float(heightCm) ?? current.metricHeight,
            weightKg: Float(weightKg) ?? current.metricWeight,
            walkingStrideLength: current.walkStride,
            runningStrideLength: current.runStride,
            location: current.location,
            vo2Max: current.vo2Max,
            maxHr: current.maxHr,
            imperialUnits: current.imperialUnits
        )

        do {
            switch try await sensorBio.updateUserProfile(update) {
            case .ok:                       saveMessage = "Saved ✓"
            case .invalidHeight:            saveMessage = "Invalid height"
            case .invalidWeight:            saveMessage = "Invalid weight"
            case .invalidBirthday:          saveMessage = "Invalid birthday"
            case .other(let message):       saveMessage = message
            }
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
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
