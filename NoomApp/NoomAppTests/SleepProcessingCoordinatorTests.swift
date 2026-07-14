import Foundation
import XCTest
import SensorBioSDK
@testable import NoomApp

private enum SleepCoordinatorStubError: Error, Sendable {
    case transient
    case missingDetail
}

private actor SleepFetchClockSpy {
    private var sessionsByDay: [SleepLocalDay: [SleepSessionSummary]] = [:]
    private var detailsByIdentity: [SleepSessionIdentity: SB_SleepDetailDay] = [:]
    private var sessionFailuresRemaining: [SleepLocalDay: Int] = [:]
    private var detailFailuresRemaining: [SleepSessionIdentity: Int] = [:]
    private var shouldSuspendNextSessions = false
    private var suspendedDetailIdentities: Set<SleepSessionIdentity> = []
    private var suspendedSessionFetches:
        [SleepSessionsRequestKey: [CheckedContinuation<[SleepSessionSummary], Error>]] = [:]
    private var suspendedDetailFetches:
        [SleepRequestKey: [CheckedContinuation<SB_SleepDetailDay, Error>]] = [:]

    private var sessionRequestLog: [SleepSessionsRequestKey] = []
    private var detailRequestLog: [SleepRequestKey] = []
    private var sleepLog: [Duration] = []
    private var instant: Duration = .zero

    func setSessions(_ sessions: [SleepSessionSummary], for day: SleepLocalDay) {
        sessionsByDay[day] = sessions
    }

    func setDetail(_ detail: SB_SleepDetailDay, for identity: SleepSessionIdentity) {
        detailsByIdentity[identity] = detail
    }

    func failNextSessions(for day: SleepLocalDay, count: Int = 1) {
        sessionFailuresRemaining[day, default: 0] += count
    }

    func failNextDetail(for identity: SleepSessionIdentity, count: Int = 1) {
        detailFailuresRemaining[identity, default: 0] += count
    }

    func suspendNextSessionsFetch() {
        shouldSuspendNextSessions = true
    }

    func suspendNextDetailFetch(for identity: SleepSessionIdentity) {
        suspendedDetailIdentities.insert(identity)
    }

    func fetchSessions(for key: SleepSessionsRequestKey) async throws -> [SleepSessionSummary] {
        sessionRequestLog.append(key)

        if shouldSuspendNextSessions {
            shouldSuspendNextSessions = false
            return try await withCheckedThrowingContinuation { continuation in
                suspendedSessionFetches[key, default: []].append(continuation)
            }
        }

        if sessionFailuresRemaining[key.localDay, default: 0] > 0 {
            sessionFailuresRemaining[key.localDay, default: 0] -= 1
            throw SleepCoordinatorStubError.transient
        }
        return sessionsByDay[key.localDay] ?? []
    }

    func fetchDetail(for key: SleepRequestKey) async throws -> SB_SleepDetailDay {
        detailRequestLog.append(key)

        if suspendedDetailIdentities.remove(key.sessionIdentity) != nil {
            return try await withCheckedThrowingContinuation { continuation in
                suspendedDetailFetches[key, default: []].append(continuation)
            }
        }

        if detailFailuresRemaining[key.sessionIdentity, default: 0] > 0 {
            detailFailuresRemaining[key.sessionIdentity, default: 0] -= 1
            throw SleepCoordinatorStubError.transient
        }
        guard let detail = detailsByIdentity[key.sessionIdentity] else {
            throw SleepCoordinatorStubError.missingDetail
        }
        return detail
    }

    func resolveSessions(
        _ sessions: [SleepSessionSummary],
        for key: SleepSessionsRequestKey
    ) {
        guard var continuations = suspendedSessionFetches[key], !continuations.isEmpty else {
            preconditionFailure("No suspended sessions fetch for \(key)")
        }
        let continuation = continuations.removeFirst()
        suspendedSessionFetches[key] = continuations.isEmpty ? nil : continuations
        continuation.resume(returning: sessions)
    }

    func resolveDetail(_ detail: SB_SleepDetailDay, for key: SleepRequestKey) {
        guard var continuations = suspendedDetailFetches[key], !continuations.isEmpty else {
            preconditionFailure("No suspended detail fetch for \(key)")
        }
        let continuation = continuations.removeFirst()
        suspendedDetailFetches[key] = continuations.isEmpty ? nil : continuations
        continuation.resume(returning: detail)
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        sleepLog.append(duration)
        instant += duration
        await Task.yield()
        try Task.checkCancellation()
    }

    func monotonicNow() -> Duration {
        instant
    }

    func sessionRequests() -> [SleepSessionsRequestKey] {
        sessionRequestLog
    }

    func detailRequests() -> [SleepRequestKey] {
        detailRequestLog
    }

    func sleptDurations() -> [Duration] {
        sleepLog
    }

    func resetRecordedEffects(resetClock: Bool = false) {
        sessionRequestLog = []
        detailRequestLog = []
        sleepLog = []
        if resetClock {
            instant = .zero
        }
    }
}

private actor SleepMetadataStoreSpy {
    struct Save: Equatable, Sendable {
        let accountScopeHash: String
        let data: Data
    }

    private var values: [String: Data] = [:]
    private var loadLog: [String] = []
    private var saveLog: [Save] = []
    private var clearLog: [String] = []

    func load(accountScopeHash: String) throws -> Data? {
        loadLog.append(accountScopeHash)
        return values[accountScopeHash]
    }

    func save(accountScopeHash: String, data: Data) throws {
        values[accountScopeHash] = data
        saveLog.append(Save(accountScopeHash: accountScopeHash, data: data))
    }

    func clear(accountScopeHash: String) throws {
        values[accountScopeHash] = nil
        clearLog.append(accountScopeHash)
    }

    func saves() -> [Save] {
        saveLog
    }

    func loads() -> [String] {
        loadLog
    }

    func clears() -> [String] {
        clearLog
    }
}

private actor SleepCompletionNotifierSpy {
    enum Event: Equatable, Sendable {
        case checkedAuthorization
        case delivered(String)
        case cleared(String)
    }

    private var status: SleepNotificationAuthorizationStatus = .authorized
    private var eventLog: [Event] = []
    private var deliveredLog: [SleepCompletionNotification] = []

    func setAuthorizationStatus(_ status: SleepNotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> SleepNotificationAuthorizationStatus {
        eventLog.append(.checkedAuthorization)
        return status
    }

    func deliver(_ notification: SleepCompletionNotification) {
        deliveredLog.append(notification)
        eventLog.append(.delivered(notification.identifier))
    }

    func clear(accountScopeHash: String) {
        eventLog.append(.cleared(accountScopeHash))
    }

    func events() -> [Event] {
        eventLog
    }

    func deliveries() -> [SleepCompletionNotification] {
        deliveredLog
    }
}

@MainActor
final class SleepProcessingCoordinatorTests: XCTestCase {
    private let accountA = "raw-account-a-1234"
    private let accountB = "raw-account-b-5678"
    private let oldDay = SleepLocalDay(rawValue: 20260712)
    private let selectedDay = SleepLocalDay(rawValue: 20260713)
    private let otherDay = SleepLocalDay(rawValue: 20260714)

    private func makeIdentity(
        day: SleepLocalDay,
        endTimestamp: Int64,
        timezoneMinutes: Int32 = -420
    ) -> SleepSessionIdentity {
        SleepSessionIdentity(
            endDate: day.rawValue,
            endTimestamp: endTimestamp,
            timezoneMinutes: timezoneMinutes
        )
    }

    private func makeSession(
        day: SleepLocalDay,
        identityEndTimestamp: Int64,
        endMilliseconds: Int64,
        timezoneMinutes: Int32 = -420,
        asleepMinutes: Int32 = 400
    ) -> SleepSessionSummary {
        SleepSessionSummary(
            identity: makeIdentity(
                day: day,
                endTimestamp: identityEndTimestamp,
                timezoneMinutes: timezoneMinutes
            ),
            startMilliseconds: endMilliseconds - 25_200_000,
            endMilliseconds: endMilliseconds,
            asleepMinutes: asleepMinutes
        )
    }

    private func makeDetail(
        processState: SB_SleepScoreProcessState,
        processing: Bool = false,
        score: Int32 = 91
    ) -> SB_SleepDetailDay {
        SB_SleepDetailDay(
            sleepScore: SB_SleepScore(processState: processState, score: score),
            sleepTimeSec: 25_200,
            sleepOnset: 1_700_000_000_000,
            wakeUpTime: 1_700_025_200_000,
            timezone: -420,
            processing: processing
        )
    }

    private func configuration(
        eventDebounce: Duration = .milliseconds(250),
        pollInterval: Duration = .seconds(1),
        maxPollAttempts: Int = 3,
        maximumForegroundReconciliationDuration: Duration = .seconds(60),
        maxCorrelationDistanceMilliseconds: Int64 = 1_000
    ) -> SleepProcessingConfiguration {
        SleepProcessingConfiguration(
            eventDebounce: eventDebounce,
            pollInterval: pollInterval,
            maxPollAttempts: maxPollAttempts,
            maximumForegroundReconciliationDuration:
                maximumForegroundReconciliationDuration,
            maxCorrelationDistanceMilliseconds:
                maxCorrelationDistanceMilliseconds
        )
    }

    private func makeSystem(
        configuration: SleepProcessingConfiguration? = nil
    ) -> (
        coordinator: SleepProcessingCoordinator,
        fetchClock: SleepFetchClockSpy,
        metadata: SleepMetadataStoreSpy,
        notifier: SleepCompletionNotifierSpy
    ) {
        let fetchClock = SleepFetchClockSpy()
        let metadata = SleepMetadataStoreSpy()
        let notifier = SleepCompletionNotifierSpy()
        let dependencies = SleepProcessingDependencies(
            fetchSessions: { key in
                try await fetchClock.fetchSessions(for: key)
            },
            fetchDetail: { key in
                try await fetchClock.fetchDetail(for: key)
            },
            sleep: { duration in
                try await fetchClock.sleep(for: duration)
            },
            monotonicNow: {
                await fetchClock.monotonicNow()
            },
            metadataStore: SleepProtectedMetadataStore(
                load: { accountScopeHash in
                    try await metadata.load(accountScopeHash: accountScopeHash)
                },
                save: { accountScopeHash, data in
                    try await metadata.save(
                        accountScopeHash: accountScopeHash,
                        data: data
                    )
                },
                clear: { accountScopeHash in
                    try await metadata.clear(accountScopeHash: accountScopeHash)
                }
            ),
            completionNotifier: SleepCompletionNotifier(
                authorizationStatus: {
                    await notifier.authorizationStatus()
                },
                deliver: { notification in
                    await notifier.deliver(notification)
                },
                clear: { accountScopeHash in
                    await notifier.clear(accountScopeHash: accountScopeHash)
                }
            )
        )
        return (
            SleepProcessingCoordinator(
                dependencies: dependencies,
                configuration: configuration ?? self.configuration()
            ),
            fetchClock,
            metadata,
            notifier
        )
    }

    private func activate(
        _ coordinator: SleepProcessingCoordinator,
        accountScope: String,
        day: SleepLocalDay
    ) async {
        coordinator.setAccountScope(accountScope)
        await coordinator.waitForEffects()
        coordinator.selectDay(day)
        await coordinator.waitForEffects()
    }

    private func waitUntil(
        _ description: String,
        condition: @escaping () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out without wall-clock sleeping: \(description)")
    }

    private func settleTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    func testDetectedSleepImmediatelyEntersPendingAndPreservesOlderDatedCompletion() async throws {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        let oldSession = makeSession(
            day: oldDay,
            identityEndTimestamp: 1_001,
            endMilliseconds: 50_000
        )
        await system.fetchClock.setSessions([oldSession], for: oldDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: oldSession.identity
        )
        await activate(system.coordinator, accountScope: accountA, day: oldDay)
        let completed = try XCTUnwrap(system.coordinator.lastCompleted)

        await system.fetchClock.setSessions([], for: selectedDay)
        system.coordinator.selectDay(selectedDay)
        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 100_000
        )

        XCTAssertEqual(system.coordinator.state.pipelineState.phase, .detected)
        XCTAssertEqual(system.coordinator.state.pendingCandidates.count, 1)
        XCTAssertNil(system.coordinator.selectedSnapshot)
        XCTAssertEqual(system.coordinator.lastCompleted, completed)
        XCTAssertEqual(system.coordinator.displaySnapshot, completed)
        XCTAssertEqual(system.coordinator.displaySnapshot?.sourceDay, oldDay)

        await system.coordinator.waitForEffects()
    }

    func testIdentityFreeSignalBurstCoalescesIntoOneReconciliationWithoutFabricatingIdentityOrCompletion() async {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        await system.fetchClock.setSessions([], for: selectedDay)
        await activate(system.coordinator, accountScope: accountA, day: selectedDay)
        await system.fetchClock.resetRecordedEffects(resetClock: true)

        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 100_000
        )
        system.coordinator.receiveVoidSignal(.stored)
        system.coordinator.receiveVoidSignal(.uploaded)
        system.coordinator.receiveVoidSignal(.sync)
        system.coordinator.receiveVoidSignal(.sync)
        await system.coordinator.waitForEffects()

        let sessionRequests = await system.fetchClock.sessionRequests()
        let detailRequests = await system.fetchClock.detailRequests()
        let sleptDurations = await system.fetchClock.sleptDurations()
        XCTAssertEqual(sessionRequests.count, 1)
        XCTAssertEqual(detailRequests, [])
        XCTAssertEqual(
            sleptDurations.filter {
                $0 == .milliseconds(250)
            }.count,
            1
        )
        XCTAssertEqual(system.coordinator.state.pendingCandidates.count, 1)
        XCTAssertNil(
            system.coordinator.state.pendingCandidates.values.first?
                .boundSessionIdentity
        )
        XCTAssertNil(system.coordinator.selectedSession)
        XCTAssertNil(system.coordinator.selectedSnapshot)
        XCTAssertNil(system.coordinator.lastCompleted)
        XCTAssertEqual(system.coordinator.state.pipelineState.phase, .detected)
    }

    func testReconciliationRetainsAllSessionsCorrelatesProvisionalEndAndFetchesExactIdentityLineage() async throws {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        await system.fetchClock.setSessions([], for: selectedDay)
        await activate(system.coordinator, accountScope: accountA, day: selectedDay)

        let deterministicFallback = makeSession(
            day: selectedDay,
            identityEndTimestamp: 10_001,
            endMilliseconds: 130_000,
            timezoneMinutes: -300,
            asleepMinutes: 500
        )
        let correlated = makeSession(
            day: selectedDay,
            identityEndTimestamp: 10_002,
            endMilliseconds: 100_250,
            timezoneMinutes: 330,
            asleepMinutes: 120
        )
        let sessions = [deterministicFallback, correlated]
        await system.fetchClock.setSessions(sessions, for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: correlated.identity
        )
        await system.fetchClock.resetRecordedEffects()

        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 100_000
        )
        await system.coordinator.waitForEffects()

        XCTAssertEqual(system.coordinator.sessions, sessions)
        XCTAssertEqual(system.coordinator.state.selection.allSessions, sessions)
        XCTAssertEqual(system.coordinator.selectedSession, correlated)
        XCTAssertEqual(
            system.coordinator.state.selection.reason,
            .correlatedDetection
        )
        let detailRequests = await system.fetchClock.detailRequests()
        let request = try XCTUnwrap(detailRequests.last)
        XCTAssertEqual(request.accountScope, accountA)
        XCTAssertEqual(request.localDay, selectedDay)
        XCTAssertEqual(request.sessionIdentity.endDate, correlated.identity.endDate)
        XCTAssertEqual(
            request.sessionIdentity.endTimestamp,
            correlated.identity.endTimestamp
        )
        XCTAssertEqual(
            request.sessionIdentity.timezoneMinutes,
            correlated.identity.timezoneMinutes
        )
        XCTAssertEqual(system.coordinator.selectedSnapshot?.sessionIdentity, correlated.identity)
        XCTAssertEqual(system.coordinator.lastCompleted?.sessionIdentity, correlated.identity)
    }

    func testNoCorrelationUsesDeterministicFallbackAndExplicitSelectionFetchesThatExactSession() async throws {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        let explicit = makeSession(
            day: selectedDay,
            identityEndTimestamp: 20_001,
            endMilliseconds: 200_000,
            timezoneMinutes: -60,
            asleepMinutes: 120
        )
        let fallback = makeSession(
            day: selectedDay,
            identityEndTimestamp: 20_002,
            endMilliseconds: 210_000,
            timezoneMinutes: 60,
            asleepMinutes: 500
        )
        await system.fetchClock.setSessions([explicit, fallback], for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully, score: 82),
            for: fallback.identity
        )
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully, score: 93),
            for: explicit.identity
        )

        await activate(system.coordinator, accountScope: accountA, day: selectedDay)

        XCTAssertEqual(system.coordinator.selectedSession, fallback)
        XCTAssertEqual(
            system.coordinator.state.selection.reason,
            .longestSessionDefault
        )
        XCTAssertEqual(system.coordinator.sessions, [explicit, fallback])

        await system.fetchClock.resetRecordedEffects()
        system.coordinator.selectSession(explicit.identity)
        await system.coordinator.waitForEffects()

        XCTAssertEqual(system.coordinator.selectedSession, explicit)
        XCTAssertEqual(system.coordinator.sessions, [explicit, fallback])
        let detailRequests = await system.fetchClock.detailRequests()
        let exactRequest = try XCTUnwrap(detailRequests.last)
        XCTAssertEqual(exactRequest.sessionIdentity, explicit.identity)
        XCTAssertEqual(
            system.coordinator.selectedSnapshot?.sessionIdentity,
            explicit.identity
        )
        XCTAssertEqual(system.coordinator.selectedSnapshot?.detail.sleepScore.score, 93)
    }

    func testEverySDKProcessStateMapsTruthfullyAndDetailProcessingOverridesReportedSuccess() async throws {
        let mappings: [(
            processState: SB_SleepScoreProcessState,
            phase: SleepProcessingPhase,
            outcome: SleepAnalysisOutcome,
            completes: Bool
        )] = [
            (.processing, .processing, .processing, false),
            (.processedSuccessfully, .ready, .processedSuccessfully, true),
            (.aggregated, .retryableError, .invalidDailyAggregate, false),
            (.shortSession, .shortSession, .shortSession, false),
            (.processedWithError, .retryableError, .processedWithError, false),
            (.circadianGenerating, .calibrating, .processing, false),
        ]

        for (index, mapping) in mappings.enumerated() {
            let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
            let session = makeSession(
                day: selectedDay,
                identityEndTimestamp: Int64(30_000 + index),
                endMilliseconds: Int64(300_000 + index)
            )
            await system.fetchClock.setSessions([session], for: selectedDay)
            await system.fetchClock.setDetail(
                makeDetail(processState: mapping.processState),
                for: session.identity
            )

            await activate(
                system.coordinator,
                accountScope: "\(accountA)-\(index)",
                day: selectedDay
            )

            XCTAssertEqual(
                system.coordinator.state.pipelineState.phase,
                mapping.phase,
                "Incorrect phase for \(mapping.processState)"
            )
            XCTAssertEqual(
                system.coordinator.state.analysisOutcome,
                mapping.outcome,
                "Incorrect outcome for \(mapping.processState)"
            )
            XCTAssertEqual(
                system.coordinator.lastCompleted != nil,
                mapping.completes,
                "Incorrect completion for \(mapping.processState)"
            )
            XCTAssertEqual(
                system.coordinator.state.permitsBodyStatus(
                    forAccountScope: "\(accountA)-\(index)",
                    localDay: selectedDay,
                    sessionIdentity: session.identity
                ),
                mapping.completes,
                "Incorrect Body Status permission for \(mapping.processState)"
            )
        }

        let overrideSystem = makeSystem(configuration: configuration(maxPollAttempts: 1))
        let overrideSession = makeSession(
            day: selectedDay,
            identityEndTimestamp: 30_999,
            endMilliseconds: 399_999
        )
        await overrideSystem.fetchClock.setSessions([overrideSession], for: selectedDay)
        await overrideSystem.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully, processing: true),
            for: overrideSession.identity
        )

        await activate(
            overrideSystem.coordinator,
            accountScope: "\(accountA)-override",
            day: selectedDay
        )

        XCTAssertEqual(overrideSystem.coordinator.state.pipelineState.phase, .processing)
        XCTAssertEqual(overrideSystem.coordinator.state.analysisOutcome, .processing)
        XCTAssertNil(overrideSystem.coordinator.lastCompleted)
        XCTAssertFalse(
            overrideSystem.coordinator.state.permitsBodyStatus(
                forAccountScope: "\(accountA)-override",
                localDay: selectedDay,
                sessionIdentity: overrideSession.identity
            )
        )
    }

    func testStaleSessionsCompletionAfterAccountDateAndGenerationChangeCannotMutateNewerState() async throws {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        system.coordinator.setAccountScope(accountA)
        await system.coordinator.waitForEffects()
        await system.fetchClock.suspendNextSessionsFetch()

        system.coordinator.selectDay(oldDay)
        await waitUntil("old account sessions fetch to suspend") {
            await system.fetchClock.sessionRequests().count == 1
        }
        let oldSessionRequests = await system.fetchClock.sessionRequests()
        let staleKey = try XCTUnwrap(oldSessionRequests.first)

        await system.fetchClock.setSessions([], for: otherDay)
        system.coordinator.setAccountScope(accountB)
        system.coordinator.selectDay(otherDay)
        await system.coordinator.waitForEffects()
        let newerState = system.coordinator.state

        let staleSession = makeSession(
            day: oldDay,
            identityEndTimestamp: 40_001,
            endMilliseconds: 400_000
        )
        await system.fetchClock.resolveSessions([staleSession], for: staleKey)
        await settleTasks()

        XCTAssertEqual(system.coordinator.state, newerState)
        XCTAssertEqual(system.coordinator.state.accountScope, accountB)
        XCTAssertEqual(system.coordinator.state.selectedDay, otherDay)
        XCTAssertFalse(system.coordinator.sessions.contains(staleSession))
        let detailRequests = await system.fetchClock.detailRequests()
        XCTAssertFalse(
            detailRequests.contains {
                $0.sessionIdentity == staleSession.identity
            }
        )
    }

    func testStaleExactDetailCompletionAfterSessionAndGenerationChangeCannotOverwriteNewSelection() async throws {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        let first = makeSession(
            day: selectedDay,
            identityEndTimestamp: 50_001,
            endMilliseconds: 500_000,
            asleepMinutes: 500
        )
        let second = makeSession(
            day: selectedDay,
            identityEndTimestamp: 50_002,
            endMilliseconds: 510_000,
            asleepMinutes: 100
        )
        await system.fetchClock.setSessions([first, second], for: selectedDay)
        await system.fetchClock.suspendNextDetailFetch(for: first.identity)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully, score: 94),
            for: second.identity
        )
        system.coordinator.setAccountScope(accountA)
        await system.coordinator.waitForEffects()

        system.coordinator.selectDay(selectedDay)
        await waitUntil("first exact detail fetch to suspend") {
            await system.fetchClock.detailRequests().count == 1
        }
        let suspendedDetailRequests = await system.fetchClock.detailRequests()
        let staleKey = try XCTUnwrap(suspendedDetailRequests.first)

        system.coordinator.selectSession(second.identity)
        await system.coordinator.waitForEffects()
        let newerState = system.coordinator.state
        XCTAssertEqual(system.coordinator.selectedSession, second)
        XCTAssertEqual(system.coordinator.lastCompleted?.sessionIdentity, second.identity)

        await system.fetchClock.resolveDetail(
            makeDetail(processState: .processedSuccessfully, score: 11),
            for: staleKey
        )
        await settleTasks()

        XCTAssertEqual(system.coordinator.state, newerState)
        XCTAssertEqual(system.coordinator.selectedSnapshot?.sessionIdentity, second.identity)
        XCTAssertEqual(system.coordinator.selectedSnapshot?.detail.sleepScore.score, 94)
        let detailRequests = await system.fetchClock.detailRequests()
        XCTAssertEqual(
            detailRequests.map(\.sessionIdentity),
            [first.identity, second.identity]
        )
    }

    func testTransientNetworkFailurePreservesLastCompletedAndMarksTransportAndFreshnessTruthfully() async throws {
        let system = makeSystem(configuration: configuration(maxPollAttempts: 1))
        let oldSession = makeSession(
            day: oldDay,
            identityEndTimestamp: 60_001,
            endMilliseconds: 600_000
        )
        await system.fetchClock.setSessions([oldSession], for: oldDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: oldSession.identity
        )
        await activate(system.coordinator, accountScope: accountA, day: oldDay)
        let oldCompletion = try XCTUnwrap(system.coordinator.lastCompleted)

        await system.fetchClock.setSessions([], for: selectedDay)
        system.coordinator.selectDay(selectedDay)
        await system.coordinator.waitForEffects()

        let newSession = makeSession(
            day: selectedDay,
            identityEndTimestamp: 60_002,
            endMilliseconds: 610_000
        )
        await system.fetchClock.setSessions([newSession], for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: newSession.identity
        )
        await system.fetchClock.failNextDetail(for: newSession.identity)
        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 610_000
        )
        await system.coordinator.waitForEffects()

        XCTAssertEqual(system.coordinator.lastCompleted, oldCompletion)
        XCTAssertEqual(system.coordinator.displaySnapshot, oldCompletion)
        XCTAssertNil(system.coordinator.selectedSnapshot)
        XCTAssertEqual(system.coordinator.state.transport, .failed)
        XCTAssertEqual(system.coordinator.state.freshness, .stale)
        XCTAssertEqual(system.coordinator.state.pendingCandidates.count, 1)
        XCTAssertFalse(
            system.coordinator.state.permitsBodyStatus(
                forAccountScope: accountA,
                localDay: selectedDay,
                sessionIdentity: newSession.identity
            )
        )
    }

    func testPollingStopsAtAttemptLimitOrSixtySecondDeadlineAndLeavesPendingCandidateExhausted() async throws {
        let attemptSystem = makeSystem(
            configuration: configuration(
                eventDebounce: .zero,
                pollInterval: .seconds(1),
                maxPollAttempts: 3,
                maximumForegroundReconciliationDuration: .seconds(60)
            )
        )
        await attemptSystem.fetchClock.setSessions([], for: selectedDay)
        await activate(attemptSystem.coordinator, accountScope: accountA, day: selectedDay)
        await attemptSystem.fetchClock.resetRecordedEffects(resetClock: true)
        let attemptSession = makeSession(
            day: selectedDay,
            identityEndTimestamp: 70_001,
            endMilliseconds: 700_000
        )
        await attemptSystem.fetchClock.setSessions([attemptSession], for: selectedDay)
        await attemptSystem.fetchClock.setDetail(
            makeDetail(processState: .processing, processing: true),
            for: attemptSession.identity
        )

        attemptSystem.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 700_000
        )
        await attemptSystem.coordinator.waitForEffects()

        let attemptDetailRequests = await attemptSystem.fetchClock.detailRequests()
        XCTAssertEqual(attemptDetailRequests.count, 3)
        let attemptCandidate = try XCTUnwrap(
            attemptSystem.coordinator.state.pendingCandidates.values.first
        )
        XCTAssertEqual(attemptCandidate.retryAttempt, 3)
        XCTAssertTrue(attemptCandidate.isRetryExhausted)
        XCTAssertEqual(attemptSystem.coordinator.state.pipelineState.phase, .processing)
        XCTAssertNil(attemptSystem.coordinator.lastCompleted)

        let deadlineSystem = makeSystem(
            configuration: configuration(
                eventDebounce: .zero,
                pollInterval: .seconds(31),
                maxPollAttempts: 100,
                maximumForegroundReconciliationDuration: .seconds(60)
            )
        )
        await deadlineSystem.fetchClock.setSessions([], for: otherDay)
        await activate(deadlineSystem.coordinator, accountScope: accountB, day: otherDay)
        await deadlineSystem.fetchClock.resetRecordedEffects(resetClock: true)
        let deadlineSession = makeSession(
            day: otherDay,
            identityEndTimestamp: 70_002,
            endMilliseconds: 710_000
        )
        await deadlineSystem.fetchClock.setSessions([deadlineSession], for: otherDay)
        await deadlineSystem.fetchClock.setDetail(
            makeDetail(processState: .processing, processing: true),
            for: deadlineSession.identity
        )

        deadlineSystem.coordinator.receiveDetectedSleep(
            localDay: otherDay,
            provisionalEndTimestampMilliseconds: 710_000
        )
        await deadlineSystem.coordinator.waitForEffects()

        let deadlineDetailRequests = await deadlineSystem.fetchClock.detailRequests()
        let deadlineElapsed = await deadlineSystem.fetchClock.monotonicNow()
        XCTAssertEqual(deadlineDetailRequests.count, 2)
        XCTAssertLessThanOrEqual(
            deadlineElapsed,
            .seconds(60)
        )
        let deadlineCandidate = try XCTUnwrap(
            deadlineSystem.coordinator.state.pendingCandidates.values.first
        )
        XCTAssertEqual(deadlineCandidate.retryAttempt, 2)
        XCTAssertTrue(deadlineCandidate.isRetryExhausted)
        XCTAssertEqual(deadlineSystem.coordinator.state.pipelineState.phase, .processing)
        XCTAssertNil(deadlineSystem.coordinator.lastCompleted)
    }

    func testBackgroundSuspendsPollingAndForegroundResumesPendingReconciliation() async throws {
        let system = makeSystem(
            configuration: configuration(
                eventDebounce: .zero,
                maxPollAttempts: 5
            )
        )
        await system.fetchClock.setSessions([], for: selectedDay)
        await activate(system.coordinator, accountScope: accountA, day: selectedDay)
        await system.fetchClock.resetRecordedEffects(resetClock: true)

        let session = makeSession(
            day: selectedDay,
            identityEndTimestamp: 80_001,
            endMilliseconds: 800_000
        )
        await system.fetchClock.setSessions([session], for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processing, processing: true),
            for: session.identity
        )
        system.coordinator.setForeground(false)
        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 800_000
        )
        await system.coordinator.waitForEffects()

        let backgroundDetailRequests = await system.fetchClock.detailRequests()
        let backgroundMetadataSaves = await system.metadata.saves()
        XCTAssertEqual(backgroundDetailRequests.count, 1)
        let suspendedCandidate = try XCTUnwrap(
            system.coordinator.state.pendingCandidates.values.first
        )
        XCTAssertEqual(suspendedCandidate.retryAttempt, 1)
        XCTAssertFalse(suspendedCandidate.isRetryExhausted)
        XCTAssertFalse(backgroundMetadataSaves.isEmpty)
        XCTAssertNil(system.coordinator.lastCompleted)

        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: session.identity
        )
        system.coordinator.setForeground(true)
        await system.coordinator.waitForEffects()

        let resumedDetailRequests = await system.fetchClock.detailRequests()
        XCTAssertEqual(resumedDetailRequests.count, 2)
        XCTAssertEqual(system.coordinator.lastCompleted?.sessionIdentity, session.identity)
        XCTAssertEqual(system.coordinator.state.pendingCandidates, [:])
        XCTAssertEqual(system.coordinator.state.pipelineState.phase, .ready)
    }

    func testProtectedMetadataIsMinimalHashedAndClearedOnAccountSwitchAndSignOut() async throws {
        let system = makeSystem(
            configuration: configuration(
                eventDebounce: .zero,
                maxPollAttempts: 1
            )
        )
        await system.fetchClock.setSessions([], for: selectedDay)
        await activate(system.coordinator, accountScope: accountA, day: selectedDay)
        let session = makeSession(
            day: selectedDay,
            identityEndTimestamp: 90_001,
            endMilliseconds: 900_000,
            timezoneMinutes: 345
        )
        await system.fetchClock.setSessions([session], for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processing, processing: true, score: 77),
            for: session.identity
        )

        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 900_000
        )
        await system.coordinator.waitForEffects()

        let metadataSaves = await system.metadata.saves()
        let save = try XCTUnwrap(metadataSaves.last)
        XCTAssertNotEqual(save.accountScopeHash, accountA)
        XCTAssertFalse(save.accountScopeHash.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: save.data) as? [String: Any]
        )
        XCTAssertNotNil(object["version"])
        XCTAssertEqual(
            object["accountScopeHash"] as? String,
            save.accountScopeHash
        )

        let json = String(decoding: save.data, as: UTF8.self)
        for requiredLineage in [
            "localDay",
            "candidateGeneration",
            "provisionalEndTimestampMilliseconds",
            "boundSessionIdentity",
            "retryAttempt",
            "isRetryExhausted",
            "endDate",
            "endTimestamp",
            "timezoneMinutes",
            "20260713",
            "90001",
            "345",
        ] {
            XCTAssertTrue(
                json.contains(requiredLineage),
                "Missing protected lineage field/value: \(requiredLineage)"
            )
        }
        for forbidden in [
            accountA,
            "SB_SleepDetailDay",
            "\"sleepScore\"",
            "\"score\"",
            "\"restingHr\"",
            "\"restingHrv\"",
            "\"heartRate\"",
            "\"hrv\"",
            "\"stages\"",
            "\"email\"",
            "\"username\"",
        ] {
            XCTAssertFalse(json.contains(forbidden), "Persisted forbidden value: \(forbidden)")
        }

        system.coordinator.setAccountScope(accountB)
        await system.coordinator.waitForEffects()
        let clearsAfterSwitch = await system.metadata.clears()
        let notifierEventsAfterSwitch = await system.notifier.events()
        XCTAssertTrue(clearsAfterSwitch.contains(save.accountScopeHash))
        XCTAssertTrue(
            notifierEventsAfterSwitch.contains(.cleared(save.accountScopeHash))
        )
        XCTAssertEqual(system.coordinator.state.accountScope, accountB)
        XCTAssertEqual(system.coordinator.state.pendingCandidates, [:])
        XCTAssertNil(system.coordinator.lastCompleted)

        let metadataLoads = await system.metadata.loads()
        let accountBHash = try XCTUnwrap(metadataLoads.last)
        XCTAssertNotEqual(accountBHash, accountB)
        system.coordinator.setAccountScope(nil)
        await system.coordinator.waitForEffects()
        let clearsAfterSignOut = await system.metadata.clears()
        let notifierEventsAfterSignOut = await system.notifier.events()
        XCTAssertTrue(clearsAfterSignOut.contains(accountBHash))
        XCTAssertTrue(
            notifierEventsAfterSignOut.contains(.cleared(accountBHash))
        )
        XCTAssertNil(system.coordinator.state.accountScope)
    }

    func testCompletionNotificationChecksExistingAuthorizationNeverPromptsAndFiresOnlyOnceForBackgroundExactSuccess() async throws {
        let cases: [(
            name: String,
            foreground: Bool,
            authorization: SleepNotificationAuthorizationStatus,
            expectedChecks: Int,
            expectedDeliveries: Int
        )] = [
            ("background authorized", false, .authorized, 1, 1),
            ("background not determined", false, .notDetermined, 1, 0),
            ("foreground authorized", true, .authorized, 0, 0),
        ]

        for (index, testCase) in cases.enumerated() {
            let system = makeSystem(
                configuration: configuration(
                    eventDebounce: .zero,
                    maxPollAttempts: 1
                )
            )
            await system.notifier.setAuthorizationStatus(testCase.authorization)
            await system.fetchClock.setSessions([], for: selectedDay)
            await activate(
                system.coordinator,
                accountScope: "\(accountA)-notification-\(index)",
                day: selectedDay
            )
            let session = makeSession(
                day: selectedDay,
                identityEndTimestamp: Int64(100_001 + index),
                endMilliseconds: Int64(1_000_000 + index)
            )
            await system.fetchClock.setSessions([session], for: selectedDay)
            await system.fetchClock.setDetail(
                makeDetail(processState: .processedSuccessfully),
                for: session.identity
            )
            system.coordinator.setForeground(testCase.foreground)

            system.coordinator.receiveDetectedSleep(
                localDay: selectedDay,
                provisionalEndTimestampMilliseconds: session.endMilliseconds
            )
            await system.coordinator.waitForEffects()

            let events = await system.notifier.events()
            let deliveries = await system.notifier.deliveries()
            XCTAssertEqual(
                events.filter { $0 == .checkedAuthorization }.count,
                testCase.expectedChecks,
                testCase.name
            )
            XCTAssertEqual(
                deliveries.count,
                testCase.expectedDeliveries,
                testCase.name
            )

            if testCase.expectedDeliveries == 1 {
                let notification = try XCTUnwrap(deliveries.first)
                XCTAssertFalse(notification.identifier.isEmpty)
                XCTAssertFalse(
                    notification.identifier.contains(
                        "\(accountA)-notification-\(index)"
                    )
                )
                XCTAssertEqual(notification.localDay, selectedDay)
                XCTAssertEqual(notification.sessionIdentity, session.identity)

                system.coordinator.refresh()
                await system.coordinator.waitForEffects()
                let deliveriesAfterRefresh = await system.notifier.deliveries()
                XCTAssertEqual(
                    deliveriesAfterRefresh.count,
                    1,
                    "Duplicate exact success must not notify twice"
                )
            }
        }
    }

    func testBackToBackAccountAndDayBindingDoesNotCancelPendingMetadataRestore() async throws {
        let system = makeSystem(
            configuration: configuration(eventDebounce: .zero, maxPollAttempts: 1)
        )
        let hash = try XCTUnwrap(SleepProcessingCoordinator.accountScopeHash(accountA))
        let metadata = SleepPendingCandidateMetadata(
            localDay: selectedDay,
            candidateGeneration: 7,
            provisionalEndTimestampMilliseconds: 7_777_000,
            boundSessionIdentity: nil,
            retryAttempt: 2,
            isRetryExhausted: false
        )
        let envelope = SleepPendingMetadataEnvelope(
            version: SleepPendingMetadataEnvelope.currentVersion,
            accountScopeHash: hash,
            selectedDay: selectedDay,
            selectedSessionIdentity: nil,
            pendingCandidates: [metadata],
            lastCompletedIdentity: nil,
            savedAtEpochSeconds: 1
        )
        try await system.metadata.save(
            accountScopeHash: hash,
            data: JSONEncoder().encode(envelope)
        )
        await system.fetchClock.setSessions([], for: selectedDay)

        system.coordinator.setAccountScope(accountA)
        system.coordinator.selectDay(selectedDay)
        await system.coordinator.waitForEffects()

        let key = SleepCandidateKey(
            accountScope: accountA,
            localDay: selectedDay,
            candidateGeneration: 7
        )
        let restored = try XCTUnwrap(system.coordinator.state.pendingCandidates[key])
        XCTAssertEqual(restored.correlationProvisionalEndTimestampMilliseconds, 7_777_000)
        XCTAssertEqual(restored.retryAttempt, 2)
        XCTAssertEqual(system.coordinator.state.selectedDay, selectedDay)
        let metadataLoads = await system.metadata.loads()
        XCTAssertEqual(metadataLoads, [hash])
    }

    func testExplicitRetryStartsNewGenerationAndRealReconciliationAfterExhaustion() async throws {
        let system = makeSystem(
            configuration: configuration(
                eventDebounce: .zero,
                maxPollAttempts: 1
            )
        )
        await system.fetchClock.setSessions([], for: selectedDay)
        await activate(system.coordinator, accountScope: accountA, day: selectedDay)
        await system.fetchClock.resetRecordedEffects(resetClock: true)
        let session = makeSession(
            day: selectedDay,
            identityEndTimestamp: 110_001,
            endMilliseconds: 1_100_000
        )
        await system.fetchClock.setSessions([session], for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processing, processing: true),
            for: session.identity
        )

        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: session.endMilliseconds
        )
        await system.coordinator.waitForEffects()

        let candidate = try XCTUnwrap(
            system.coordinator.state.pendingCandidates.values.first
        )
        XCTAssertTrue(candidate.isRetryExhausted)
        let requestsBeforeRetry = await system.fetchClock.detailRequests()
        let firstRequest = try XCTUnwrap(requestsBeforeRetry.last)
        XCTAssertEqual(requestsBeforeRetry.count, 1)

        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: session.identity
        )
        system.coordinator.retry(candidateKey: candidate.key)
        await system.coordinator.waitForEffects()

        let requests = await system.fetchClock.detailRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertGreaterThan(
            try XCTUnwrap(requests.last).requestGeneration,
            firstRequest.requestGeneration
        )
        XCTAssertEqual(system.coordinator.lastCompleted?.sessionIdentity, session.identity)
        XCTAssertNil(system.coordinator.state.pendingCandidates[candidate.key])
        XCTAssertEqual(system.coordinator.state.pipelineState.phase, .ready)
    }

    func testMultipleDetectedCandidatesStayIndependentAndOneExactSuccessResolvesOnlyItsCandidate() async throws {
        let system = makeSystem(
            configuration: configuration(
                eventDebounce: .milliseconds(250),
                maxPollAttempts: 1,
                maxCorrelationDistanceMilliseconds: 500
            )
        )
        await system.fetchClock.setSessions([], for: selectedDay)
        await activate(system.coordinator, accountScope: accountA, day: selectedDay)
        await system.fetchClock.resetRecordedEffects(resetClock: true)

        let first = makeSession(
            day: selectedDay,
            identityEndTimestamp: 120_001,
            endMilliseconds: 1_200_050,
            asleepMinutes: 500
        )
        let second = makeSession(
            day: selectedDay,
            identityEndTimestamp: 120_002,
            endMilliseconds: 1_300_050,
            asleepMinutes: 400
        )
        await system.fetchClock.setSessions([second, first], for: selectedDay)
        await system.fetchClock.setDetail(
            makeDetail(processState: .processedSuccessfully),
            for: first.identity
        )

        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 1_200_000
        )
        system.coordinator.receiveDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 1_300_000
        )
        await system.coordinator.waitForEffects()

        let firstKey = SleepCandidateKey(
            accountScope: accountA,
            localDay: selectedDay,
            candidateGeneration: 1
        )
        let secondKey = SleepCandidateKey(
            accountScope: accountA,
            localDay: selectedDay,
            candidateGeneration: 2
        )
        XCTAssertNil(system.coordinator.state.pendingCandidates[firstKey])
        XCTAssertEqual(
            system.coordinator.state.pendingCandidates[secondKey]?
                .boundSessionIdentity,
            second.identity
        )
        XCTAssertEqual(system.coordinator.state.pendingCandidates.count, 1)
        XCTAssertEqual(system.coordinator.sessions, [second, first])
        XCTAssertEqual(system.coordinator.selectedSession, first)
        XCTAssertEqual(system.coordinator.lastCompleted?.sessionIdentity, first.identity)
        let detailRequests = await system.fetchClock.detailRequests()
        XCTAssertEqual(
            detailRequests.map(\.sessionIdentity),
            [first.identity]
        )
    }
}
