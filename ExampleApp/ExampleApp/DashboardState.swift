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
            // The refresh token itself is expired/revoked — the session is over
            // (access-token expiry is handled transparently by the SDK's
            // refresh-and-retry; this is the terminal case). Sign out so the app
            // routes back to the Register screen. A real integration would do
            // this centrally for every authenticated call.
            try? await sensorBio.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
