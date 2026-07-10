import SwiftUI
import SensorBioSDK

struct SignInView: View {
    @State private var form = SignInFormState()
    @State private var showPassword: Bool = false
    @State private var resetStatus: PasswordResetStatus? = nil
    @State private var isRequestingReset: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                SignInFullBleedHero()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            NoomLogoPlate(compact: true)
                            Spacer()
                        }
                        .padding(.horizontal, NoomTheme.horizontalPadding)
                        .padding(.top, geometry.safeAreaInsets.top + 10)

                        Spacer(minLength: max(238, geometry.size.height * 0.29))

                        signInPanel
                            .frame(width: geometry.size.width, alignment: .leading)
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome back")
                    .noomSerifTitle(size: 40)
                Text("Continue your everyday plan with your Noom Band.")
                    .noomBody()
            }

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email").noomLabel()
                    TextField("Email", text: $form.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(NoomTheme.logoBlack)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(NoomTheme.softLine, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password").noomLabel()
                    HStack(spacing: 10) {
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(NoomTheme.logoBlack)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NoomTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(NoomTheme.softLine, lineWidth: 1)
                    }
                }

                if let result = form.result {
                    resultView(result)
                        .padding(.top, 2)
                }

                if let resetStatus {
                    passwordResetStatusView(resetStatus)
                        .padding(.top, 2)
                }

                Button {
                    dismissKeyboard()
                    Task { await form.submit() }
                } label: {
                    if form.isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in")
                    }
                }
                .buttonStyle(NoomPrimaryButtonStyle())
                .disabled(!form.canSubmit)
                .padding(.top, 4)

                HStack {
                    Button {
                        dismissKeyboard()
                        Task { await requestPasswordReset() }
                    } label: {
                        if isRequestingReset {
                            ProgressView().tint(NoomTheme.logoBlack)
                        } else {
                            Text("Forgot password?")
                        }
                    }
                    .disabled(form.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRequestingReset)
                    Spacer()
                    NavigationLink("Create account") { SignUpView() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NoomTheme.logoBlack.opacity(0.70))
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, NoomTheme.horizontalPadding)
        .padding(.top, 30)
        .padding(.bottom, 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoomTheme.warmSurface.opacity(0.98))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
        .overlay(alignment: .top) {
            Capsule()
                .fill(NoomTheme.ink.opacity(0.12))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    @MainActor
    private func requestPasswordReset() async {
        let email = form.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }
        isRequestingReset = true
        resetStatus = nil
        defer { isRequestingReset = false }
        do {
            switch try await sensorBio.requestPasswordReset(email: email) {
            case .ok:
                resetStatus = .resetSent
            case .userNotFound:
                resetStatus = .notFound
            case .other(let message):
                resetStatus = .failed(message.isEmpty ? "We could not send a reset link. Please try again." : message)
            @unknown default:
                resetStatus = .failed("We could not send a reset link. Please try again.")
            }
        } catch {
            resetStatus = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func resultView(_ result: SignInFormState.Result) -> some View {
        switch result {
        case .success(let username):
            SignInStatusRow(text: "Signed in as \(username)", systemImage: "checkmark.circle.fill", tint: Color(hex: 0x356F4B))
        case .passwordIncorrect:
            SignInStatusRow(text: "Password incorrect", systemImage: "xmark.octagon.fill", tint: NoomTheme.red)
        case .unknownUsername:
            SignInStatusRow(text: "Unknown username", systemImage: "xmark.octagon.fill", tint: NoomTheme.red)
        case .subscriptionRequired(let message):
            SignInStatusRow(text: message.isEmpty ? "A subscription is required" : message, systemImage: "creditcard.trianglebadge.exclamationmark", tint: NoomTheme.gold)
        case .loginBlocked(let message):
            SignInStatusRow(text: message.isEmpty ? "Too many failed attempts. Try again later." : message, systemImage: "lock.trianglebadge.exclamationmark.fill", tint: NoomTheme.red)
        case .other(let message):
            SignInStatusRow(text: message.isEmpty ? "We could not sign you in. Please try again." : message, systemImage: "exclamationmark.triangle.fill", tint: NoomTheme.gold)
        case .threw(let description):
            SignInStatusRow(text: friendlyMessage(for: description), systemImage: "bolt.trianglebadge.exclamationmark.fill", tint: NoomTheme.gold)
        @unknown default:
            EmptyView()
        }
    }

    private func passwordResetStatusView(_ status: PasswordResetStatus) -> some View {
        switch status {
        case .resetSent:
            SignInStatusRow(text: "Reset link sent. Check your email.", systemImage: "envelope.badge.fill", tint: Color(hex: 0x356F4B))
        case .notFound:
            SignInStatusRow(text: "No account found for that email.", systemImage: "xmark.octagon.fill", tint: NoomTheme.red)
        case .failed(let message):
            SignInStatusRow(text: message, systemImage: "exclamationmark.triangle.fill", tint: NoomTheme.gold)
        }
    }

    private func friendlyMessage(for raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("unavailable") || lower.contains("offline") ||
           lower.contains("network") || lower.contains("connection") ||
           lower.contains("internet") {
            return "Noom service unreachable. Please check your internet connection and try again."
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

private enum PasswordResetStatus: Equatable {
    case resetSent
    case notFound
    case failed(String)
}

private struct SignInStatusRow: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint == NoomTheme.gold ? NoomTheme.logoBlack : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SignInFullBleedHero: View {
    var body: some View {
        Image("WelcomeMorning")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .overlay {
                LinearGradient(
                    colors: [
                        Color.clear,
                        NoomTheme.ink.opacity(0.10),
                        NoomTheme.warmSurface.opacity(0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .accessibilityHidden(true)
    }
}

private struct SignInHeroCollage: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFF1E8), NoomTheme.warmSurface, Color(hex: 0xF4E0D3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Canvas { context, size in
                        for index in 0..<42 {
                            let x = CGFloat((index * 47) % 320) / 320 * size.width
                            let y = CGFloat((index * 83) % 280) / 280 * size.height
                            let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                            context.fill(Path(ellipseIn: rect), with: .color(NoomTheme.logoBlack.opacity(0.035)))
                        }
                    }
                }

            Path { path in
                path.move(to: CGPoint(x: 20, y: 250))
                path.addCurve(to: CGPoint(x: 175, y: 170), control1: CGPoint(x: 78, y: 226), control2: CGPoint(x: 112, y: 175))
                path.addCurve(to: CGPoint(x: 310, y: 42), control1: CGPoint(x: 236, y: 166), control2: CGPoint(x: 254, y: 76))
            }
            .stroke(NoomTheme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 20, lineCap: .round))
            .blur(radius: 0.4)

            Path { path in
                path.move(to: CGPoint(x: 26, y: 246))
                path.addCurve(to: CGPoint(x: 174, y: 168), control1: CGPoint(x: 78, y: 224), control2: CGPoint(x: 112, y: 176))
                path.addCurve(to: CGPoint(x: 304, y: 48), control1: CGPoint(x: 234, y: 163), control2: CGPoint(x: 250, y: 78))
            }
            .stroke(Color.white.opacity(0.58), style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [1, 18]))

            Circle()
                .fill(NoomTheme.red)
                .frame(width: 18, height: 18)
                .offset(x: 102, y: -82)
                .shadow(color: NoomTheme.red.opacity(0.28), radius: 14, x: 0, y: 8)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(NoomTheme.ink.opacity(0.92))
                .frame(width: 118, height: 148)
                .rotationEffect(.degrees(-8))
                .offset(x: -78, y: 18)
                .shadow(color: NoomTheme.ink.opacity(0.22), radius: 24, x: 0, y: 18)
                .overlay {
                    VStack(spacing: 9) {
                        ForEach([0.40, 0.66, 0.52, 0.76], id: \.self) { value in
                            Capsule()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 62 * value, height: 6)
                        }
                    }
                    .rotationEffect(.degrees(-8))
                    .offset(x: -78, y: 18)
                }

            Circle()
                .fill(Color.white.opacity(0.62))
                .frame(width: 118, height: 118)
                .offset(x: 76, y: 76)
                .overlay {
                    Circle()
                        .stroke(NoomTheme.ink.opacity(0.12), lineWidth: 1)
                        .frame(width: 118, height: 118)
                        .offset(x: 76, y: 76)
                }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach([0.76, 0.62, 0.50, 0.38, 0.32], id: \.self) { height in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0xFF8D54), NoomTheme.red], startPoint: .top, endPoint: .bottom))
                        .frame(width: 12, height: 72 * height)
                }
            }
            .offset(x: 74, y: 82)
        }
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(NoomTheme.softLine.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: NoomTheme.ink.opacity(0.08), radius: 28, x: 0, y: 18)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { SignInView() }
}
