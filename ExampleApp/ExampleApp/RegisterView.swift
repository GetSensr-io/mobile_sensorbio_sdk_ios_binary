import SwiftUI
import SensorBioSDK

/// Single entry point for the SDK-key `registerUser` flow. Replaces the old
/// email/password Sign In + Create Account screens: for embedding apps the
/// user is already authenticated by the host, so there is one register-or-login
/// call keyed on `orgId` + `sdkKey` + `userId`.
struct RegisterView: View {
    @State private var form = RegisterFormState()
    @State private var showSDKKey: Bool = false

    var body: some View {
        Form {
            Section {
                TextField("Org ID", text: $form.orgId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Group {
                        if showSDKKey {
                            TextField("SDK Key", text: $form.sdkKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("SDK Key", text: $form.sdkKey)
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
        .navigationBarTitleDisplayMode(.inline)
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
