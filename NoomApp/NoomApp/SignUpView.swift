import SwiftUI
import SensorBioSDK

struct SignUpView: View {
    @State private var form = SignUpFormState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    NoomLogoPlate(compact: true)
                    Spacer()
                }
                .padding(.top, 10)

                compactSection("Account") {
                    TextField(text: $form.username, prompt: prompt("Username")) { Text("Username") }
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    NoomDivider()
                    TextField(text: $form.email, prompt: prompt("Email")) { Text("Email") }
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    NoomDivider()
                    SecureField(text: $form.password, prompt: prompt("Password (min 6 chars)")) { Text("Password (min 6 chars)") }
                        .textContentType(.newPassword)
                }

                compactSection("Profile") {
                    DatePicker("Birthday", selection: $form.birthday, in: ...Date(), displayedComponents: .date)
                    NoomDivider()
                    Picker("Gender", selection: $form.gender) {
                        Text("Male").tag(SB_Gender.male)
                        Text("Female").tag(SB_Gender.female)
                        Text("Undisclosed").tag(SB_Gender.undisclosed)
                    }
                }

                compactSection("Body") {
                    Toggle("Imperial units (ft / lbs)", isOn: $form.imperialUnits)
                    NoomDivider()
                    if form.imperialUnits {
                        HStack {
                            TextField(text: $form.heightFeet, prompt: prompt("Feet")) { Text("Feet") }
                                .keyboardType(.numberPad)
                            Text("ft").foregroundStyle(.secondary)
                            TextField(text: $form.heightInches, prompt: prompt("Inches")) { Text("Inches") }
                                .keyboardType(.decimalPad)
                            Text("in").foregroundStyle(.secondary)
                        }
                        NoomDivider()
                        HStack {
                            TextField(text: $form.weightInput, prompt: prompt("Weight")) { Text("Weight") }
                                .keyboardType(.decimalPad)
                            Text("lbs").foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            TextField(text: $form.heightCm, prompt: prompt("Height")) { Text("Height") }
                                .keyboardType(.decimalPad)
                            Text("cm").foregroundStyle(.secondary)
                        }
                        NoomDivider()
                        HStack {
                            TextField(text: $form.weightInput, prompt: prompt("Weight")) { Text("Weight") }
                                .keyboardType(.decimalPad)
                            Text("kg").foregroundStyle(.secondary)
                        }
                    }
                }

                if let result = form.result {
                    compactSection("Status") { resultView(result) }
                }
            }
            .padding(.horizontal, NoomTheme.horizontalPadding)
            .padding(.bottom, 92)
        }
        .scrollDismissesKeyboard(.interactively)
        .noomBackground()
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    dismissKeyboard()
                    Task { await form.submit() }
                } label: {
                    HStack {
                        Spacer()
                        if form.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create Account").bold()
                        }
                        Spacer()
                    }
                }
                .buttonStyle(NoomPrimaryButtonStyle())
                .disabled(!form.canSubmit)
                .padding(.horizontal, NoomTheme.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .background(.ultraThinMaterial)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }

    @ViewBuilder
    private func compactSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                content()
                    .font(.system(size: 17))
                    .frame(minHeight: 40)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(NoomTheme.ink.opacity(0.72))
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    @ViewBuilder
    private func resultView(_ result: SignUpFormState.Result) -> some View {
        switch result {
        case .success(let username):
            Label("Signed in as \(username)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalidBirthday:
            Label("Please check your birthday and try again.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidEmail:
            Label("Enter a valid email address.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidHeight:
            Label("Please check your height and try again.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidWeight:
            Label("Please check your weight and try again.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidAccessCode:
            Label("Account setup is not configured correctly. Please contact support.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .accessCodeAlreadyInUse:
            Label("This account setup link has already been used. Please contact support.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .deviceSerialNumberRequired:
            Label("This account requires a Noom Band serial number. Please contact support.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .deviceSerialNumberMismatch:
            Label("The Noom Band assigned to this account does not match. Please contact support.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .other(let message):
            Label(message.isEmpty ? "We could not create your account. Please try again." : message,
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .threw:
            Label("We could not create your account. Please try again.", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.orange)
        case .unexpected:
            Label("Noom+ received an unexpected account response. Please try again.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct NoomDivider: View {
    var body: some View {
        NoomTheme.ink.opacity(0.08).frame(height: 1)
    }
}

#Preview {
    NavigationStack { SignUpView() }
}
