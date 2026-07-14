import XCTest
import SensorBioSDK
@testable import NoomApp

final class SleepJourneyStateTests: XCTestCase {
    private let accountA = "opaque-account-a"
    private let accountB = "opaque-account-b"
    private let oldDay = SleepLocalDay(rawValue: 20260712)
    private let selectedDay = SleepLocalDay(rawValue: 20260713)
    private let otherDay = SleepLocalDay(rawValue: 20260714)

    private func makeIdentity(
        localDay: SleepLocalDay,
        endTimestamp: Int64,
        timezoneMinutes: Int32 = -420
    ) -> SleepSessionIdentity {
        SleepSessionIdentity(
            endDate: localDay.rawValue,
            endTimestamp: endTimestamp,
            timezoneMinutes: timezoneMinutes
        )
    }

    private func makeSummary(
        localDay: SleepLocalDay,
        identityEndTimestamp: Int64,
        endMilliseconds: Int64,
        asleepMinutes: Int32 = 400
    ) -> SleepSessionSummary {
        SleepSessionSummary(
            identity: makeIdentity(
                localDay: localDay,
                endTimestamp: identityEndTimestamp
            ),
            startMilliseconds: endMilliseconds - 1_000,
            endMilliseconds: endMilliseconds,
            asleepMinutes: asleepMinutes
        )
    }

    private func makeDetail(outcome: SleepAnalysisOutcome) -> SB_SleepDetailDay {
        let processState: SB_SleepScoreProcessState
        let processing: Bool
        switch outcome {
        case .unknown:
            processState = .processing
            processing = false
        case .processing:
            processState = .processing
            processing = true
        case .processedSuccessfully:
            processState = .processedSuccessfully
            processing = false
        case .shortSession:
            processState = .shortSession
            processing = false
        case .processedWithError:
            processState = .processedWithError
            processing = false
        case .invalidDailyAggregate:
            processState = .aggregated
            processing = false
        }

        return SB_SleepDetailDay(
            sleepScore: SB_SleepScore(processState: processState, score: 91),
            sleepTimeSec: 25_200,
            sleepOnset: 1_700_000_000_000,
            wakeUpTime: 1_700_025_200_000,
            timezone: -420,
            processing: processing
        )
    }

    private func makeSnapshot(
        accountScope: String,
        localDay: SleepLocalDay,
        sessionIdentity: SleepSessionIdentity,
        requestGeneration: UInt64,
        outcome: SleepAnalysisOutcome,
        circadianAvailability: SleepCircadianAvailability = .available,
        sourceDay: SleepLocalDay? = nil,
        freshness: SleepFreshness = .fresh
    ) -> SleepAtomicSnapshot {
        SleepAtomicSnapshot(
            accountScope: accountScope,
            localDay: localDay,
            sessionIdentity: sessionIdentity,
            detail: makeDetail(outcome: outcome),
            outcome: outcome,
            circadianAvailability: circadianAvailability,
            sourceDay: sourceDay ?? localDay,
            requestGeneration: requestGeneration,
            freshness: freshness
        )
    }

    private func makeSessionsKey(
        accountScope: String,
        localDay: SleepLocalDay,
        requestGeneration: UInt64
    ) -> SleepSessionsRequestKey {
        SleepSessionsRequestKey(
            accountScope: accountScope,
            localDay: localDay,
            requestGeneration: requestGeneration
        )
    }

    private func makeDetailKey(
        accountScope: String,
        localDay: SleepLocalDay,
        sessionIdentity: SleepSessionIdentity,
        requestGeneration: UInt64
    ) -> SleepRequestKey {
        SleepRequestKey(
            accountScope: accountScope,
            localDay: localDay,
            sessionIdentity: sessionIdentity,
            requestGeneration: requestGeneration
        )
    }

    private func emptySelection() -> SleepSessionSelection {
        SleepSessionSelection.select(
            from: [],
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )
    }

    private func makeCompletedState(
        accountScope: String,
        localDay: SleepLocalDay,
        session: SleepSessionSummary
    ) -> (state: SleepJourneyState, snapshot: SleepAtomicSnapshot) {
        var state = SleepJourneyState(
            accountScope: accountScope,
            selectedDay: localDay
        )
        let generation = state.requestGeneration
        _ = state.commitSessions(
            [session],
            for: makeSessionsKey(
                accountScope: accountScope,
                localDay: localDay,
                requestGeneration: generation
            ),
            maxCorrelationDistanceMilliseconds: 1_000
        )
        let snapshot = makeSnapshot(
            accountScope: accountScope,
            localDay: localDay,
            sessionIdentity: session.identity,
            requestGeneration: generation,
            outcome: .processedSuccessfully
        )
        _ = state.commitSnapshot(
            snapshot,
            for: makeDetailKey(
                accountScope: accountScope,
                localDay: localDay,
                sessionIdentity: session.identity,
                requestGeneration: generation
            )
        )
        return (state, snapshot)
    }

    private func makePendingStateOverCompleted() -> (
        state: SleepJourneyState,
        oldSnapshot: SleepAtomicSnapshot,
        selectedSession: SleepSessionSummary,
        candidateKey: SleepCandidateKey
    ) {
        let oldSession = makeSummary(
            localDay: oldDay,
            identityEndTimestamp: 1_001,
            endMilliseconds: 5_000
        )
        let completed = makeCompletedState(
            accountScope: accountA,
            localDay: oldDay,
            session: oldSession
        )
        var state = completed.state
        _ = state.selectDay(selectedDay)

        let selectedSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 2_001,
            endMilliseconds: 10_100
        )
        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 10_000
        )
        _ = state.commitSessions(
            [selectedSession],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )
        state.reconcilePendingCandidates(maxCorrelationDistanceMilliseconds: 500)

        return (
            state,
            completed.snapshot,
            selectedSession,
            SleepCandidateKey(
                accountScope: accountA,
                localDay: selectedDay,
                candidateGeneration: 1
            )
        )
    }

    private func makeSnapshotGuardState() -> (
        state: SleepJourneyState,
        selectedSession: SleepSessionSummary,
        alternateSession: SleepSessionSummary
    ) {
        let selectedSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 3_001,
            endMilliseconds: 30_000,
            asleepMinutes: 500
        )
        let alternateSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 3_002,
            endMilliseconds: 31_000,
            asleepMinutes: 100
        )
        var state = SleepJourneyState(
            accountScope: accountA,
            selectedDay: selectedDay
        )
        _ = state.commitSessions(
            [alternateSession, selectedSession],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )
        return (state, selectedSession, alternateSession)
    }

    private func assertContains(
        _ command: SleepJourneyCommand,
        in commands: [SleepJourneyCommand],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(commands.contains(command), file: file, line: line)
    }

    private func assertSessionsCommitIsDropped(
        for staleKey: SleepSessionsRequestKey,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let baseline = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 4_001,
            endMilliseconds: 40_000
        )
        let replacement = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 4_002,
            endMilliseconds: 50_000
        )
        var state = SleepJourneyState(
            accountScope: accountA,
            selectedDay: selectedDay
        )
        _ = state.commitSessions(
            [baseline],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )
        let before = state

        let accepted = state.commitSessions(
            [replacement],
            for: staleKey,
            maxCorrelationDistanceMilliseconds: 500
        )

        XCTAssertFalse(accepted, file: file, line: line)
        XCTAssertEqual(state, before, file: file, line: line)
    }

    private func assertSnapshotCommitIsDropped(
        accountScope: String,
        localDay: SleepLocalDay,
        sessionIdentity: SleepSessionIdentity,
        requestGeneration: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var scenario = makeSnapshotGuardState()
        let before = scenario.state
        let snapshot = makeSnapshot(
            accountScope: accountScope,
            localDay: localDay,
            sessionIdentity: sessionIdentity,
            requestGeneration: requestGeneration,
            outcome: .processedSuccessfully
        )
        let key = makeDetailKey(
            accountScope: accountScope,
            localDay: localDay,
            sessionIdentity: sessionIdentity,
            requestGeneration: requestGeneration
        )

        let accepted = scenario.state.commitSnapshot(snapshot, for: key)

        XCTAssertFalse(accepted, file: file, line: line)
        XCTAssertEqual(scenario.state, before, file: file, line: line)
    }

    func testInitialRootOwnsExplicitSelectionsAndIndependentJourneyState() {
        let state = SleepJourneyState(
            accountScope: accountA,
            selectedDay: selectedDay
        )

        XCTAssertEqual(state.accountScope, accountA)
        XCTAssertEqual(state.selectedDay, selectedDay)
        XCTAssertEqual(state.allSessions, [])
        XCTAssertEqual(state.selection, emptySelection())
        XCTAssertNil(state.selectedSnapshot)
        XCTAssertNil(state.lastCompleted)
        XCTAssertEqual(state.pendingCandidates, [:])
        XCTAssertEqual(state.pipelineState, SleepProcessingState())
        XCTAssertFalse(state.reconciliationRequested)
        XCTAssertEqual(state.analysisOutcome, .unknown)
        XCTAssertEqual(state.transport, .idle)
        XCTAssertEqual(state.freshness, .stale)
        XCTAssertEqual(state.circadianAvailability, .unknown)
        XCTAssertEqual(state.requestGeneration, 0)
        XCTAssertNil(state.displaySnapshot)
    }

    func testAccountSwitchAndSignOutAtomicallyClearAccountBoundState() {
        let session = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 5_001,
            endMilliseconds: 50_000
        )

        for targetScope: String? in [accountB, nil] {
            var completed = makeCompletedState(
                accountScope: accountA,
                localDay: selectedDay,
                session: session
            )
            _ = completed.state.recordDetectedSleep(
                localDay: selectedDay,
                provisionalEndTimestampMilliseconds: 60_000
            )
            let previousGeneration = completed.state.requestGeneration

            let commands = completed.state.setAccountScope(targetScope)

            XCTAssertEqual(completed.state.accountScope, targetScope)
            XCTAssertNil(completed.state.selectedDay)
            XCTAssertEqual(completed.state.allSessions, [])
            XCTAssertEqual(completed.state.selection, emptySelection())
            XCTAssertNil(completed.state.selectedSnapshot)
            XCTAssertNil(completed.state.lastCompleted)
            XCTAssertEqual(completed.state.pendingCandidates, [:])
            XCTAssertEqual(
                completed.state.requestGeneration,
                previousGeneration + 1
            )
            assertContains(.cancelRequests, in: commands)
            assertContains(
                .clearPersistedMetadata(accountScope: accountA),
                in: commands
            )
        }
    }

    func testSameAccountUpdateIsIdempotent() {
        let session = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 6_001,
            endMilliseconds: 60_000
        )
        var completed = makeCompletedState(
            accountScope: accountA,
            localDay: selectedDay,
            session: session
        )
        _ = completed.state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 61_000
        )
        let before = completed.state

        let commands = completed.state.setAccountScope(accountA)

        XCTAssertEqual(commands, [])
        XCTAssertEqual(completed.state, before)
    }

    func testDaySelectionInvalidatesSelectedLineageAndPreservesDatedHistory() {
        let session = makeSummary(
            localDay: oldDay,
            identityEndTimestamp: 7_001,
            endMilliseconds: 70_000
        )
        var completed = makeCompletedState(
            accountScope: accountA,
            localDay: oldDay,
            session: session
        )
        _ = completed.state.recordDetectedSleep(
            localDay: oldDay,
            provisionalEndTimestampMilliseconds: 71_000
        )
        let candidatesBefore = completed.state.pendingCandidates
        let generationBefore = completed.state.requestGeneration

        let commands = completed.state.selectDay(selectedDay)

        XCTAssertEqual(completed.state.selectedDay, selectedDay)
        XCTAssertEqual(completed.state.requestGeneration, generationBefore + 1)
        XCTAssertEqual(completed.state.allSessions, [])
        XCTAssertEqual(completed.state.selection, emptySelection())
        XCTAssertNil(completed.state.selectedSnapshot)
        XCTAssertEqual(completed.state.lastCompleted, completed.snapshot)
        XCTAssertEqual(completed.state.lastCompleted?.sourceDay, oldDay)
        XCTAssertEqual(completed.state.pendingCandidates, candidatesBefore)
        assertContains(.cancelRequests, in: commands)
        assertContains(
            .reconcileSessions(
                makeSessionsKey(
                    accountScope: accountA,
                    localDay: selectedDay,
                    requestGeneration: generationBefore + 1
                )
            ),
            in: commands
        )
    }

    func testConcurrentDetectionsCreateIndependentCandidatesWithoutRelabelingHistory() {
        let oldSession = makeSummary(
            localDay: oldDay,
            identityEndTimestamp: 8_001,
            endMilliseconds: 80_000
        )
        var completed = makeCompletedState(
            accountScope: accountA,
            localDay: oldDay,
            session: oldSession
        )
        _ = completed.state.selectDay(selectedDay)

        _ = completed.state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 90_000
        )
        _ = completed.state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 100_000
        )

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
        XCTAssertEqual(completed.state.pendingCandidates.count, 2)
        XCTAssertEqual(
            completed.state.pendingCandidates[firstKey]?
                .correlationProvisionalEndTimestampMilliseconds,
            90_000
        )
        XCTAssertEqual(
            completed.state.pendingCandidates[secondKey]?
                .correlationProvisionalEndTimestampMilliseconds,
            100_000
        )
        XCTAssertNil(completed.state.pendingCandidates[firstKey]?.boundSessionIdentity)
        XCTAssertNil(completed.state.pendingCandidates[secondKey]?.boundSessionIdentity)
        XCTAssertNil(completed.state.selection.selectedSession)
        XCTAssertNil(completed.state.selectedSnapshot)
        XCTAssertEqual(completed.state.lastCompleted, completed.snapshot)
        XCTAssertEqual(completed.state.displaySnapshot, completed.snapshot)
        XCTAssertEqual(completed.state.displaySnapshot?.sourceDay, oldDay)
        XCTAssertEqual(completed.state.selectedDay, selectedDay)
        XCTAssertEqual(completed.state.pipelineState.phase, .detected)
        XCTAssertTrue(completed.state.reconciliationRequested)
    }

    func testVoidPipelineSignalsOnlyRequestReconciliationAndAreDuplicateSafe() {
        let session = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 9_001,
            endMilliseconds: 90_000
        )
        let signals: [SleepVoidPipelineSignal] = [.stored, .uploaded, .sync]

        for signal in signals {
            var completed = makeCompletedState(
                accountScope: accountA,
                localDay: selectedDay,
                session: session
            )
            _ = completed.state.recordDetectedSleep(
                localDay: selectedDay,
                provisionalEndTimestampMilliseconds: 100_000
            )
            let candidateKey = SleepCandidateKey(
                accountScope: accountA,
                localDay: selectedDay,
                candidateGeneration: 1
            )
            let candidatesBefore = completed.state.pendingCandidates
            let sessionsBefore = completed.state.allSessions
            let selectionBefore = completed.state.selection
            let expectedCommand = SleepJourneyCommand.reconcileSessions(
                makeSessionsKey(
                    accountScope: accountA,
                    localDay: selectedDay,
                    requestGeneration: completed.state.requestGeneration
                )
            )

            let firstCommands = completed.state.receiveVoidPipelineSignal(signal)
            let duplicateCommands = completed.state.receiveVoidPipelineSignal(signal)

            assertContains(expectedCommand, in: firstCommands)
            assertContains(expectedCommand, in: duplicateCommands)
            XCTAssertTrue(completed.state.reconciliationRequested)
            XCTAssertEqual(completed.state.pendingCandidates, candidatesBefore)
            XCTAssertNil(
                completed.state.pendingCandidates[candidateKey]?.boundSessionIdentity
            )
            XCTAssertEqual(completed.state.allSessions, sessionsBefore)
            XCTAssertEqual(completed.state.selection, selectionBefore)
            XCTAssertEqual(completed.state.selectedSnapshot, completed.snapshot)
            XCTAssertEqual(completed.state.lastCompleted, completed.snapshot)
            XCTAssertNotEqual(completed.state.pipelineState.phase, .ready)
        }
    }

    func testFreshSessionsCommitRetainsAllSessionsAndUsesExplicitSelectorReason() {
        var state = SleepJourneyState(
            accountScope: accountA,
            selectedDay: selectedDay
        )
        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 10_000
        )
        let longer = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 10_001,
            endMilliseconds: 30_000,
            asleepMinutes: 500
        )
        let correlated = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 10_002,
            endMilliseconds: 10_300,
            asleepMinutes: 100
        )
        let sessions = [longer, correlated]

        let accepted = state.commitSessions(
            sessions,
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(state.allSessions, sessions)
        XCTAssertEqual(state.selection.allSessions, sessions)
        XCTAssertEqual(state.selection.selectedSession, correlated)
        XCTAssertEqual(state.selection.reason, .correlatedDetection)
    }

    func testSessionsCommitDropsStaleAccount() {
        assertSessionsCommitIsDropped(
            for: makeSessionsKey(
                accountScope: accountB,
                localDay: selectedDay,
                requestGeneration: 0
            )
        )
    }

    func testSessionsCommitDropsStaleDay() {
        assertSessionsCommitIsDropped(
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: otherDay,
                requestGeneration: 0
            )
        )
    }

    func testSessionsCommitDropsStaleRequestGeneration() {
        assertSessionsCommitIsDropped(
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: 1
            )
        )
    }

    func testReconciliationBindsCandidatesOneToOneWithinInjectedBound() {
        var state = SleepJourneyState(
            accountScope: accountA,
            selectedDay: selectedDay
        )
        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 10_000
        )
        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 10_200
        )
        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 100_000
        )
        let firstSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 11_001,
            endMilliseconds: 10_050
        )
        let secondSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 11_002,
            endMilliseconds: 10_450
        )
        _ = state.commitSessions(
            [secondSession, firstSession],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )

        state.reconcilePendingCandidates(maxCorrelationDistanceMilliseconds: 500)

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
        let outOfBoundKey = SleepCandidateKey(
            accountScope: accountA,
            localDay: selectedDay,
            candidateGeneration: 3
        )
        XCTAssertEqual(
            state.pendingCandidates[firstKey]?.boundSessionIdentity,
            firstSession.identity
        )
        XCTAssertEqual(
            state.pendingCandidates[secondKey]?.boundSessionIdentity,
            secondSession.identity
        )
        XCTAssertNil(state.pendingCandidates[outOfBoundKey]?.boundSessionIdentity)
        let boundIdentities = [firstKey, secondKey, outOfBoundKey].compactMap {
            state.pendingCandidates[$0]?.boundSessionIdentity
        }
        XCTAssertEqual(Set(boundIdentities).count, 2)
    }

    func testReconciliationPreservesStillValidExactBinding() {
        var state = SleepJourneyState(
            accountScope: accountA,
            selectedDay: selectedDay
        )
        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 10_000
        )
        let retainedSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 12_001,
            endMilliseconds: 10_400
        )
        _ = state.commitSessions(
            [retainedSession],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )
        state.reconcilePendingCandidates(maxCorrelationDistanceMilliseconds: 500)

        _ = state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 20_000
        )
        let newlyCloserToFirst = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 12_002,
            endMilliseconds: 10_000
        )
        let secondSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 12_003,
            endMilliseconds: 20_100
        )
        _ = state.commitSessions(
            [newlyCloserToFirst, secondSession, retainedSession],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )

        state.reconcilePendingCandidates(maxCorrelationDistanceMilliseconds: 500)

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
        XCTAssertEqual(
            state.pendingCandidates[firstKey]?.boundSessionIdentity,
            retainedSession.identity
        )
        XCTAssertEqual(
            state.pendingCandidates[secondKey]?.boundSessionIdentity,
            secondSession.identity
        )
        XCTAssertNotEqual(
            state.pendingCandidates[firstKey]?.boundSessionIdentity,
            state.pendingCandidates[secondKey]?.boundSessionIdentity
        )
    }

    func testSnapshotCommitDropsStaleAccount() {
        let scenario = makeSnapshotGuardState()
        assertSnapshotCommitIsDropped(
            accountScope: accountB,
            localDay: selectedDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: 0
        )
    }

    func testSnapshotCommitDropsStaleDay() {
        let scenario = makeSnapshotGuardState()
        assertSnapshotCommitIsDropped(
            accountScope: accountA,
            localDay: otherDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: 0
        )
    }

    func testSnapshotCommitDropsStaleSelectedSession() {
        let scenario = makeSnapshotGuardState()
        assertSnapshotCommitIsDropped(
            accountScope: accountA,
            localDay: selectedDay,
            sessionIdentity: scenario.alternateSession.identity,
            requestGeneration: 0
        )
    }

    func testSnapshotCommitDropsStaleRequestGeneration() {
        let scenario = makeSnapshotGuardState()
        assertSnapshotCommitIsDropped(
            accountScope: accountA,
            localDay: selectedDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: 1
        )
    }

    func testNonSuccessfulExactSnapshotsNeverReplaceCompletedHistory() {
        let outcomes: [SleepAnalysisOutcome] = [
            .processing,
            .shortSession,
            .processedWithError,
            .invalidDailyAggregate,
        ]

        for outcome in outcomes {
            var scenario = makePendingStateOverCompleted()
            let snapshot = makeSnapshot(
                accountScope: accountA,
                localDay: selectedDay,
                sessionIdentity: scenario.selectedSession.identity,
                requestGeneration: scenario.state.requestGeneration,
                outcome: outcome,
                circadianAvailability: .generating,
                freshness: .stale
            )

            let accepted = scenario.state.commitSnapshot(
                snapshot,
                for: makeDetailKey(
                    accountScope: accountA,
                    localDay: selectedDay,
                    sessionIdentity: scenario.selectedSession.identity,
                    requestGeneration: scenario.state.requestGeneration
                )
            )

            XCTAssertTrue(accepted)
            XCTAssertEqual(scenario.state.selectedSnapshot, snapshot)
            XCTAssertEqual(scenario.state.analysisOutcome, outcome)
            XCTAssertEqual(scenario.state.lastCompleted, scenario.oldSnapshot)
            XCTAssertNotNil(
                scenario.state.pendingCandidates[scenario.candidateKey]
            )
            XCTAssertEqual(scenario.state.displaySnapshot, scenario.oldSnapshot)
            XCTAssertEqual(scenario.state.displaySnapshot?.sourceDay, oldDay)
            XCTAssertEqual(scenario.state.selectedSnapshot?.sourceDay, selectedDay)
        }
    }

    func testExactSuccessAtomicallyReplacesHistoryAndResolvesOnlyMatchingCandidate() {
        var scenario = makePendingStateOverCompleted()
        let secondSession = makeSummary(
            localDay: selectedDay,
            identityEndTimestamp: 13_002,
            endMilliseconds: 20_100
        )
        _ = scenario.state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 20_000
        )
        _ = scenario.state.commitSessions(
            [secondSession, scenario.selectedSession],
            for: makeSessionsKey(
                accountScope: accountA,
                localDay: selectedDay,
                requestGeneration: scenario.state.requestGeneration
            ),
            maxCorrelationDistanceMilliseconds: 500
        )
        scenario.state.reconcilePendingCandidates(
            maxCorrelationDistanceMilliseconds: 500
        )
        let secondKey = SleepCandidateKey(
            accountScope: accountA,
            localDay: selectedDay,
            candidateGeneration: 2
        )
        XCTAssertEqual(
            scenario.state.pendingCandidates[scenario.candidateKey]?
                .boundSessionIdentity,
            scenario.selectedSession.identity
        )
        XCTAssertEqual(
            scenario.state.pendingCandidates[secondKey]?.boundSessionIdentity,
            secondSession.identity
        )
        let success = makeSnapshot(
            accountScope: accountA,
            localDay: selectedDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: scenario.state.requestGeneration,
            outcome: .processedSuccessfully
        )

        let accepted = scenario.state.commitSnapshot(
            success,
            for: makeDetailKey(
                accountScope: accountA,
                localDay: selectedDay,
                sessionIdentity: scenario.selectedSession.identity,
                requestGeneration: scenario.state.requestGeneration
            )
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(scenario.state.selectedSnapshot, success)
        XCTAssertEqual(scenario.state.lastCompleted, success)
        XCTAssertNotEqual(scenario.state.lastCompleted, scenario.oldSnapshot)
        XCTAssertNil(scenario.state.pendingCandidates[scenario.candidateKey])
        XCTAssertEqual(
            scenario.state.pendingCandidates[secondKey]?.boundSessionIdentity,
            secondSession.identity
        )
        XCTAssertEqual(scenario.state.displaySnapshot, success)
    }

    func testRootKeepsPipelineAnalysisCircadianTransportAndFreshnessOrthogonal() {
        var scenario = makeSnapshotGuardState()
        scenario.state.setTransport(.failed)
        let snapshot = makeSnapshot(
            accountScope: accountA,
            localDay: selectedDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: scenario.state.requestGeneration,
            outcome: .processedSuccessfully,
            circadianAvailability: .generating,
            freshness: .stale
        )
        _ = scenario.state.commitSnapshot(
            snapshot,
            for: makeDetailKey(
                accountScope: accountA,
                localDay: selectedDay,
                sessionIdentity: scenario.selectedSession.identity,
                requestGeneration: scenario.state.requestGeneration
            )
        )

        XCTAssertEqual(scenario.state.pipelineState.phase, .ready)
        XCTAssertEqual(scenario.state.analysisOutcome, .processedSuccessfully)
        XCTAssertEqual(scenario.state.circadianAvailability, .generating)
        XCTAssertEqual(scenario.state.transport, .failed)
        XCTAssertEqual(scenario.state.freshness, .stale)

        scenario.state.setTransport(.loaded)

        XCTAssertEqual(scenario.state.pipelineState.phase, .ready)
        XCTAssertEqual(scenario.state.analysisOutcome, .processedSuccessfully)
        XCTAssertEqual(scenario.state.circadianAvailability, .generating)
        XCTAssertEqual(scenario.state.transport, .loaded)
        XCTAssertEqual(scenario.state.freshness, .stale)
    }

    func testRootDelegatesBodyStatusToExactAtomicSnapshotLineage() {
        var scenario = makeSnapshotGuardState()
        let snapshot = makeSnapshot(
            accountScope: accountA,
            localDay: selectedDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: scenario.state.requestGeneration,
            outcome: .processedSuccessfully
        )
        _ = scenario.state.commitSnapshot(
            snapshot,
            for: makeDetailKey(
                accountScope: accountA,
                localDay: selectedDay,
                sessionIdentity: scenario.selectedSession.identity,
                requestGeneration: scenario.state.requestGeneration
            )
        )
        let contexts: [(
            accountScope: String,
            localDay: SleepLocalDay,
            sessionIdentity: SleepSessionIdentity
        )] = [
            (accountA, selectedDay, scenario.selectedSession.identity),
            (accountB, selectedDay, scenario.selectedSession.identity),
            (accountA, otherDay, scenario.selectedSession.identity),
            (accountA, selectedDay, scenario.alternateSession.identity),
        ]

        for context in contexts {
            XCTAssertEqual(
                scenario.state.permitsBodyStatus(
                    forAccountScope: context.accountScope,
                    localDay: context.localDay,
                    sessionIdentity: context.sessionIdentity
                ),
                snapshot.permitsBodyStatus(
                    forAccountScope: context.accountScope,
                    localDay: context.localDay,
                    sessionIdentity: context.sessionIdentity
                )
            )
        }
    }

    func testDetectionAfterCompletedTerminalStartsNextIndependentCandidateGeneration() {
        var scenario = makePendingStateOverCompleted()
        let success = makeSnapshot(
            accountScope: accountA,
            localDay: selectedDay,
            sessionIdentity: scenario.selectedSession.identity,
            requestGeneration: scenario.state.requestGeneration,
            outcome: .processedSuccessfully
        )
        _ = scenario.state.commitSnapshot(
            success,
            for: makeDetailKey(
                accountScope: accountA,
                localDay: selectedDay,
                sessionIdentity: scenario.selectedSession.identity,
                requestGeneration: scenario.state.requestGeneration
            )
        )
        XCTAssertNil(scenario.state.pendingCandidates[scenario.candidateKey])
        XCTAssertEqual(scenario.state.pipelineState.phase, .ready)

        _ = scenario.state.recordDetectedSleep(
            localDay: selectedDay,
            provisionalEndTimestampMilliseconds: 30_000
        )

        let nextKey = SleepCandidateKey(
            accountScope: accountA,
            localDay: selectedDay,
            candidateGeneration: 2
        )
        XCTAssertEqual(scenario.state.pendingCandidates.count, 1)
        XCTAssertEqual(
            scenario.state.pendingCandidates[nextKey]?
                .correlationProvisionalEndTimestampMilliseconds,
            30_000
        )
        XCTAssertNil(
            scenario.state.pendingCandidates[nextKey]?.boundSessionIdentity
        )
        XCTAssertEqual(scenario.state.selectedSnapshot, success)
        XCTAssertEqual(scenario.state.lastCompleted, success)
        XCTAssertEqual(scenario.state.displaySnapshot, success)
        XCTAssertEqual(scenario.state.pipelineState.phase, .detected)
    }
}
