import SwiftUI
import SensorBioSDK

/// The signed-out root screen, and the SDK's only way in.
///
/// `registerUser` is the single entry point for an embedding app: the end-user
/// is already authenticated by the host (its own login / SSO / OAuth), so the
/// SDK takes one register-or-login call keyed on `org_id` + `sdk_token` + `userId`.
/// There is no email/password surface in the distributed SDK — `signIn` and
/// `createAccount` are compile-gated behind `SENSORBIO_INTERNAL` and absent
/// from the shipped xcframework — so this screen has no alternative to offer
/// and stands alone rather than sitting behind a menu.
struct RegisterView: View {
    @State private var form = RegisterFormState()
    @State private var showSDKKey: Bool = false
    // Shared with ContentView, which applies it to `SB_SDK.environment`.
    @AppStorage("envIsDev") private var envIsDev: Bool = true

    var body: some View {
        Form {
            Section {
                Picker("Server", selection: $envIsDev) {
                    Text("Staging").tag(true)
                    Text("Prod").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Environment")
            } footer: {
                Text("Flip before registering. Changes after the first RPC take full effect on next launch.")
            }

            Section {
                TextField("Org ID", text: $form.orgId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Group {
                        if showSDKKey {
                            TextField("SDK Token", text: $form.sdkKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("SDK Token", text: $form.sdkKey)
                        }
                    }
                    Button {
                        showSDKKey.toggle()
                    } label: {
                        Image(systemName: showSDKKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showSDKKey ? "Hide SDK key" : "Show SDK key")
                }
                TextField("User ID", text: $form.userId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("SDK Credentials")
            } footer: {
                Text("Org ID and SDK Key come from your Sensor Bio dashboard. User ID is your own stable identifier for the end-user — the first register for a User ID creates it, later calls log it back in.")
            }

            Section {
                Toggle("Include demographics", isOn: $form.includeProfile)
            } footer: {
                Text("The platform fills any omitted value with a dummy. Provide real demographics so recovery, calories, and sleep scoring compute correctly.")
            }

            if form.includeProfile {
                Section("Profile") {
                    TextField("Contact email (optional)", text: $form.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    DatePicker("Birthday", selection: $form.birthday, in: ...Date(), displayedComponents: .date)
                    Picker("Sex", selection: $form.sex) {
                        Text("Male").tag(SB_Gender.male)
                        Text("Female").tag(SB_Gender.female)
                        Text("Undisclosed").tag(SB_Gender.undisclosed)
                    }
                }

                Section("Body") {
                    Toggle("Imperial units (ft / lbs)", isOn: $form.imperialUnits)
                    if form.imperialUnits {
                        HStack {
                            TextField("Feet", text: $form.heightFeet)
                                .keyboardType(.numberPad)
                            Text("ft").foregroundStyle(.secondary)
                            TextField("Inches", text: $form.heightInches)
                                .keyboardType(.decimalPad)
                            Text("in").foregroundStyle(.secondary)
                        }
                        HStack {
                            TextField("Weight", text: $form.weightInput)
                                .keyboardType(.decimalPad)
                            Text("lbs").foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            TextField("Height", text: $form.heightCm)
                                .keyboardType(.decimalPad)
                            Text("cm").foregroundStyle(.secondary)
                        }
                        HStack {
                            TextField("Weight", text: $form.weightInput)
                                .keyboardType(.decimalPad)
                            Text("kg").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Activation (optional)") {
                TextField("Activation code", text: $form.activationCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    dismissKeyboard()
                    Task { await form.submit() }
                } label: {
                    HStack {
                        Spacer()
                        if form.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Register").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(!form.canSubmit)
            }

            if let result = form.result {
                Section("Result") {
                    resultView(result)
                }
            }
        }
        .navigationTitle("Register")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    @ViewBuilder
    private func resultView(_ result: RegisterFormState.Result) -> some View {
        switch result {
        case .success(let username):
            Label("Registered as \(username)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let errorCode):
            Label(errorCode.isEmpty ? "Registration failed" : errorCode,
                  systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .threw(let description):
            VStack(alignment: .leading, spacing: 4) {
                Label(friendlyMessage(for: description), systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(.orange)
                Text("debug: \(description)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private func friendlyMessage(for raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("unavailable") || lower.contains("offline") ||
           lower.contains("network") || lower.contains("connection") ||
           lower.contains("internet") {
            return "Server unreachable. Please check your internet connection and try again."
        }
        if lower.contains("deadline") || lower.contains("timed out") || lower.contains("timeout") {
            return "Request timed out. Please try again."
        }
        if lower.contains("cancelled") {
            return "Registration was cancelled."
        }
        if lower.contains("token") || lower.contains("auth") {
            return "The account was created but the SDK couldn't establish a session (auth/token error). You've been signed back out."
        }
        return "Registration failed. Please try again."
    }
}

#Preview {
    NavigationStack { RegisterView() }
}
