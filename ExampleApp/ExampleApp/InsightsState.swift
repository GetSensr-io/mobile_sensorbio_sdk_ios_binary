import Foundation
import Observation
import SensorBioSDK

@Observable
final class InsightsState {
    var personal: SB_NewInsights?
    var personalError: String?
    var isLoadingPersonal: Bool = false

    var filterList: SB_PopulationInsightsFilterList?

    var selectedGender: SB_PopulationGender = .all
    /// Tagged by `ageStart` because `SB_PopulationAgeGroup` is not Hashable.
    var selectedAgeStart: Int32 = -1
    /// Tagged by `metricType` because `SB_PopulationInsightMetric` is not Hashable.
    var selectedMetricType: SB_PopulationMetricType = .unknown

    var populationHistogram: SB_PopulationInsightsHistogram?
    var populationRadar: SB_PopulationInsightsRadarChart?
    var populationError: String?
    var isLoadingPopulation: Bool = false

    var selectedAgeGroup: SB_PopulationAgeGroup? {
        filterList?.ageGroups.first { $0.ageStart == selectedAgeStart }
    }

    var selectedMetric: SB_PopulationInsightMetric? {
        filterList?.metrics.first { $0.metricType == selectedMetricType }
    }

    @MainActor
    func loadPersonal() async {
        isLoadingPersonal = true
        personalError = nil
        defer { isLoadingPersonal = false }
        do {
            personal = try await sensorBio.fetchNewInsights()
        } catch SB_InsightError.notEnoughSessions(let msg) {
            personalError = msg.isEmpty ? "Not enough sessions yet for personal insights." : msg
            personal = nil
        } catch {
            personalError = error.localizedDescription
        }
    }

    @MainActor
    func loadFilters() async {
        do {
            let list = try await sensorBio.fetchPopulationInsightsMetricList()
            filterList = list
            if selectedAgeStart == -1, let first = list.ageGroups.first {
                selectedAgeStart = first.ageStart
            }
            if selectedMetricType == .unknown, let first = list.metrics.first {
                selectedMetricType = first.metricType
            }
        } catch {
            populationError = error.localizedDescription
        }
    }

    @MainActor
    func loadPopulation() async {
        guard let age = selectedAgeGroup, let metric = selectedMetric else { return }
        isLoadingPopulation = true
        populationError = nil
        defer { isLoadingPopulation = false }
        do {
            let result = try await sensorBio.fetchPopulationInsights(
                ageStart: age.ageStart,
                ageEnd: age.ageEnd,
                gender: selectedGender,
                metricType: metric.metricType
            )
            populationHistogram = result.histogram
            populationRadar = result.radarChart
        } catch {
            populationError = error.localizedDescription
            populationHistogram = nil
            populationRadar = nil
        }
    }
}
