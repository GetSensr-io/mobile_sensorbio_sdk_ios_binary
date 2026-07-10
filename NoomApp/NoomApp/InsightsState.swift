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
        } catch {
            populationError = error.localizedDescription
        }
    }

    @MainActor
    func loadPopulation() async {
        if populationFilters == nil {
            await loadFilters()
        }
        guard let metric = selectedPopulationMetric, let ageGroup = selectedAgeGroup else { return }
        isLoadingPopulation = true
        populationError = nil
        defer { isLoadingPopulation = false }
        do {
            let result = try await sensorBio.fetchPopulationInsights(
                ageStart: ageGroup.ageStart,
                ageEnd: ageGroup.ageEnd,
                gender: selectedGender,
                metricType: metric.metricType
            )
            populationHistogram = result.histogram
            populationRadarChart = result.radarChart
        } catch {
            populationError = error.localizedDescription
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
