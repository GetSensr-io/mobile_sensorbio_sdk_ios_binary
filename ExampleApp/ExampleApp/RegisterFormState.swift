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

/// Drives the two-step `registerUser` flow: exchange the organization SDK Key
/// for a single-use SDK token, then register with the token.
///
/// `registerUser` is the register-or-login entry point for apps that have
/// already authenticated the end-user by their own means (their login, SSO,
/// OAuth — the SDK doesn't care which). These users have no Sensor Bio
/// email/password. The first call for a given `userId` registers; subsequent
/// calls log the same `userId` back in. On success the SDK persists the
/// session and publishes `sensorBio.session`, so `ContentView` routes to the
/// dashboard automatically — this form has no "route to home" logic of its own.
///
/// The token exchange in front of it (`SDKTokenExchange`) is the part a real
/// integration puts on its **own backend**: the app receives `sdk_token` +
/// `organization_id` from there and never sees the SDK Key. This form holds the
/// key because it is standing in for that backend — see `SDKTokenExchange` for
/// the long version.
@Observable
final class RegisterFormState {
    // MARK: Required credentials
    //
    // In a real integration the app is handed `sdk_token` + `organization_id`
    // by its own backend, and `userId` comes from its own user store. Here the
    // SDK Key is typed in and exchanged locally, and `orgId` is whatever the
    // last exchange resolved (the key determines the org, so nobody has to type
    // it). The example persists all of this across launches so
    // relaunch-and-register logs you straight back into the same demo user.
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

    /// What the last exchange resolved, for the result panel: the org the key
    /// belongs to and the prefix of the token that was spent. Never log or
    /// display a whole token — the prefix is what Sensor Bio stores server-side
    /// too, so it is the greppable half.
    var lastExchange: SDKTokenExchange.MintedToken? = nil

    enum Result {
        case success(username: String)
        case failure(errorCode: String)
        case threw(String)
        /// The key → token exchange failed, so no register call was made.
        case exchangeFailed(String)
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

        // Step one — what your backend does: exchange the long-lived SDK Key
        // for a single-use token. Fresh every submit; a token is spent by the
        // register it succeeds at, and reusing one fails inside the SDK as an
        // opaque auth error.
        let minted: SDKTokenExchange.MintedToken
        do {
            minted = try await SDKTokenExchange.mintToken(sdkKey: trimmed(sdkKey))
        } catch {
            lastExchange = nil
            result = .exchangeFailed(error.localizedDescription)
            return
        }
        lastExchange = minted
        // Hand it to the Profile tab too: this form's state dies as soon as
        // the register succeeds and ContentView routes to the tabs.
        SDKTokenRecord.shared.record(minted)

        // The exchange is authoritative for the org id — the key determines it.
        orgId = minted.organizationId
        UserDefaults.standard.set(minted.organizationId, forKey: Keys.orgId)

        // Configure the org credentials once, then register with just the user
        // identity. `sdkKeyCredentials` is what every authenticated call after
        // the register carries; the single-use token is passed to the register
        // call itself, below, and is the only credential that call presents.
        SB_SDK.sdkKeyCredentials = SB_SDKKeyCredentials(org_id: minted.organizationId, sdk_token: trimmed(sdkKey))

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
                activationCode: trimmed(activationCode).isEmpty ? nil : trimmed(activationCode),
                sdkToken: minted.sdkToken
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

    /// The org id is deliberately absent: it is written from the exchange
    /// response in `submit()`, which is the only thing that knows it.
    private func persistCredentials() {
        let defaults = UserDefaults.standard
        defaults.set(trimmed(sdkKey), forKey: Keys.sdkKey)
        defaults.set(trimmed(userId), forKey: Keys.userId)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
