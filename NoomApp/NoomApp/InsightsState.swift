import Foundation
import Observation
import SensorBioSDK

@Observable
final class InsightsState {
    var personal: SB_NewInsights?
    var personalError: String?
    var isLoadingPersonal = false

    var feedbackMessage: String?

    @MainActor
    func loadPersonal() async {
        isLoadingPersonal = true
        personalError = nil
        defer { isLoadingPersonal = false }
        do {
            personal = try await sensorBio.fetchNewInsights()
        } catch SB_InsightError.notEnoughSessions {
            personal = nil
        } catch {
            personalError = error.localizedDescription
        }
    }


    @MainActor
    func submitFeedback(_ feedback: SB_InsightFeedback) async {
        guard let insightId = personal?.insightId else { return }
        do {
            try await sensorBio.submitInsightsFeedback(insightId: insightId, feedback: feedback)
            feedbackMessage = feedback == .helpful ? "Thanks, feedback saved." : "Thanks, we saved your feedback."
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }
}
