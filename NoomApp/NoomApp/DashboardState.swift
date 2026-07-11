import Foundation
import Observation
import Security
import SensorBioSDK

struct DashboardSnapshot {
    let date: Date
    let data: SB_DashboardData
    let personalInsights: SB_NewInsights?
    let weeklyRecovery: SB_RecoveryRangeTrending?
    let weeklySleep: SB_SleepDetailAggregated?
    let nightlySleep: SB_SleepDetailDay?
    let inflammationSignal: InflammationSignal
    let loadedAt: Date
    let networkStatus: SB_NetworkStatus
}

@Observable
final class DashboardState {
    static let automaticRefreshInterval: TimeInterval = 60

    private(set) var snapshot: DashboardSnapshot?
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var personalInsightsError: String? = nil
    var progressError: String? = nil
    private var activeRequestID: UUID?
    private let inflammationSignalProvider = MockInflammationSignalProvider()

    var data: SB_DashboardData? { snapshot?.data }
    var personalInsights: SB_NewInsights? { snapshot?.personalInsights }
    var weeklyRecovery: SB_RecoveryRangeTrending? { snapshot?.weeklyRecovery }
    var weeklySleep: SB_SleepDetailAggregated? { snapshot?.weeklySleep }
    var nightlySleep: SB_SleepDetailDay? { snapshot?.nightlySleep }
    var inflammationSignal: InflammationSignal {
        snapshot?.inflammationSignal ?? .unavailable(for: snapshot?.date ?? .now)
    }
    var loadedAt: Date? { snapshot?.loadedAt }
    var networkStatus: SB_NetworkStatus { snapshot?.networkStatus ?? sensorBio.networkStatus }

    @MainActor
    func load(date: Date, force: Bool = false) async {
        guard !force, let currentSnapshot = snapshotForSameDay(as: date) else {
            await performLoad(date: date)
            return
        }
        guard Date().timeIntervalSince(currentSnapshot.loadedAt) < Self.automaticRefreshInterval else {
            await performLoad(date: date)
            return
        }
    }

    @MainActor
    private func performLoad(date: Date) async {
        let requestID = UUID()
        activeRequestID = requestID
        let previousSnapshot = snapshotForSameDay(as: date)
        if previousSnapshot == nil {
            snapshot = nil
        }
        isLoading = true
        errorMessage = nil
        personalInsightsError = nil
        progressError = nil
        defer {
            if activeRequestID == requestID {
                isLoading = false
            }
        }

        let tzOffset = Int32(TimeZone.current.secondsFromGMT(for: date))
        let nextData: SB_DashboardData

        do {
            nextData = try await sensorBio.fetchDashboardData(date: date, tzOffset: tzOffset)
        } catch {
            guard activeRequestID == requestID else { return }
            errorMessage = error.localizedDescription
            return
        }

        var nextNightlySleep = previousSnapshot?.nightlySleep
        if let sleepSession = nextData.sleeps.first {
            do {
                let endDate = Date(timeIntervalSince1970: TimeInterval(sleepSession.endTimestamp) / 1000)
                nextNightlySleep = try await sensorBio.fetchSleepDetail(endDate: endDate, endTimestamp: Int64(sleepSession.endTimestamp))
            } catch {
                // Keep the last complete same-day sleep detail during a transient refresh failure.
            }
        } else {
            nextNightlySleep = nil
        }

        var nextPersonalInsights = previousSnapshot?.personalInsights
        var nextPersonalInsightsError: String?
        do {
            nextPersonalInsights = try await sensorBio.fetchNewInsights()
        } catch SB_InsightError.notEnoughSessions {
            nextPersonalInsights = nil
        } catch {
            nextPersonalInsightsError = error.localizedDescription
        }

        var nextWeeklyRecovery = previousSnapshot?.weeklyRecovery
        var nextProgressError: String?
        do {
            nextWeeklyRecovery = try await sensorBio.fetchRangeRecovery(date: date, granularity: .week)
        } catch {
            nextProgressError = error.localizedDescription
        }

        var nextWeeklySleep = previousSnapshot?.weeklySleep
        do {
            nextWeeklySleep = try await sensorBio.fetchSleepAggregation(date: date, granularity: .week)
        } catch {
            if nextProgressError == nil {
                nextProgressError = error.localizedDescription
            }
        }

        guard activeRequestID == requestID, !Task.isCancelled else { return }
        personalInsightsError = nextPersonalInsightsError
        progressError = nextProgressError
        snapshot = DashboardSnapshot(
            date: date,
            data: nextData,
            personalInsights: nextPersonalInsights,
            weeklyRecovery: nextWeeklyRecovery,
            weeklySleep: nextWeeklySleep,
            nightlySleep: nextNightlySleep,
            inflammationSignal: inflammationSignalProvider.signal(for: date),
            loadedAt: Date(),
            networkStatus: sensorBio.networkStatus
        )
    }

    private func snapshotForSameDay(as date: Date, calendar: Calendar = .current) -> DashboardSnapshot? {
        guard let snapshot, calendar.isDate(snapshot.date, inSameDayAs: date) else { return nil }
        return snapshot
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

struct ProductLoopExperiment: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let title: String
    let reason: String
    let instructions: String
    let expectedDurationDays: Int

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, title, reason, instructions, expectedDurationDays
    }
}

struct ProductLoopCurrent: Codable, Equatable {
    let active: ProductLoopExperiment?
    let proposals: [ProductLoopExperiment]
}

struct ProductLoopSuggestion {
    let demoCatalogId: String
    let title: String
    let reason: String
    let instructions: String
    let expectedDurationDays: Int

    static let prelogLunch = ProductLoopSuggestion(
        demoCatalogId: "prelog-lunch-v1",
        title: "Pre-log tomorrow's lunch",
        reason: "Planning one meal in Noom before the day starts makes the choice concrete while keeping it easy to change.",
        instructions: "For three days, open Noom after dinner and pre-log tomorrow's lunch. Adjust the entry later if your plan changes.",
        expectedDurationDays: 3
    )
}

@MainActor
@Observable
final class ProductLoopStore {
    var current: ProductLoopCurrent? = nil
    var isLoading = false
    var isSaving = false
    var errorMessage: String? = nil
    var lastSyncedAt: Date? = nil

    var activeExperiment: ProductLoopExperiment? { current?.active }
    var proposedExperiment: ProductLoopExperiment? { current?.proposals.first }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            current = try await ProductLoopAPI.shared.request(path: "/demo/v1/current", method: "GET", body: nil)
            errorMessage = nil
            lastSyncedAt = Date()
        } catch {
            errorMessage = ProductLoopAPI.displayError(error)
        }
    }

    func start(_ suggestion: ProductLoopSuggestion) async {
        guard activeExperiment == nil else { return }
        await save {
            let experiment: ProductLoopExperiment
            if let proposed = self.proposedExperiment {
                experiment = proposed
            } else {
                let payload: [String: Any] = ["demoCatalogId": suggestion.demoCatalogId]
                experiment = try await ProductLoopAPI.shared.request(path: "/demo/v1/proposals", method: "POST", body: payload)
            }

            if experiment.status == "active" {
                self.current = ProductLoopCurrent(active: experiment, proposals: [])
                return
            }
            guard experiment.status == "proposed" else { throw ProductLoopAPIError.unavailable }

            let payload: [String: Any] = ["experimentId": experiment.id, "idempotencyKey": UUID().uuidString]
            let active: ProductLoopExperiment = try await ProductLoopAPI.shared.request(path: "/demo/v1/experiments/accept", method: "POST", body: payload)
            guard active.status == "active" else { throw ProductLoopAPIError.unavailable }
            self.current = ProductLoopCurrent(active: active, proposals: [])
        }
    }

    func accept(_ experiment: ProductLoopExperiment) async {
        await transition(experiment, path: "/demo/v1/experiments/accept")
    }

    func complete(_ experiment: ProductLoopExperiment) async {
        await transition(experiment, path: "/demo/v1/experiments/complete")
    }

    func cancel(_ experiment: ProductLoopExperiment) async {
        await transition(experiment, path: "/demo/v1/experiments/cancel")
    }

    private func transition(_ experiment: ProductLoopExperiment, path: String) async {
        await save {
            let payload: [String: Any] = ["experimentId": experiment.id, "idempotencyKey": UUID().uuidString]
            let next: ProductLoopExperiment? = try await ProductLoopAPI.shared.request(path: path, method: "POST", body: payload)
            if next?.status == "active" { self.current = ProductLoopCurrent(active: next, proposals: []) }
            else { self.current = ProductLoopCurrent(active: nil, proposals: []) }
        }
    }

    private func save(_ operation: @escaping () async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
            errorMessage = nil
            lastSyncedAt = Date()
        } catch {
            errorMessage = ProductLoopAPI.displayError(error)
        }
    }
}

enum ProductLoopAPIError: LocalizedError {
    case unavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Suggested Experiments are temporarily unavailable. Your Body Status stays on this device."
        case .server(let message): return message
        }
    }
}

private enum DemoInstallIdentityError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Demo storage is unavailable on this device."
    }
}

private enum DemoInstallIdentity {
    private static let service = "ai.sensr.example.NoomApp.demo"
    private static let account = "installation-id"
    private static let serverCompatiblePattern = try! NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        options: [.caseInsensitive]
    )

    static func isServerCompatible(_ identifier: String) -> Bool {
        let range = NSRange(identifier.startIndex..., in: identifier)
        return serverCompatiblePattern.firstMatch(in: identifier, options: [], range: range) != nil
    }

    static func value() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let lookupStatus = SecItemCopyMatching(query as CFDictionary, &result)
        if lookupStatus == errSecSuccess,
           let data = result as? Data,
           let identifier = String(data: data, encoding: .utf8),
           isServerCompatible(identifier) {
            return identifier.lowercased()
        }

        let identifier = UUID().uuidString.lowercased()
        let valueData = Data(identifier.utf8)
        if lookupStatus == errSecSuccess {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: valueData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw DemoInstallIdentityError.unavailable }
            return identifier
        }
        guard lookupStatus == errSecItemNotFound else { throw DemoInstallIdentityError.unavailable }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess { return identifier }
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: valueData] as CFDictionary
            )
            if updateStatus == errSecSuccess { return identifier }
        }
        throw DemoInstallIdentityError.unavailable
    }
}

actor ProductLoopAPI {
    static let shared = ProductLoopAPI()
    private let decoder = JSONDecoder()

    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ProductLoopEndpoint") as? String else { return nil }
        return URL(string: raw)
    }

    func request<T: Decodable>(path: String, method: String, body: [String: Any]?) async throws -> T {
        guard let endpoint else { throw ProductLoopAPIError.unavailable }
        guard let url = URL(string: path, relativeTo: endpoint) else { throw ProductLoopAPIError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(try DemoInstallIdentity.value(), forHTTPHeaderField: "X-Noom-Demo-Install-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProductLoopAPIError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ProductLoopAPIFailure.self, from: data).error) ?? "Suggested Experiments could not be saved."
            throw ProductLoopAPIError.server(message)
        }
        return try decoder.decode(T.self, from: data)
    }

    nonisolated static func displayError(_ error: Error) -> String {
        "Couldn’t update this experiment. Try again."
    }
}

struct ProductLoopPreferenceSaved: Decodable { let id: String; enum CodingKeys: String, CodingKey { case id = "_id" } }
private struct ProductLoopAPIFailure: Decodable { let error: String }
