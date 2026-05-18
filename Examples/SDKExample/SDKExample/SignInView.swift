import SwiftUI
import SensorBioSDK

struct SignInView: View {
    @State private var form = SignInFormState()
    @State private var showPassword: Bool = false

    var body: some View {
        Form {
            Section("Credentials") {
                TextField("Email", text: $form.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Group {
                        if showPassword {
                            TextField("Password", text: $form.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Password", text: $form.password)
                        }
                    }
                    .textContentType(.password)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
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
                            Text("Sign In").bold()
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
        .navigationTitle("Sign In")
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
    private func resultView(_ result: SignInFormState.Result) -> some View {
        switch result {
        case .success(let username):
            Label("Signed in as \(username)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .passwordIncorrect:
            Label("Password incorrect", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .unknownUsername:
            Label("Unknown username", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .other(let message):
            Label(message.isEmpty ? "Server returned a non-OK error" : message,
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
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
            return "Sign-in was cancelled."
        }
        return "Sign-in failed. Please try again."
    }
}

#Preview {
    NavigationStack { SignInView() }
}
