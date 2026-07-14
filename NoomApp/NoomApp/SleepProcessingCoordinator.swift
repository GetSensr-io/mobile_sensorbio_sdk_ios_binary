import Combine
import CryptoKit
import Foundation
import Observation
import Security
import SensorBioSDK
import UserNotifications

struct SleepProcessingConfiguration: Equatable, Sendable {
    let eventDebounce: Duration
    let pollInterval: Duration
    let maxPollAttempts: Int
    let maximumForegroundReconciliationDuration: Duration
    let maxCorrelationDistanceMilliseconds: Int64

    init(
        eventDebounce: Duration,
        pollInterval: Duration,
        maxPollAttempts: Int,
        maximumForegroundReconciliationDuration: Duration,
        maxCorrelationDistanceMilliseconds: Int64
    ) {
        self.eventDebounce = eventDebounce
        self.pollInterval = pollInterval
        self.maxPollAttempts = max(1, maxPollAttempts)
        self.maximumForegroundReconciliationDuration = maximumForegroundReconciliationDuration
        self.maxCorrelationDistanceMilliseconds = maxCorrelationDistanceMilliseconds
    }

    static let production = SleepProcessingConfiguration(
        eventDebounce: .milliseconds(250),
        pollInterval: .seconds(2),
        maxPollAttempts: 8,
        maximumForegroundReconciliationDuration: .seconds(60),
        maxCorrelationDistanceMilliseconds: 30 * 60 * 1_000
    )
}

struct SleepDetectedSignal: Equatable, Sendable {
    let startEpochMilliseconds: Int64
    let endEpochMilliseconds: Int64
}

struct SleepPendingCandidateMetadata: Codable, Equatable, Sendable {
    let localDay: SleepLocalDay
    let candidateGeneration: UInt64
    let provisionalEndTimestampMilliseconds: Int64
    let boundSessionIdentity: SleepSessionIdentity?
    let retryAttempt: Int
    let isRetryExhausted: Bool
}

struct SleepCompletedIdentityMetadata: Codable, Equatable, Sendable {
    let localDay: SleepLocalDay
    let sessionIdentity: SleepSessionIdentity
}

/// Versioned lifecycle metadata only. It must never contain SDK sleep detail,
/// scores, stages, heart rate, HRV, or raw account identity.
struct SleepPendingMetadataEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let accountScopeHash: String
    let selectedDay: SleepLocalDay?
    let selectedSessionIdentity: SleepSessionIdentity?
    let pendingCandidates: [SleepPendingCandidateMetadata]
    let lastCompletedIdentity: SleepCompletedIdentityMetadata?
    let savedAtEpochSeconds: Int64
}

protocol SleepPendingMetadataStoring {
    func load(accountScopeHash: String) throws -> SleepPendingMetadataEnvelope?
    func save(_ envelope: SleepPendingMetadataEnvelope) throws
    func clear(accountScopeHash: String) throws
}

struct SleepKeychainMetadataStore: SleepPendingMetadataStoring {
    private let service = "com.sensorbio.noomplus.sleep-processing"

    func load(accountScopeHash: String) throws -> SleepPendingMetadataEnvelope? {
        var query = baseQuery(accountScopeHash: accountScopeHash)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SleepProtectedStorageError.readFailed(status)
        }
        let envelope = try JSONDecoder().decode(SleepPendingMetadataEnvelope.self, from: data)
        guard
            envelope.version == SleepPendingMetadataEnvelope.currentVersion,
            envelope.accountScopeHash == accountScopeHash
        else {
            throw SleepProtectedStorageError.invalidEnvelope
        }
        return envelope
    }

    func save(_ envelope: SleepPendingMetadataEnvelope) throws {
        guard
            envelope.version == SleepPendingMetadataEnvelope.currentVersion,
            !envelope.accountScopeHash.isEmpty
        else {
            throw SleepProtectedStorageError.invalidEnvelope
        }
        let data = try JSONEncoder().encode(envelope)
        let query = baseQuery(accountScopeHash: envelope.accountScopeHash)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SleepProtectedStorageError.writeFailed(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw SleepProtectedStorageError.writeFailed(insertStatus)
        }
    }

    func clear(accountScopeHash: String) throws {
        let status = SecItemDelete(baseQuery(accountScopeHash: accountScopeHash) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SleepProtectedStorageError.deleteFailed(status)
        }
    }

    private func baseQuery(accountScopeHash: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountScopeHash,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

enum SleepProtectedStorageError: Error, Equatable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidEnvelope
}

enum SleepNotificationAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

struct SleepCompletionNotification: Equatable, Sendable {
    let identifier: String
    let localDay: SleepLocalDay
    let sessionIdentity: SleepSessionIdentity
}

struct SleepCompletionNotifier: Sendable {
    var authorizationStatus: @Sendable () async -> SleepNotificationAuthorizationStatus
    var deliver: @Sendable (SleepCompletionNotification) async -> Void
    var clear: @Sendable (String) async -> Void
}

struct SleepCompletionNotificationCenter {
    private let center: UNUserNotificationCenter
    private let identifierPrefix = "noom.sleep.ready."

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> SleepNotificationAuthorizationStatus {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func deliver(_ notification: SleepCompletionNotification) async {
        let content = UNMutableNotificationContent()
        content.title = "Sleep analysis ready"
        content.body = "Your Noom+ sleep analysis is ready to review."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        try? await add(request)
    }

    func clear(accountScopeHash: String) async {
        let prefix = "\(identifierPrefix)\(accountScopeHash)."
        let pending = await pendingRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !pending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
        let delivered = await deliveredNotifications()
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(prefix) }
        if !delivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { continuation.resume(returning: $0) }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct SleepProtectedMetadataStore: Sendable {
    var load: @Sendable (String) async throws -> Data?
    var save: @Sendable (String, Data) async throws -> Void
    var clear: @Sendable (String) async throws -> Void
}

@MainActor
struct SleepProcessingDependencies {
    var fetchSessions: (SleepSessionsRequestKey) async throws -> [SleepSessionSummary]
    var fetchDetail: (SleepRequestKey) async throws -> SB_SleepDetailDay
    var sleep: (Duration) async throws -> Void
    var monotonicNow: () async -> Duration
    var metadataStore: SleepProtectedMetadataStore
    var completionNotifier: SleepCompletionNotifier
    var wallClockNow: () -> Date

    init(
        fetchSessions: @escaping (SleepSessionsRequestKey) async throws -> [SleepSessionSummary],
        fetchDetail: @escaping (SleepRequestKey) async throws -> SB_SleepDetailDay,
        sleep: @escaping (Duration) async throws -> Void,
        monotonicNow: @escaping () async -> Duration,
        metadataStore: SleepProtectedMetadataStore,
        completionNotifier: SleepCompletionNotifier,
        wallClockNow: @escaping () -> Date = Date.init
    ) {
        self.fetchSessions = fetchSessions
        self.fetchDetail = fetchDetail
        self.sleep = sleep
        self.monotonicNow = monotonicNow
        self.metadataStore = metadataStore
        self.completionNotifier = completionNotifier
        self.wallClockNow = wallClockNow
    }

    static func live() -> SleepProcessingDependencies {
        let keychain = SleepKeychainMetadataStore()
        let notifications = SleepCompletionNotificationCenter()
        let clock = ContinuousClock()
        let origin = clock.now
        return SleepProcessingDependencies(
            fetchSessions: { key in
                try await sensorBio.fetchSleepSessions(date: date(from: key.localDay))
                    .map(SleepSessionSummary.init(item:))
            },
            fetchDetail: { key in
                try await sensorBio.fetchSleepDetail(
                    endDate: date(from: key.sessionIdentity),
                    endTimestamp: key.sessionIdentity.endTimestamp,
                    forceRemote: true
                )
            },
            sleep: { duration in
                try await Task.sleep(for: duration)
            },
            monotonicNow: {
                origin.duration(to: clock.now)
            },
            metadataStore: SleepProtectedMetadataStore(
                load: { accountScopeHash in
                    guard let envelope = try keychain.load(accountScopeHash: accountScopeHash) else {
                        return nil
                    }
                    return try JSONEncoder().encode(envelope)
                },
                save: { accountScopeHash, data in
                    let envelope = try JSONDecoder().decode(
                        SleepPendingMetadataEnvelope.self,
                        from: data
                    )
                    guard envelope.accountScopeHash == accountScopeHash else {
                        throw SleepProtectedStorageError.invalidEnvelope
                    }
                    try keychain.save(envelope)
                },
                clear: { accountScopeHash in
                    try keychain.clear(accountScopeHash: accountScopeHash)
                }
            ),
            completionNotifier: SleepCompletionNotifier(
                authorizationStatus: {
                    await notifications.authorizationStatus()
                },
                deliver: { notification in
                    await notifications.deliver(notification)
                },
                clear: { accountScopeHash in
                    await notifications.clear(accountScopeHash: accountScopeHash)
                }
            )
        )
    }

    private static func date(from localDay: SleepLocalDay) -> Date {
        let raw = Int(localDay.rawValue)
        return Calendar.current.date(from: DateComponents(
            year: raw / 10_000,
            month: (raw / 100) % 100,
            day: raw % 100,
            hour: 12
        )) ?? Date(timeIntervalSince1970: 0)
    }

    private static func date(from identity: SleepSessionIdentity) -> Date {
        let raw = Int(identity.endDate)
        let year = raw / 10_000
        let month = (raw / 100) % 100
        let day = raw % 100
        let seconds = Int(identity.timezoneMinutes) * 60
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: seconds) ?? .gmt
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        )) ?? Date(timeIntervalSince1970: TimeInterval(identity.endTimestamp) / 1_000)
    }
}

@MainActor
@Observable
final class SleepProcessingCoordinator {
    private(set) var journey: SleepJourneyState
    private(set) var selectedDate: Date
    private(set) var isForeground: Bool
    private(set) var reconciliationAttempt = 0
    private(set) var isReconciliationExhausted = false

    @ObservationIgnored private let dependencies: SleepProcessingDependencies
    @ObservationIgnored private let configuration: SleepProcessingConfiguration
    @ObservationIgnored private var lifecycleCancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var reconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var accountLifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var metadataSaveTask: Task<Void, Never>?
    @ObservationIgnored private var accountCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var debouncedReconciliationPending = false
    @ObservationIgnored private var reconciliationScheduledOrRunning = false
    @ObservationIgnored private var reconciliationTaskGeneration: UInt64 = 0

    init(
        dependencies: SleepProcessingDependencies? = nil,
        configuration: SleepProcessingConfiguration = .production,
        selectedDate: Date = Date(),
        isForeground: Bool = true,
        subscribeToSDKLifecycle: Bool = true
    ) {
        self.dependencies = dependencies ?? .live()
        self.configuration = configuration
        self.selectedDate = selectedDate
        self.isForeground = isForeground
        self.journey = SleepJourneyState(accountScope: nil, selectedDay: nil)
        if subscribeToSDKLifecycle {
            bindSDKLifecycle()
        }
    }

    var state: SleepJourneyState { journey }
    var rootState: SleepJourneyState { journey }
    var selectedSnapshot: SleepAtomicSnapshot? { journey.selectedSnapshot }
    var lastCompleted: SleepAtomicSnapshot? { journey.lastCompleted }
    var displaySnapshot: SleepAtomicSnapshot? { journey.displaySnapshot }
    var sessions: [SleepSessionSummary] { journey.allSessions }
    var allSessions: [SleepSessionSummary] { journey.allSessions }
    var selectedSession: SleepSessionSummary? { journey.selection.selectedSession }
    var selectionReason: SleepSessionSelection.Reason? { journey.selection.reason }
    var phase: SleepProcessingPresentationPhase {
        SleepProcessingPresentationPhase(journey.pipelineState.phase)
    }
    var transport: SleepTransportState { journey.transport }
    var freshness: SleepFreshness { journey.freshness }

    var sourceDate: Date? {
        journey.displaySnapshot.map { date(from: $0.sourceDay) }
    }

    var canRetry: Bool {
        isReconciliationExhausted
            || journey.transport == .failed
            || journey.pipelineState.phase == .retryableError
    }

    var bodyStatusSleepDetail: SB_SleepDetailDay? {
        guard
            let snapshot = journey.displaySnapshot,
            snapshot.permitsBodyStatus(
                forAccountScope: snapshot.accountScope,
                localDay: snapshot.sourceDay,
                sessionIdentity: snapshot.sessionIdentity
            )
        else {
            return nil
        }
        return snapshot.detail
    }

    func setAccountIdentifier(_ identifier: String?) {
        setAccountScope(identifier)
        guard identifier != nil else { return }
        selectDay(localDay(for: selectedDate))
    }

    func setAccountScope(_ accountScope: String?) {
        let normalized = accountScope?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextScope = normalized.flatMap { $0.isEmpty ? nil : $0 }
        guard nextScope != journey.accountScope else { return }
        accountLifecycleTask?.cancel()
        accountLifecycleTask = nil
        let commands = journey.setAccountScope(nextScope)
        execute(commands)
        guard let nextScope else { return }
        restoreAndReconcile(accountScope: nextScope)
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        selectDay(localDay(for: date))
    }

    func selectDay(_ day: SleepLocalDay) {
        guard journey.accountScope != nil else { return }
        selectedDate = date(from: day)
        execute(journey.selectDay(day))
    }

    func selectSession(_ identity: SleepSessionIdentity) {
        execute(journey.selectSession(identity))
        scheduleMetadataSave()
    }

    func setForeground(_ foreground: Bool) {
        guard isForeground != foreground else { return }
        isForeground = foreground
        if foreground {
            requestReconciliation(debounced: false, forceRemote: true)
        } else {
            reconciliationTaskGeneration &+= 1
            reconciliationTask?.cancel()
            reconciliationTask = nil
            debouncedReconciliationPending = false
            reconciliationScheduledOrRunning = false
        }
    }

    func receiveDetectedSleep(_ signal: SleepDetectedSignal) {
        guard signal.endEpochMilliseconds > 0 else {
            receiveVoidSignal(.sync)
            return
        }
        let endDate = Date(
            timeIntervalSince1970: TimeInterval(signal.endEpochMilliseconds) / 1_000
        )
        receiveDetectedSleep(
            localDay: localDay(for: endDate),
            provisionalEndTimestampMilliseconds: signal.endEpochMilliseconds
        )
    }

    func receiveDetectedSleep(
        localDay: SleepLocalDay,
        provisionalEndTimestampMilliseconds: Int64
    ) {
        execute(journey.recordDetectedSleep(
            localDay: localDay,
            provisionalEndTimestampMilliseconds: provisionalEndTimestampMilliseconds
        ))
        scheduleMetadataSave()
    }

    func receiveVoidSignal(_ signal: SleepVoidPipelineSignal) {
        receiveVoidPipelineSignal(signal)
    }

    func receiveVoidPipelineSignal(_ signal: SleepVoidPipelineSignal) {
        execute(journey.receiveVoidPipelineSignal(signal))
        scheduleMetadataSave()
    }

    func refresh(forceRemote: Bool = true) {
        requestReconciliation(debounced: false, forceRemote: forceRemote)
    }

    func retry() {
        retry(candidateKey: nil)
    }

    func retry(candidateKey: SleepCandidateKey?) {
        let commands: [SleepJourneyCommand]
        if let candidateKey {
            commands = journey.retry(candidateKey: candidateKey)
            guard !commands.isEmpty else { return }
        } else if let firstPending = journey.pendingCandidates.keys.sorted(by: {
            if $0.localDay != $1.localDay {
                return $0.localDay.rawValue < $1.localDay.rawValue
            }
            return $0.candidateGeneration < $1.candidateGeneration
        }).first {
            commands = journey.retry(candidateKey: firstPending)
        } else {
            commands = []
        }
        isReconciliationExhausted = false
        reconciliationAttempt = 0
        execute(commands)
        scheduleMetadataSave()
        requestReconciliation(debounced: false, forceRemote: true)
    }

    func waitForEffects() async {
        for _ in 0..<4 {
            await accountLifecycleTask?.value
            await reconciliationTask?.value
            await metadataSaveTask?.value
            await accountCleanupTask?.value
            await Task.yield()
        }
    }

    private func bindSDKLifecycle() {
        sensorBio.sleepDetected
            .sink { [weak self] detected in
                Task { @MainActor [weak self] in
                    self?.receiveDetectedSleep(SleepDetectedSignal(
                        startEpochMilliseconds: detected.startEpochInms,
                        endEpochMilliseconds: detected.endEpochms
                    ))
                }
            }
            .store(in: &lifecycleCancellables)

        sensorBio.sleepStored
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.receiveVoidPipelineSignal(.stored)
                }
            }
            .store(in: &lifecycleCancellables)

        sensorBio.sleepUploaded
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.receiveVoidPipelineSignal(.uploaded)
                }
            }
            .store(in: &lifecycleCancellables)

        sensorBio.syncCompleted
            .compactMap { result in
                result?.acknowledge == true ? () : nil
            }
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    self?.receiveVoidPipelineSignal(.sync)
                }
            }
            .store(in: &lifecycleCancellables)
    }

    private func execute(_ commands: [SleepJourneyCommand]) {
        for command in commands {
            switch command {
            case .cancelRequests:
                reconciliationTaskGeneration &+= 1
                reconciliationTask?.cancel()
                reconciliationTask = nil
                debouncedReconciliationPending = false
                reconciliationScheduledOrRunning = false
            case let .clearPersistedMetadata(accountScope):
                guard let hash = Self.accountScopeHash(accountScope) else { continue }
                let store = dependencies.metadataStore
                let notifier = dependencies.completionNotifier
                let priorSave = metadataSaveTask
                let priorCleanup = accountCleanupTask
                let task = Task {
                    await priorSave?.value
                    await priorCleanup?.value
                    try? await store.clear(hash)
                    await notifier.clear(hash)
                }
                accountCleanupTask = task
            case .reconcileSessions:
                requestReconciliation(debounced: true, forceRemote: true)
            }
        }
    }

    private func restoreAndReconcile(accountScope: String) {
        accountLifecycleTask?.cancel()
        let store = dependencies.metadataStore
        accountLifecycleTask = Task { [weak self] in
            guard
                let self,
                let hash = Self.accountScopeHash(accountScope)
            else { return }
            let data = try? await store.load(hash)
            guard !Task.isCancelled, journey.accountScope == accountScope else { return }
            if
                let data,
                let persisted = try? JSONDecoder().decode(
                    SleepPendingMetadataEnvelope.self,
                    from: data
                ),
                persisted.version == SleepPendingMetadataEnvelope.currentVersion,
                persisted.accountScopeHash == hash
            {
                let restorable = SleepPendingMetadataEnvelope(
                    version: persisted.version,
                    accountScopeHash: accountScope,
                    selectedDay: persisted.selectedDay,
                    selectedSessionIdentity: persisted.selectedSessionIdentity,
                    pendingCandidates: persisted.pendingCandidates,
                    lastCompletedIdentity: persisted.lastCompletedIdentity,
                    savedAtEpochSeconds: persisted.savedAtEpochSeconds
                )
                journey.restorePendingMetadata(restorable)
                if let restoredDay = journey.selectedDay {
                    selectedDate = date(from: restoredDay)
                }
            }
            requestReconciliation(debounced: false, forceRemote: false)
        }
    }

    private func requestReconciliation(debounced: Bool, forceRemote: Bool) {
        guard journey.accountScope != nil, journey.selectedDay != nil else {
            return
        }
        if debounced && reconciliationScheduledOrRunning {
            return
        }

        reconciliationTaskGeneration &+= 1
        let taskGeneration = reconciliationTaskGeneration
        if !debounced {
            reconciliationTask?.cancel()
        }
        debouncedReconciliationPending = debounced
        reconciliationScheduledOrRunning = true

        let debounce = debounced ? configuration.eventDebounce : .zero
        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if reconciliationTaskGeneration == taskGeneration {
                    debouncedReconciliationPending = false
                    reconciliationScheduledOrRunning = false
                    reconciliationTask = nil
                }
            }
            if debounced, debounce > .zero {
                do {
                    try await dependencies.sleep(debounce)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
            }
            guard reconciliationTaskGeneration == taskGeneration else { return }
            debouncedReconciliationPending = false
            await reconcileWithBoundedPolling(forceRemote: forceRemote)
        }
    }

    private func reconcileWithBoundedPolling(forceRemote: Bool) async {
        let startedAt = await dependencies.monotonicNow()
        reconciliationAttempt = 0
        isReconciliationExhausted = false
        var lastParticipatingCandidateKeys: [SleepCandidateKey] = []

        while reconciliationAttempt < configuration.maxPollAttempts {
            guard !Task.isCancelled else { return }
            let elapsed = await dependencies.monotonicNow() - startedAt
            guard elapsed <= configuration.maximumForegroundReconciliationDuration else {
                break
            }

            reconciliationAttempt += 1
            let outcome = await reconcileOnce(forceRemote: forceRemote || reconciliationAttempt > 1)
            guard !Task.isCancelled else { return }
            lastParticipatingCandidateKeys = participatingCandidateKeys()
            journey.markPendingRetryAttempt(
                candidateKeys: lastParticipatingCandidateKeys,
                attempt: reconciliationAttempt,
                isExhausted: false
            )

            switch outcome {
            case .processedSuccessfully, .shortSession, .processedWithError,
                 .invalidDailyAggregate:
                isReconciliationExhausted = false
                scheduleMetadataSave()
                return
            case .unknown, .processing, nil:
                break
            }

            guard isForeground else {
                scheduleMetadataSave()
                return
            }
            guard reconciliationAttempt < configuration.maxPollAttempts else {
                break
            }
            let projected = (await dependencies.monotonicNow() - startedAt)
                + configuration.pollInterval
            guard projected <= configuration.maximumForegroundReconciliationDuration else {
                break
            }
            if configuration.pollInterval > .zero {
                do {
                    try await dependencies.sleep(configuration.pollInterval)
                } catch {
                    return
                }
            }
        }

        guard !Task.isCancelled, isForeground else { return }
        isReconciliationExhausted = true
        journey.markPendingRetryAttempt(
            candidateKeys: lastParticipatingCandidateKeys,
            attempt: reconciliationAttempt,
            isExhausted: true
        )
        scheduleMetadataSave()
    }

    private func participatingCandidateKeys() -> [SleepCandidateKey] {
        guard
            let accountScope = journey.accountScope,
            let selectedDay = journey.selectedDay
        else { return [] }
        let selectedIdentity = journey.selection.selectedSession?.identity
        return journey.pendingCandidates.values
            .filter { candidate in
                candidate.key.accountScope == accountScope
                    && candidate.key.localDay == selectedDay
                    && (selectedIdentity == nil
                        ? candidate.boundSessionIdentity == nil
                        : candidate.boundSessionIdentity == selectedIdentity)
            }
            .map(\.key)
            .sorted { $0.candidateGeneration < $1.candidateGeneration }
    }

    private func reconcileOnce(forceRemote: Bool) async -> SleepAnalysisOutcome? {
        guard
            let accountScope = journey.accountScope,
            let selectedDay = journey.selectedDay
        else {
            return nil
        }

        let generation = journey.requestGeneration
        let sessionsKey = SleepSessionsRequestKey(
            accountScope: accountScope,
            localDay: selectedDay,
            requestGeneration: generation
        )
        journey.setTransport(.loading)

        do {
            let sessions = try await dependencies.fetchSessions(sessionsKey)
            guard !Task.isCancelled else { return nil }
            let accepted = journey.commitSessions(
                sessions,
                for: sessionsKey,
                maxCorrelationDistanceMilliseconds: configuration.maxCorrelationDistanceMilliseconds
            )
            guard accepted else { return nil }
            journey.reconcilePendingCandidates(
                maxCorrelationDistanceMilliseconds: configuration.maxCorrelationDistanceMilliseconds
            )
            journey.setTransport(.loaded)

            guard let selectedSession = journey.selection.selectedSession else {
                scheduleMetadataSave()
                return nil
            }
            let detailKey = SleepRequestKey(
                accountScope: accountScope,
                localDay: selectedDay,
                sessionIdentity: selectedSession.identity,
                requestGeneration: generation
            )
            let detail = try await dependencies.fetchDetail(detailKey)
            guard !Task.isCancelled else { return nil }

            let mapped = map(detail)
            let snapshot = SleepAtomicSnapshot(
                accountScope: accountScope,
                localDay: selectedDay,
                sessionIdentity: selectedSession.identity,
                detail: detail,
                outcome: mapped.outcome,
                circadianAvailability: mapped.circadian,
                sourceDay: SleepLocalDay(rawValue: selectedSession.identity.endDate),
                requestGeneration: generation,
                freshness: forceRemote ? .fresh : .stale
            )
            let previousCompletedIdentity = journey.lastCompleted?.sessionIdentity
            guard journey.commitSnapshot(snapshot, for: detailKey) else { return nil }
            scheduleMetadataSave()

            if
                mapped.outcome == .processedSuccessfully,
                previousCompletedIdentity != selectedSession.identity,
                !isForeground
            {
                await notifyCompletionIfAuthorized(
                    accountScope: accountScope,
                    localDay: selectedDay,
                    sessionIdentity: selectedSession.identity
                )
            }
            return mapped.outcome
        } catch is CancellationError {
            return nil
        } catch {
            guard
                journey.accountScope == accountScope,
                journey.selectedDay == selectedDay,
                journey.requestGeneration == generation
            else {
                return nil
            }
            journey.setTransport(.failed)
            journey.setFreshness(.stale)
            scheduleMetadataSave()
            return nil
        }
    }

    private func map(_ detail: SB_SleepDetailDay) -> (
        outcome: SleepAnalysisOutcome,
        circadian: SleepCircadianAvailability
    ) {
        if detail.processing {
            return (
                .processing,
                detail.sleepScore.processState == .circadianGenerating ? .generating : .unknown
            )
        }

        switch detail.sleepScore.processState {
        case .processing:
            return (.processing, .unknown)
        case .processedSuccessfully:
            return (.processedSuccessfully, .available)
        case .aggregated:
            return (.invalidDailyAggregate, .unavailable)
        case .shortSession:
            return (.shortSession, .unavailable)
        case .processedWithError:
            return (.processedWithError, .unavailable)
        case .circadianGenerating:
            return (.processing, .generating)
        @unknown default:
            return (.processedWithError, .unavailable)
        }
    }

    private func scheduleMetadataSave() {
        guard
            let accountScope = journey.accountScope,
            let accountScopeHash = Self.accountScopeHash(accountScope)
        else { return }
        let candidates = journey.pendingCandidates.values
            .filter { $0.key.accountScope == accountScope }
            .map {
                SleepPendingCandidateMetadata(
                    localDay: $0.key.localDay,
                    candidateGeneration: $0.key.candidateGeneration,
                    provisionalEndTimestampMilliseconds:
                        $0.correlationProvisionalEndTimestampMilliseconds,
                    boundSessionIdentity: $0.boundSessionIdentity,
                    retryAttempt: $0.retryAttempt,
                    isRetryExhausted: $0.isRetryExhausted
                )
            }
            .sorted {
                if $0.localDay != $1.localDay {
                    return $0.localDay.rawValue < $1.localDay.rawValue
                }
                return $0.candidateGeneration < $1.candidateGeneration
            }
        let completed = journey.lastCompleted.map {
            SleepCompletedIdentityMetadata(
                localDay: $0.sourceDay,
                sessionIdentity: $0.sessionIdentity
            )
        }
        let envelope = SleepPendingMetadataEnvelope(
            version: SleepPendingMetadataEnvelope.currentVersion,
            accountScopeHash: accountScopeHash,
            selectedDay: journey.selectedDay,
            selectedSessionIdentity: journey.selection.selectedSession?.identity,
            pendingCandidates: candidates,
            lastCompletedIdentity: completed,
            savedAtEpochSeconds: Int64(dependencies.wallClockNow().timeIntervalSince1970)
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let store = dependencies.metadataStore
        let priorSave = metadataSaveTask
        let task = Task {
            await priorSave?.value
            try? await store.save(accountScopeHash, data)
        }
        metadataSaveTask = task
    }

    private func notifyCompletionIfAuthorized(
        accountScope: String,
        localDay: SleepLocalDay,
        sessionIdentity: SleepSessionIdentity
    ) async {
        guard
            let accountScopeHash = Self.accountScopeHash(accountScope),
            await dependencies.completionNotifier.authorizationStatus() == .authorized
        else { return }
        let rawIdentity = "\(sessionIdentity.endDate)|\(sessionIdentity.endTimestamp)|\(sessionIdentity.timezoneMinutes)"
        let digest = SHA256.hash(data: Data(rawIdentity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        await dependencies.completionNotifier.deliver(SleepCompletionNotification(
            identifier: "noom.sleep.ready.\(accountScopeHash).\(digest)",
            localDay: localDay,
            sessionIdentity: sessionIdentity
        ))
    }

    private func localDay(for date: Date) -> SleepLocalDay {
        SleepLocalDay(
            date: date,
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone.current
        )
    }

    private func date(from localDay: SleepLocalDay) -> Date {
        let raw = Int(localDay.rawValue)
        return Calendar.current.date(from: DateComponents(
            year: raw / 10_000,
            month: (raw / 100) % 100,
            day: raw % 100,
            hour: 12
        )) ?? selectedDate
    }

    static func accountScopeHash(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SHA256.hash(data: Data(trimmed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// Compatibility spellings retained for the already-migrated views/previews.
enum SleepProcessingPresentationPhase: Equatable, Sendable {
    case idle
    case detected
    case stored
    case uploaded
    case processing
    case ready
    case tooShort
    case retryableError
    case calibrating

    init(_ phase: SleepProcessingPhase) {
        switch phase {
        case .idle: self = .idle
        case .detected: self = .detected
        case .stored: self = .stored
        case .uploaded: self = .uploaded
        case .processing: self = .processing
        case .ready: self = .ready
        case .shortSession: self = .tooShort
        case .retryableError: self = .retryableError
        case .calibrating: self = .calibrating
        }
    }

    static var shortSession: SleepProcessingPresentationPhase { .tooShort }

    var domainPhase: SleepProcessingPhase {
        switch self {
        case .idle: .idle
        case .detected: .detected
        case .stored: .stored
        case .uploaded: .uploaded
        case .processing: .processing
        case .ready: .ready
        case .tooShort: .shortSession
        case .retryableError: .retryableError
        case .calibrating: .calibrating
        }
    }
}

extension SleepProcessingBanner {
    init(
        phase: SleepProcessingPresentationPhase,
        transportState: SleepTransportState,
        freshness: SleepFreshness,
        selectedDate: Date,
        sourceDate: Date? = nil,
        canRetry: Bool = false,
        retryAction: (() -> Void)? = nil
    ) {
        self.init(
            phase: phase.domainPhase,
            transportState: transportState,
            freshness: freshness,
            selectedDate: selectedDate,
            sourceDate: sourceDate,
            canRetry: canRetry,
            retryAction: retryAction
        )
    }
}

extension SleepProcessingPhase {
    static var tooShort: SleepProcessingPhase { .shortSession }
}

extension SleepFreshness {
    static var unknown: SleepFreshness { .stale }
}

extension SleepLocalDay {
    init(date: Date) {
        self.init(
            date: date,
            calendar: Calendar(identifier: .gregorian),
            timeZone: .current
        )
    }
}

extension SB_SleepDetailDay {
    var sleepTime: Int32 { sleepTimeSec }
}
