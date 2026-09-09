import Foundation
import Observation
import SensorBioSDK

@Observable
final class DashboardState {
    var data: SB_DashboardData? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    @MainActor
    func load(date: Date) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let tzOffset = Int32(TimeZone.current.secondsFromGMT(for: date))
        do {
            data = try await sensorBio.fetchDashboardData(date: date, tzOffset: tzOffset)
        } catch SB_AuthError.refreshTokenExpired {
            // Reaching here now means recovery itself failed. Access-token
            // expiry is refreshed transparently, and a dead refresh chain is
            // rebuilt transparently too — the SDK mints a fresh token through
            // `SB_SDK.sdkTokenProvider` and logs the same user back in. This
            // case is what's left: no provider, or the provider declined (no
            // key saved, backend down, host's own user no longer authenticated).
            // The session really is over, so sign out and route to Register.
            try? await sensorBio.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
