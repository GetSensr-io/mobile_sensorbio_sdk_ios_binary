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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
