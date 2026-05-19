import SwiftUI
import SensorBioSDK

struct SignUpView: View {
    @State private var form = SignUpFormState()

    var body: some View {
        Form {
            Section("Account") {
                TextField("Username", text: $form.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Email", text: $form.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password (min 6 chars)", text: $form.password)
                    .textContentType(.newPassword)
            }

            Section("Profile") {
                DatePicker("Birthday", selection: $form.birthday, in: ...Date(), displayedComponents: .date)
                Picker("Gender", selection: $form.gender) {
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

            Section("Organization (optional)") {
                TextField("Org ID", text: $form.orgId)
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
                            Text("Create Account").bold()
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
        .navigationTitle("Create Account")
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
    private func resultView(_ result: SignUpFormState.Result) -> some View {
        switch result {
        case .success(let username):
            Label("Signed in as \(username)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalidBirthday:
            Label("Server rejected birthday", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidEmail:
            Label("Server rejected email", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidHeight:
            Label("Server rejected height", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .invalidWeight:
            Label("Server rejected weight", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .other(let message):
            Label(message.isEmpty ? "Server returned a non-OK error" : message,
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .threw(let description):
            Label("Threw: \(description)", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.orange)
            @unknown default:
                EmptyView()
        }
    }
}

#Preview {
    NavigationStack { SignUpView() }
}
