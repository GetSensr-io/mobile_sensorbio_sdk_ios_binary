import Foundation
import XCTest
@testable import NoomApp

final class NoomRecordingReadinessTests: XCTestCase {
    private let policy = NoomRecordingFinalizationPolicy(
        phaseBounds: [
            .stoppingDevice: 30,
            .syncingDevice: 45,
            .submitting: 105,
        ],
        correlationToleranceMilliseconds: 15_000
    )

    func testConnectedWithoutFullConfigurationCannotStartRecording() {
        XCTAssertFalse(
            policy.canStartRecording(
                connected: true,
                isFullyConfigured: false
            )
        )
    }

    func testFullConfigurationIsTheReadinessSignalRatherThanLooseConnection() {
        XCTAssertTrue(
            policy.canStartRecording(
                connected: false,
                isFullyConfigured: true
            )
        )
    }
}

final class NoomRecordingFinalizationPhaseTests: XCTestCase {
    private let requestID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let staleRequestID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let stoppingToken = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let syncingToken = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private var attempt: NoomRecordingAttempt {
        NoomRecordingAttempt(
            requestID: requestID,
            experience: .spotCheck,
            startedAtMilliseconds: 1_700_000_000_000
        )
    }

    private func makePolicy(
        stoppingDevice: TimeInterval = 30,
        syncingDevice: TimeInterval = 45,
        submitting: TimeInterval = 105
    ) -> NoomRecordingFinalizationPolicy {
        NoomRecordingFinalizationPolicy(
            phaseBounds: [
                .stoppingDevice: stoppingDevice,
                .syncingDevice: syncingDevice,
                .submitting: submitting,
            ],
            correlationToleranceMilliseconds: 15_000
        )
    }

    private func resolveTimeout(
        phase: NoomRecordingFinalizationPhase,
        enteredAt: TimeInterval,
        now: TimeInterval,
        token: UUID,
        policy: NoomRecordingFinalizationPolicy
    ) -> NoomRecordingResolution {
        let watchdog = policy.armWatchdog(
            for: attempt,
            phase: phase,
            enteredAt: enteredAt,
            token: token
        )
        return policy.resolve(
            timeout: watchdog,
            firedToken: token,
            requestID: requestID,
            phase: phase,
            now: now
        )
    }

    func testStoppingDeviceIsInertBeforeItsThirtySecondBoundAndRecoverableAtTheBound() {
        let policy = makePolicy()

        XCTAssertEqual(
            resolveTimeout(
                phase: .stoppingDevice,
                enteredAt: 100,
                now: 129.999,
                token: stoppingToken,
                policy: policy
            ),
            .unresolved
        )
        XCTAssertEqual(
            resolveTimeout(
                phase: .stoppingDevice,
                enteredAt: 100,
                now: 130,
                token: stoppingToken,
                policy: policy
            ),
            .recoverable(.phaseTimedOut(.stoppingDevice))
        )
    }

    func testSyncingDeviceIsInertBeforeItsFortyFiveSecondBoundAndRecoverableAtTheBound() {
        let policy = makePolicy()

        XCTAssertEqual(
            resolveTimeout(
                phase: .syncingDevice,
                enteredAt: 100,
                now: 144.999,
                token: syncingToken,
                policy: policy
            ),
            .unresolved
        )
        XCTAssertEqual(
            resolveTimeout(
                phase: .syncingDevice,
                enteredAt: 100,
                now: 145,
                token: syncingToken,
                policy: policy
            ),
            .recoverable(.phaseTimedOut(.syncingDevice))
        )
    }

    func testSubmittingIsInertBeforeItsOneHundredFiveSecondBoundAndRecoverableAtTheBound() {
        let policy = makePolicy()
        let submittingToken = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

        XCTAssertEqual(
            resolveTimeout(
                phase: .submitting,
                enteredAt: 100,
                now: 204.999,
                token: submittingToken,
                policy: policy
            ),
            .unresolved
        )
        XCTAssertEqual(
            resolveTimeout(
                phase: .submitting,
                enteredAt: 100,
                now: 205,
                token: submittingToken,
                policy: policy
            ),
            .recoverable(.phaseTimedOut(.submitting))
        )
    }

    func testInjectedPhaseBoundsAreIndependent() {
        let policy = makePolicy(stoppingDevice: 2, syncingDevice: 7, submitting: 13)
        let cases: [(NoomRecordingFinalizationPhase, TimeInterval, UUID)] = [
            (.stoppingDevice, 2, stoppingToken),
            (.syncingDevice, 7, syncingToken),
            (.submitting, 13, UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!),
        ]

        for (phase, bound, token) in cases {
            XCTAssertEqual(
                resolveTimeout(
                    phase: phase,
                    enteredAt: 20,
                    now: 20 + bound - 0.001,
                    token: token,
                    policy: policy
                ),
                .unresolved,
                "\(phase) recovered before its injected bound"
            )
            XCTAssertEqual(
                resolveTimeout(
                    phase: phase,
                    enteredAt: 20,
                    now: 20 + bound,
                    token: token,
                    policy: policy
                ),
                .recoverable(.phaseTimedOut(phase)),
                "\(phase) did not recover at its injected bound"
            )
        }
    }

    func testPhaseAdvancementResetsTheDeadlineFromTheAdvancementTime() {
        let policy = makePolicy()
        let stopping = policy.armWatchdog(
            for: attempt,
            phase: .stoppingDevice,
            enteredAt: 100,
            token: stoppingToken
        )
        let syncing = policy.advanceWatchdog(
            stopping,
            to: .syncingDevice,
            at: 125,
            token: syncingToken
        )

        XCTAssertEqual(
            policy.resolve(
                timeout: syncing,
                firedToken: syncingToken,
                requestID: requestID,
                phase: .syncingDevice,
                now: 169.999
            ),
            .unresolved
        )
        XCTAssertEqual(
            policy.resolve(
                timeout: syncing,
                firedToken: syncingToken,
                requestID: requestID,
                phase: .syncingDevice,
                now: 170
            ),
            .recoverable(.phaseTimedOut(.syncingDevice))
        )
    }

    func testTimeoutFromAStaleTokenIsInert() {
        let policy = makePolicy()
        let watchdog = policy.armWatchdog(
            for: attempt,
            phase: .stoppingDevice,
            enteredAt: 100,
            token: stoppingToken
        )

        XCTAssertEqual(
            policy.resolve(
                timeout: watchdog,
                firedToken: syncingToken,
                requestID: requestID,
                phase: .stoppingDevice,
                now: 130
            ),
            .unresolved
        )
    }

    func testTimeoutFromAStaleRequestIsInert() {
        let policy = makePolicy()
        let watchdog = policy.armWatchdog(
            for: attempt,
            phase: .stoppingDevice,
            enteredAt: 100,
            token: stoppingToken
        )

        XCTAssertEqual(
            policy.resolve(
                timeout: watchdog,
                firedToken: stoppingToken,
                requestID: staleRequestID,
                phase: .stoppingDevice,
                now: 130
            ),
            .unresolved
        )
    }

    func testTimeoutFromAStalePhaseIsInert() {
        let policy = makePolicy()
        let watchdog = policy.armWatchdog(
            for: attempt,
            phase: .stoppingDevice,
            enteredAt: 100,
            token: stoppingToken
        )

        XCTAssertEqual(
            policy.resolve(
                timeout: watchdog,
                firedToken: stoppingToken,
                requestID: requestID,
                phase: .syncingDevice,
                now: 145
            ),
            .unresolved
        )
    }

    func testKeepWaitingExplicitlyRearmsTheCurrentPhase() {
        let policy = makePolicy()
        let watchdog = policy.armWatchdog(
            for: attempt,
            phase: .stoppingDevice,
            enteredAt: 100,
            token: stoppingToken
        )
        XCTAssertEqual(
            policy.resolve(
                timeout: watchdog,
                firedToken: stoppingToken,
                requestID: requestID,
                phase: .stoppingDevice,
                now: 130
            ),
            .recoverable(.phaseTimedOut(.stoppingDevice))
        )

        let rearmed = policy.rearmWatchdog(
            watchdog,
            at: 130,
            token: syncingToken
        )

        XCTAssertEqual(
            policy.resolve(
                timeout: rearmed,
                firedToken: stoppingToken,
                requestID: requestID,
                phase: .stoppingDevice,
                now: 160
            ),
            .unresolved,
            "The superseded token must remain inert"
        )
        XCTAssertEqual(
            policy.resolve(
                timeout: rearmed,
                firedToken: syncingToken,
                requestID: requestID,
                phase: .stoppingDevice,
                now: 159.999
            ),
            .unresolved
        )
        XCTAssertEqual(
            policy.resolve(
                timeout: rearmed,
                firedToken: syncingToken,
                requestID: requestID,
                phase: .stoppingDevice,
                now: 160
            ),
            .recoverable(.phaseTimedOut(.stoppingDevice))
        )
    }
}

final class NoomRecordingSubmissionEvidenceTests: XCTestCase {
    private let requestID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let otherRequestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let startMilliseconds: Int64 = 1_700_000_000_000

    private var policy: NoomRecordingFinalizationPolicy {
        NoomRecordingFinalizationPolicy(
            phaseBounds: [
                .stoppingDevice: 30,
                .syncingDevice: 45,
                .submitting: 105,
            ],
            correlationToleranceMilliseconds: 15_000
        )
    }

    private var attempt: NoomRecordingAttempt {
        NoomRecordingAttempt(
            requestID: requestID,
            experience: .spotCheck,
            startedAtMilliseconds: startMilliseconds
        )
    }

    private func evidence(
        requestID: UUID? = nil,
        experience: NoomRecordingExperience = .spotCheck,
        type: NoomRecordingSubmissionEvidence.SubmissionType = .biometrics,
        status: NoomRecordingSubmissionEvidence.Status,
        startedAtMilliseconds: Int64? = nil
    ) -> NoomRecordingSubmissionEvidence {
        NoomRecordingSubmissionEvidence(
            requestID: requestID ?? self.requestID,
            experience: experience,
            type: type,
            status: status,
            startedAtMilliseconds: startedAtMilliseconds ?? startMilliseconds
        )
    }

    func testMatchingPendingAndUploadedEvidenceResolveDurableTruthAtTheInclusiveTolerance() {
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    status: .pending,
                    startedAtMilliseconds: startMilliseconds + 15_000
                ),
                for: attempt
            ),
            .terminal(.submissionPending)
        )
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    status: .uploaded,
                    startedAtMilliseconds: startMilliseconds - 15_000
                ),
                for: attempt
            ),
            .terminal(.submissionUploaded)
        )
    }

    func testMatchingProcessedEvidenceResolvesProcessedTerminalTruth() {
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(status: .processed),
                for: attempt
            ),
            .terminal(.submissionProcessed)
        )
    }

    func testMatchingFailedSubmissionIsRecoverableRatherThanTerminal() {
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(status: .failed),
                for: attempt
            ),
            .recoverable(.submissionFailed)
        )
    }

    func testSubmissionFromAnotherRequestIsIgnored() {
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    requestID: otherRequestID,
                    status: .uploaded
                ),
                for: attempt
            ),
            .unresolved
        )
    }

    func testWrongExperienceOrSubmissionTypeIsIgnored() {
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    experience: .activity,
                    status: .uploaded
                ),
                for: attempt
            ),
            .unresolved
        )
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    type: .activity,
                    status: .uploaded
                ),
                for: attempt
            ),
            .unresolved
        )
    }

    func testSubmissionOlderOrNewerThanTheToleranceIsIgnored() {
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    status: .uploaded,
                    startedAtMilliseconds: startMilliseconds - 15_001
                ),
                for: attempt
            ),
            .unresolved
        )
        XCTAssertEqual(
            policy.resolve(
                submission: evidence(
                    status: .uploaded,
                    startedAtMilliseconds: startMilliseconds + 15_001
                ),
                for: attempt
            ),
            .unresolved
        )
    }

    func testStartCorrelationIsOverflowSafeNearInt64Extremes() {
        let nearMaximum = NoomRecordingAttempt(
            requestID: requestID,
            experience: .spotCheck,
            startedAtMilliseconds: Int64.max - 10_000
        )
        let nearbyEvidence = NoomRecordingSubmissionEvidence(
            requestID: requestID,
            experience: .spotCheck,
            type: .biometrics,
            status: .uploaded,
            startedAtMilliseconds: Int64.max
        )
        let oppositeExtreme = NoomRecordingSubmissionEvidence(
            requestID: requestID,
            experience: .spotCheck,
            type: .biometrics,
            status: .uploaded,
            startedAtMilliseconds: Int64.min
        )

        XCTAssertEqual(
            policy.resolve(submission: nearbyEvidence, for: nearMaximum),
            .terminal(.submissionUploaded)
        )
        XCTAssertEqual(
            policy.resolve(submission: oppositeExtreme, for: nearMaximum),
            .unresolved
        )
    }
}

final class NoomBiometricResultEvidenceTests: XCTestCase {
    private let requestID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let otherRequestID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    private let startMilliseconds: Int64 = 1_700_000_000_000

    private var policy: NoomRecordingFinalizationPolicy {
        NoomRecordingFinalizationPolicy(
            phaseBounds: [
                .stoppingDevice: 30,
                .syncingDevice: 45,
                .submitting: 105,
            ],
            correlationToleranceMilliseconds: 15_000
        )
    }

    private func attempt(
        requestID: UUID? = nil,
        experience: NoomRecordingExperience = .spotCheck,
        startedAtMilliseconds: Int64? = nil
    ) -> NoomRecordingAttempt {
        NoomRecordingAttempt(
            requestID: requestID ?? self.requestID,
            experience: experience,
            startedAtMilliseconds: startedAtMilliseconds ?? startMilliseconds
        )
    }

    private func result(
        requestID: UUID? = nil,
        startEpoch: Int64,
        outcome: NoomBiometricResultEvidence.Outcome = .success(resultID: "result-123")
    ) -> NoomBiometricResultEvidence {
        NoomBiometricResultEvidence(
            requestID: requestID ?? self.requestID,
            startEpoch: startEpoch,
            outcome: outcome
        )
    }

    func testEpochSecondsAndEpochMillisecondsMatchTheSameSpotCheckAttempt() {
        let currentAttempt = attempt()

        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: 1_700_000_005),
                for: currentAttempt
            ),
            .terminal(.biometricResult(resultID: "result-123"))
        )
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: 1_700_000_005_000),
                for: currentAttempt
            ),
            .terminal(.biometricResult(resultID: "result-123"))
        )
    }

    func testBiometricStartCorrelationIncludesExactlyFifteenSeconds() {
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: startMilliseconds + 15_000),
                for: attempt()
            ),
            .terminal(.biometricResult(resultID: "result-123"))
        )
    }

    func testAmbiguousOrInvalidEpochIsRejected() {
        let invalidEpochs: [Int64] = [
            Int64.min,
            -1,
            0,
            99_999_999_999,
            Int64.max,
        ]

        for epoch in invalidEpochs {
            XCTAssertEqual(
                policy.resolve(
                    biometricResult: result(startEpoch: epoch),
                    for: attempt()
                ),
                .unresolved,
                "Unexpectedly accepted epoch \(epoch)"
            )
        }
    }

    func testSuccessfulResultWithoutANonemptyIdentifierIsIgnored() {
        let emptyIdentifiers: [String?] = [nil, "", " \n\t "]

        for resultID in emptyIdentifiers {
            XCTAssertEqual(
                policy.resolve(
                    biometricResult: result(
                        startEpoch: startMilliseconds,
                        outcome: .success(resultID: resultID)
                    ),
                    for: attempt()
                ),
                .unresolved
            )
        }
    }

    func testMatchingBiometricErrorMapsToAppOwnedRecovery() {
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(
                    startEpoch: startMilliseconds,
                    outcome: .failure
                ),
                for: attempt()
            ),
            .recoverable(.biometricResultFailed)
        )
    }

    func testBiometricResultCannotResolveAnActivityAttempt() {
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: startMilliseconds),
                for: attempt(experience: .activity)
            ),
            .unresolved
        )
    }

    func testResultFromAnotherRequestCannotCompleteTheCurrentAttempt() {
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(
                    requestID: otherRequestID,
                    startEpoch: startMilliseconds
                ),
                for: attempt()
            ),
            .unresolved
        )
    }

    func testStaleOldOrPrematureNewResultCannotCompleteTheCurrentAttempt() {
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: startMilliseconds - 15_001),
                for: attempt()
            ),
            .unresolved
        )
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: startMilliseconds + 15_001),
                for: attempt()
            ),
            .unresolved
        )
    }

    func testEpochNormalizationRejectsValuesThatWouldOverflowSecondsConversion() {
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: Int64.max),
                for: attempt(startedAtMilliseconds: Int64.max - 1)
            ),
            .unresolved
        )
        XCTAssertEqual(
            policy.resolve(
                biometricResult: result(startEpoch: Int64.min),
                for: attempt(startedAtMilliseconds: Int64.min + 1)
            ),
            .unresolved
        )
    }
}

final class NoomRecordingOrchestrationEvidenceTests: XCTestCase {
    private let requestID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    private let otherRequestID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

    private var policy: NoomRecordingFinalizationPolicy {
        NoomRecordingFinalizationPolicy(
            phaseBounds: [
                .stoppingDevice: 30,
                .syncingDevice: 45,
                .submitting: 105,
            ],
            correlationToleranceMilliseconds: 15_000
        )
    }

    private var attempt: NoomRecordingAttempt {
        NoomRecordingAttempt(
            requestID: requestID,
            experience: .activity,
            startedAtMilliseconds: 1_700_000_000_000
        )
    }

    func testMatchingOrchestrationReturnRemainsValidTerminalEvidence() {
        XCTAssertEqual(
            policy.resolve(
                orchestrationReturn: attempt,
                for: attempt
            ),
            .terminal(.orchestrationReturned)
        )
    }

    func testStaleOrchestrationRequestExperienceOrStartIsIgnored() {
        let staleReturns = [
            NoomRecordingAttempt(
                requestID: otherRequestID,
                experience: .activity,
                startedAtMilliseconds: attempt.startedAtMilliseconds
            ),
            NoomRecordingAttempt(
                requestID: requestID,
                experience: .spotCheck,
                startedAtMilliseconds: attempt.startedAtMilliseconds
            ),
            NoomRecordingAttempt(
                requestID: requestID,
                experience: .activity,
                startedAtMilliseconds: attempt.startedAtMilliseconds - 1
            ),
        ]

        for staleReturn in staleReturns {
            XCTAssertEqual(
                policy.resolve(
                    orchestrationReturn: staleReturn,
                    for: attempt
                ),
                .unresolved
            )
        }
    }
}
