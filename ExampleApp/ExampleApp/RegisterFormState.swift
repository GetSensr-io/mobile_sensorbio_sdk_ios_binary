import Foundation
import Observation
import SensorBioSDK

/// Shared gate so `ContentView` doesn't route into the authenticated UI on the
/// transient `session` the SDK publishes *during* a `registerUser` attempt. A
/// failed register can still create the account and publish a session before it
/// throws (e.g. `SB_AuthError.tokenRefreshFailed`); we roll that session back
/// before lowering this flag, so a failed register never strands the user in a
/// broken signed-in state.
@Observable
final class AuthFlow {
    static let shared = AuthFlow()
    private init() {}
    var isRegistering: Bool = false
}

/// Drives the SDK-key `registerUser` flow.
///
/// `registerUser` is the register-or-login entry point for apps that have
/// already authenticated the end-user by their own means (their login, SSO,
/// OAuth — the SDK doesn't care which). These users have no Sensor Bio
/// email/password. The first call for a given `userId` registers; subsequent
/// calls log the same `userId` back in. On success the SDK persists the
/// session and publishes `sensorBio.session`, so `ContentView` routes to the
/// dashboard automatically — this form has no "route to home" logic of its own.
@Observable
final class RegisterFormState {
    // MARK: Required SDK-key credentials
    //
    // For a real integration these come from your Sensor Bio dashboard
    // (`org_id` + `sdk_token`) and your own user store (`userId`). The example
    // persists them across launches so relaunch-and-register logs you straight
    // back into the same demo user.
    var orgId: String = ""
    var sdkKey: String = ""
    var userId: String = ""

    // MARK: Optional demographics
    //
    // The platform needs height / weight / sex / birthday to compute the
    // higher-level metrics (recovery, calories, sleep scoring). Any value you
    // omit is filled with a dummy by the SDK, so pass real values when you have
    // them. Toggle `includeProfile` off to demonstrate the bare-minimum call.
    var includeProfile: Bool = false
    var email: String = ""
    var birthday: Date = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date()
    var sex: SB_Gender = .undisclosed
    var imperialUnits: Bool = true
    var heightCm: String = ""
    var heightFeet: String = ""
    var heightInches: String = ""
    var weightInput: String = ""

    // Optional device-subscription activation code (redeemed on first register).
    var activationCode: String = ""

    var isSubmitting: Bool = false
    var result: Result? = nil

    enum Result {
        case success(username: String)
        case failure(errorCode: String)
        case threw(String)
    }

    private enum Keys {
        static let orgId = "register.orgId"
        static let sdkKey = "register.sdkKey"
        static let userId = "register.userId"
    }

    init() {
        let defaults = UserDefaults.standard
        orgId = defaults.string(forKey: Keys.orgId) ?? ""
        sdkKey = defaults.string(forKey: Keys.sdkKey) ?? ""
        userId = defaults.string(forKey: Keys.userId) ?? ""
    }

    var heightOK: Bool {
        if imperialUnits {
            return Float(heightFeet) != nil && Float(heightInches) != nil
        } else {
            return Float(heightCm) != nil
        }
    }

    var canSubmit: Bool {
        !trimmed(orgId).isEmpty &&
        !trimmed(sdkKey).isEmpty &&
        !trimmed(userId).isEmpty &&
        (!includeProfile || heightOK) &&
        !isSubmitting
    }

    @MainActor
    func submit() async {
        isSubmitting = true
        result = nil
        // Hold routing until we've fully resolved the attempt (including any
        // rollback), so ContentView never flips to the tabs on a half-created
        // session that we're about to sign back out.
        AuthFlow.shared.isRegistering = true
        defer {
            isSubmitting = false
            AuthFlow.shared.isRegistering = false
        }

        persistCredentials()

        // Configure the SDK-key credentials once, then register with just the
        // user identity. The SDK reads org_id/sdk_token from here for the
        // register call and every authenticated call after it.
        SB_SDK.sdkKeyCredentials = SB_SDKKeyCredentials(org_id: trimmed(orgId), sdk_token: trimmed(sdkKey))

        // Optional demographics — only sent when the profile section is on and
        // the field parses. Everything left nil is dummy-filled by the SDK.
        var birthdayComponents: DateComponents? = nil
        var sexValue: SB_Gender? = nil
        var heightCmValue: Float? = nil
        var weightKgValue: Float? = nil

        if includeProfile {
            birthdayComponents = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
            sexValue = sex
            if imperialUnits {
                if let feet = Float(heightFeet), let inches = Float(heightInches) {
                    heightCmValue = (feet * 12 + inches) * 2.54
                }
                if let pounds = Float(weightInput) {
                    weightKgValue = pounds * 0.453_592
                }
            } else {
                heightCmValue = Float(heightCm)
                weightKgValue = Float(weightInput)
            }
        }

        let contactEmail = trimmed(email)

        do {
            let outcome = try await sensorBio.registerUser(
                userId: trimmed(userId),
                email: contactEmail.isEmpty ? nil : contactEmail,
                birthday: birthdayComponents,
                sex: sexValue,
                heightCm: heightCmValue,
                weightKg: weightKgValue,
                imperialUnits: imperialUnits,
                activationCode: trimmed(activationCode).isEmpty ? nil : trimmed(activationCode)
            )
            switch outcome {
            case .success(let session):
                result = .success(username: session.username)
            case .failure(let errorCode):
                result = .failure(errorCode: errorCode)
                await rollBackSession()
            @unknown default:
                break
            }
        } catch {
            result = .threw(Self.describe(error))
            await rollBackSession()
        }
    }

    /// A `registerUser` that fails *after* creating the account can leave the
    /// SDK holding a published `session`. Undo it so the app returns to the
    /// signed-out screen with the error, instead of stranding the user in a
    /// broken signed-in state they'd have to sign out of by hand.
    @MainActor
    private func rollBackSession() async {
        guard sensorBio.session != nil else { return }
        try? await sensorBio.signOut()
    }

    /// Decode SDK error types into readable copy — the default
    /// `SB_AuthError` description is the useless "…(SensorBioSDK.SB_AuthError
    /// error 2)".
    static func describe(_ error: Error) -> String {
        if let authError = error as? SB_AuthError {
            switch authError {
            case .missingAuthToken:      return "Missing auth token (SB_AuthError.missingAuthToken)"
            case .unexpectedNilResponse: return "Unexpected empty response (SB_AuthError.unexpectedNilResponse)"
            case .tokenRefreshFailed:    return "Token refresh failed (SB_AuthError.tokenRefreshFailed)"
            case .refreshTokenExpired:   return "Refresh token expired (SB_AuthError.refreshTokenExpired)"
            @unknown default:            return String(describing: error)
            }
        }
        return String(describing: error)
    }

    private func persistCredentials() {
        let defaults = UserDefaults.standard
        defaults.set(trimmed(orgId), forKey: Keys.orgId)
        defaults.set(trimmed(sdkKey), forKey: Keys.sdkKey)
        defaults.set(trimmed(userId), forKey: Keys.userId)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
