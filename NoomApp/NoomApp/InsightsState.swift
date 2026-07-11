import Foundation
import Observation
import SensorBioSDK

@Observable
final class InsightsState {
    var personal: SB_NewInsights?
    var personalError: String?
    var isLoadingPersonal = false

    var populationFilters: SB_PopulationInsightsFilterList?
    var selectedPopulationMetric: SB_PopulationInsightMetric?
    var selectedAgeGroup: SB_PopulationAgeGroup?
    var selectedGender: SB_PopulationGender = .all
    var populationHistogram: SB_PopulationInsightsHistogram?
    var populationRadarChart: SB_PopulationInsightsRadarChart?
    var populationError: String?
    var isLoadingPopulation = false
    var feedbackMessage: String?

    private var activePopulationRequestID: UUID?

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
    func loadFilters() async {
        populationError = nil
        do {
            let filters = try await sensorBio.fetchPopulationInsightsMetricList()
            populationFilters = filters
            if selectedPopulationMetric == nil {
                selectedPopulationMetric = filters.metrics.first
            }
            if selectedAgeGroup == nil {
                selectedAgeGroup = filters.ageGroups.first
            }
            if filters.metrics.isEmpty || filters.ageGroups.isEmpty {
                populationError = "Population comparison filters are not available yet."
            }
        } catch {
            populationError = populationErrorMessage(for: error)
        }
    }

    @MainActor
    func loadPopulation() async {
        let requestID = UUID()
        activePopulationRequestID = requestID
        isLoadingPopulation = true
        populationError = nil
        populationHistogram = nil
        populationRadarChart = nil
        defer {
            if activePopulationRequestID == requestID {
                isLoadingPopulation = false
            }
        }

        if populationFilters == nil {
            await loadFilters()
        }
        guard activePopulationRequestID == requestID else { return }
        guard populationError == nil,
              let metric = selectedPopulationMetric,
              let ageGroup = selectedAgeGroup else { return }

        do {
            let result = try await sensorBio.fetchPopulationInsights(
                ageStart: ageGroup.ageStart,
                ageEnd: ageGroup.ageEnd,
                gender: selectedGender,
                metricType: metric.metricType
            )
            guard activePopulationRequestID == requestID else { return }
            populationHistogram = result.histogram
            populationRadarChart = result.radarChart
        } catch {
            guard activePopulationRequestID == requestID else { return }
            populationHistogram = nil
            populationRadarChart = nil
            populationError = populationErrorMessage(for: error)
        }
    }

    @MainActor
    func retryPopulation() async {
        populationFilters = nil
        selectedPopulationMetric = nil
        selectedAgeGroup = nil
        await loadPopulation()
    }

    func populationErrorMessage(for error: Error) -> String {
        guard let authError = error as? SB_AuthError else {
            return "Population comparison is temporarily unavailable. Pull to refresh or try again."
        }

        switch authError {
        case .missingAuthToken:
            return "Sign in to compare your signals with population data."
        case .tokenRefreshFailed, .refreshTokenExpired:
            return "Your sign-in has expired. Open Profile, sign out, and sign back in before trying again."
        case .unexpectedNilResponse:
            return "Population data did not return a complete response. Please try again."
        @unknown default:
            return "Population comparison is temporarily unavailable. Please try again."
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
