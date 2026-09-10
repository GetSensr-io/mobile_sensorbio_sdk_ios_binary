import Foundation
import SensorBioSDK

/// The SDK-key → SDK-token exchange (`POST /sdk/v1/token`), performed here in
/// the app **only because this is the example app**.
///
/// ## Read this before copying it
///
/// In a real integration this code belongs on **your server**, not in your app.
/// The organization SDK Key (`sbsk_…`) is long-lived, org-wide, and identical
/// for every one of your users: whoever holds it can mint tokens for any user
/// id they can guess or copy out of a dashboard. That is the whole reason the
/// exchange exists — the key stays on your backend, and the only credential
/// that ever reaches a device is a single-use `sdk_token` (`sbst_…`) that is
/// worth one register-or-login, for one user, for a few minutes.
///
/// The shape your backend should serve is:
///
/// 1. authenticate your own user, however you already do;
/// 2. `POST /sdk/v1/token` with `Authorization: SDKKey sbsk_…`;
/// 3. return `sdk_token` + `organization_id` to the app.
///
/// The app then hands both to the SDK (`registerUser(…, sdkToken:)`). Steps 2
/// and 3 are what this file fakes, so the example app can demonstrate the
/// token flow end to end without standing up a backend first.
///
/// `SDK_INTERFACE.md` § 5 is the guide to building the real thing: the
/// contract, reference implementations, the errors, and key rotation.
///
/// Tokens are single use: mint a fresh one for every register call and never
/// cache one. A reused token fails inside `registerUser` as an authentication
/// error, far from its cause.
enum SDKTokenExchange {

    /// The two fields a real backend must return (`sdkKeyId` / `expiresIn` are
    /// echoed for the result panel — they are diagnostics, not inputs).
    struct MintedToken {
        let sdkToken: String
        let organizationId: String
        let sdkKeyId: String
        let expiresInSeconds: Int
    }

    enum Failure: LocalizedError {
        /// Sensor Bio answered, and said no. `guidance` is the thing to
        /// actually do about it — the bare status doesn't distinguish the four
        /// realistic causes well enough to act on.
        case rejected(status: Int, detail: String, guidance: String)
        /// Never reached Sensor Bio (offline, DNS, TLS, timeout).
        case unreachable(String)
        /// 2xx that didn't decode, or decoded without a token.
        case malformedResponse(String)

        var errorDescription: String? {
            switch self {
            case .rejected(let status, let detail, let guidance):
                let head = detail.isEmpty
                    ? "Token exchange failed (HTTP \(status))"
                    : "Token exchange failed (HTTP \(status)): \(detail)"
                return guidance.isEmpty ? head : "\(head) — \(guidance)"
            case .unreachable(let detail):
                return "Couldn't reach the token exchange: \(detail)"
            case .malformedResponse(let detail):
                return "Unexpected token-exchange response: \(detail)"
            }
        }
    }

    /// Mints one fresh `sdk_token` for `sdkKey`.
    ///
    /// `organizationId` comes back from the exchange, so the app never has to
    /// be told its own org id — the key already determines it. That is why the
    /// register form no longer asks for one.
    static func mintToken(
        sdkKey: String,
        environment: SB_SDK.Environment = SB_SDK.environment
    ) async throws -> MintedToken {
        var request = URLRequest(url: baseURL(for: environment).appendingPathComponent("sdk/v1/token"))
        request.httpMethod = "POST"
        request.setValue("SDKKey \(sdkKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        // The body is optional and every field in it is too: an empty object
        // takes the 5-minute default TTL and the presented key as the anchor.
        request.httpBody = Data("{}".utf8)
        // Single-use minutes-long credentials must not sit in a URL cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.unreachable(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            // Sensor Bio's JSON error shape is {status, title, detail}; a
            // proxy or a 464 (HTTP/1.x) may answer with neither.
            let apiError = try? JSONDecoder().decode(APIError.self, from: data)
            let detail = apiError?.detail ?? apiError?.title ?? snippet(of: data)
            throw Failure.rejected(status: status, detail: detail, guidance: guidance(for: status))
        }

        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw Failure.malformedResponse(snippet(of: data))
        }
        guard !decoded.sdkToken.isEmpty, !decoded.organizationId.isEmpty else {
            throw Failure.malformedResponse("missing sdk_token or organization_id")
        }

        return MintedToken(
            sdkToken: decoded.sdkToken,
            organizationId: decoded.organizationId,
            sdkKeyId: decoded.sdkKeyId ?? "",
            expiresInSeconds: decoded.expiresInSeconds ?? 0
        )
    }

    /// The `SB_SDK.sdkTokenProvider` closure this app installs at launch — the
    /// hook the SDK pulls when it needs a token and none was handed to it:
    /// a `registerUser` called without one, or a session that died and has to
    /// be rebuilt (a refresh token past its 60-day window, a revoked SDK key).
    ///
    /// In your app this closure calls **your backend**. Here it re-reads the
    /// key the register form saved and mints locally, which is the same
    /// stand-in the rest of this file is. It throws when no key has been
    /// entered — the SDK treats a throw as the host declining to mint and
    /// surfaces the auth error it already had, which is the right outcome:
    /// there is nobody to ask.
    static func makeProvider() -> SB_SDKTokenProvider {
        return {
            let key = UserDefaults.standard
                .string(forKey: "register.sdkKey")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else {
                throw Failure.unreachable("no SDK Key saved on this device — register once first")
            }
            let minted = try await mintToken(sdkKey: key)
            // Surface it in the Profile tab like any other mint, so a session
            // the SDK rebuilt on its own is visible rather than mysterious.
            await MainActor.run { SDKTokenRecord.shared.record(minted) }
            return minted.sdkToken
        }
    }

    /// The REST public API, which is a different host from the SDK's gRPC one
    /// (`SB_SDK.Environment.host`) — hence the second mapping here.
    private static func baseURL(for environment: SB_SDK.Environment) -> URL {
        switch environment {
        case .staging:    return URL(string: "https://staging.api.sensorbio.com")!
        case .production: return URL(string: "https://api.sensorbio.com")!
        @unknown default: return URL(string: "https://api.sensorbio.com")!
        }
    }

    /// One line per way the exchange realistically fails: the bare status does
    /// not distinguish them well enough to act on. Same wording as
    /// `SDK_INTERFACE.md` § 5's error table.
    private static func guidance(for status: Int) -> String {
        switch status {
        case 401:
            return "The SDK Key was rejected. Sensor Bio answers identically for a key that is "
                + "unknown, revoked, or expired, so check all three: that the whole key was "
                + "copied, that it hasn't been revoked in Developer Settings, and that it "
                + "hasn't passed its expiry."
        case 403:
            return "The organization has no usable SDK Key. Create one under Developer Settings."
        case 400:
            return "Sensor Bio rejected the request parameters."
        case 404:
            return "No exchange endpoint at this base URL — check the environment toggle, and "
                + "that the deployment you're pointing at has the SDK token exchange released."
        case 500...599:
            return "Sensor Bio returned a server error. Retry; if it persists, contact "
                + "developers@sensorbio.com."
        default:
            return ""
        }
    }

    private static func snippet(of data: Data) -> String {
        let text = String(decoding: data.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "empty response body" : text
    }

    // MARK: Wire shapes

    private struct TokenResponse: Decodable {
        let sdkToken: String
        let organizationId: String
        let sdkKeyId: String?
        let expiresInSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case sdkToken = "sdk_token"
            case organizationId = "organization_id"
            case sdkKeyId = "sdk_key_id"
            case expiresInSeconds = "expires_in_seconds"
        }
    }

    private struct APIError: Decodable {
        let title: String?
        let detail: String?
    }
}

/// The token the current launch minted, so the Profile tab can show what the
/// register call actually presented (`SDKTokenSheet`).
///
/// **In memory only, and deliberately so.** A minted token is spent by the
/// register that used it, and persisting a credential — even a spent one —
/// teaches the wrong habit for a file customers read. After a cold launch that
/// hydrates a session there is nothing here, which is the honest answer: the
/// token that created that session no longer exists anywhere.
@Observable
final class SDKTokenRecord {
    static let shared = SDKTokenRecord()
    private init() {}

    private(set) var token: SDKTokenExchange.MintedToken? = nil
    private(set) var mintedAt: Date? = nil

    /// When the exchange said the token would expire. Only meaningful next to
    /// `mintedAt`: it is a wall-clock deadline on a credential that is normally
    /// spent within a second of being minted.
    var expiresAt: Date? {
        guard let mintedAt, let token else { return nil }
        return mintedAt.addingTimeInterval(TimeInterval(token.expiresInSeconds))
    }

    func record(_ token: SDKTokenExchange.MintedToken) {
        self.token = token
        self.mintedAt = Date()
    }
}
