import Foundation
import Observation
import Security
import SensorBioSDK

@Observable
final class DashboardState {
    var data: SB_DashboardData? = nil
    var personalInsights: SB_NewInsights? = nil
    var weeklyRecovery: SB_RecoveryRangeTrending? = nil
    var weeklySleep: SB_SleepDetailAggregated? = nil
    var nightlySleep: SB_SleepDetailDay? = nil
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

        nightlySleep = nil
        if let sleepSession = data?.sleeps.first {
            do {
                let endDate = Date(timeIntervalSince1970: TimeInterval(sleepSession.endTimestamp) / 1000)
                nightlySleep = try await sensorBio.fetchSleepDetail(endDate: endDate, endTimestamp: Int64(sleepSession.endTimestamp))
            } catch {
                nightlySleep = nil
            }
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

    static let eveningReset = ProductLoopSuggestion(
        demoCatalogId: "evening-reset-v1",
        title: "Try an evening reset",
        reason: "This three-night demo helps you see how a small, repeatable routine can be tracked over time.",
        instructions: "For three nights, choose a wind-down time, silence nonessential notifications, and keep the last hour before bed low intensity.",
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

    func propose(_ suggestion: ProductLoopSuggestion) async {
        guard activeExperiment == nil, proposedExperiment == nil else { return }
        await save {
            let payload: [String: Any] = [
                "demoCatalogId": suggestion.demoCatalogId
            ]
            let experiment: ProductLoopExperiment = try await ProductLoopAPI.shared.request(path: "/demo/v1/proposals", method: "POST", body: payload)
            self.current = ProductLoopCurrent(active: nil, proposals: [experiment])
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
        (error as? LocalizedError)?.errorDescription ?? "Suggested Experiments are temporarily unavailable."
    }
}

struct ProductLoopPreferenceSaved: Decodable { let id: String; enum CodingKeys: String, CodingKey { case id = "_id" } }
private struct ProductLoopAPIFailure: Decodable { let error: String }
