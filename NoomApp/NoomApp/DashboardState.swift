import Foundation
import Observation
import SensorBioSDK

@Observable
final class DashboardState {
    var data: SB_DashboardData? = nil
    var personalInsights: SB_NewInsights? = nil
    var weeklyRecovery: SB_RecoveryRangeTrending? = nil
    var weeklySleep: SB_SleepDetailAggregated? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var personalInsightsError: String? = nil
    var progressError: String? = nil
    var loadedAt: Date? = nil
    var networkStatus: SB_NetworkStatus = sensorBio.networkStatus

    @MainActor
    func load(date: Date) async {
        isLoading = true
        errorMessage = nil
        personalInsightsError = nil
        progressError = nil
        loadedAt = nil
        networkStatus = sensorBio.networkStatus
        defer { isLoading = false }

        let tzOffset = Int32(TimeZone.current.secondsFromGMT(for: date))

        do {
            data = try await sensorBio.fetchDashboardData(date: date, tzOffset: tzOffset)
            loadedAt = Date()
        } catch {
            data = nil
            errorMessage = error.localizedDescription
        }

        do {
            personalInsights = try await sensorBio.fetchNewInsights()
        } catch SB_InsightError.notEnoughSessions {
            personalInsights = nil
        } catch {
            personalInsights = nil
            personalInsightsError = error.localizedDescription
        }

        do {
            weeklyRecovery = try await sensorBio.fetchRangeRecovery(date: date, granularity: .week)
        } catch {
            weeklyRecovery = nil
            progressError = error.localizedDescription
        }

        do {
            weeklySleep = try await sensorBio.fetchSleepAggregation(date: date, granularity: .week)
        } catch {
            weeklySleep = nil
            if progressError == nil {
                progressError = error.localizedDescription
            }
        }
    }

    func freshness(for selectedDate: Date, calendar: Calendar = .current) -> NoomDataFreshness {
        guard calendar.isDateInToday(selectedDate) else {
            return .historical(date: selectedDate)
        }
        let lastSync = sensorBio.lastSyncd
        guard lastSync.timeIntervalSince1970 > 0 else {
            return .unknownCurrentDay
        }
        if calendar.isDateInToday(lastSync) {
            return .fresh(lastSync: lastSync)
        }
        return .stale(lastSync: lastSync)
    }
}

enum NoomDataFreshness: Equatable {
    case fresh(lastSync: Date)
    case stale(lastSync: Date)
    case historical(date: Date)
    case unknownCurrentDay

    var isStaleCurrentDay: Bool {
        if case .stale = self { return true }
        if case .unknownCurrentDay = self { return true }
        return false
    }
}
