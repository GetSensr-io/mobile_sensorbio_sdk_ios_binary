import Foundation

struct NoomRecordingAttempt: Equatable, Sendable {
    let requestID: UUID
    let experience: NoomRecordingExperience
    let startedAtMilliseconds: Int64
}

enum NoomRecordingFinalizationPhase: Hashable, Sendable {
    case stoppingDevice
    case syncingDevice
    case submitting
}

struct NoomRecordingFinalizationWatchdog: Equatable, Sendable {
    let attempt: NoomRecordingAttempt
    let phase: NoomRecordingFinalizationPhase
    /// A timestamp from the caller's monotonic clock, such as system uptime.
    let enteredAt: TimeInterval
    let token: UUID

    fileprivate let hasValidTimeline: Bool

    var requestID: UUID { attempt.requestID }

    init(
        attempt: NoomRecordingAttempt,
        phase: NoomRecordingFinalizationPhase,
        enteredAt: TimeInterval,
        token: UUID
    ) {
        self.attempt = attempt
        self.phase = phase
        self.enteredAt = enteredAt
        self.token = token
        self.hasValidTimeline = enteredAt.isFinite
    }

    fileprivate init(
        attempt: NoomRecordingAttempt,
        phase: NoomRecordingFinalizationPhase,
        enteredAt: TimeInterval,
        token: UUID,
        hasValidTimeline: Bool
    ) {
        self.attempt = attempt
        self.phase = phase
        self.enteredAt = enteredAt
        self.token = token
        self.hasValidTimeline = hasValidTimeline
    }
}

struct NoomRecordingSubmissionEvidence: Equatable, Sendable {
    enum SubmissionType: Equatable, Sendable {
        case biometrics
        case activity
    }

    enum Status: Equatable, Sendable {
        case pending
        case uploaded
        case processed
        case failed
    }

    let requestID: UUID
    let experience: NoomRecordingExperience
    let type: SubmissionType
    let status: Status
    let startedAtMilliseconds: Int64
}

struct NoomBiometricResultEvidence: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case success(resultID: String?)
        case failure
    }

    let requestID: UUID
    let startEpoch: Int64
    let outcome: Outcome
}

enum NoomRecordingResolution: Equatable, Sendable {
    enum Terminal: Equatable, Sendable {
        case submissionPending
        case submissionUploaded
        case submissionProcessed
        case biometricResult(resultID: String)
        case orchestrationReturned
    }

    enum Recoverable: Equatable, Sendable {
        case phaseTimedOut(NoomRecordingFinalizationPhase)
        case submissionFailed
        case biometricResultFailed
    }

    case unresolved
    case terminal(Terminal)
    case recoverable(Recoverable)
}

struct NoomRecordingFinalizationPolicy: Sendable {
    private let phaseBounds: [NoomRecordingFinalizationPhase: TimeInterval]
    private let correlationToleranceMilliseconds: Int64

    init(
        phaseBounds: [NoomRecordingFinalizationPhase: TimeInterval],
        correlationToleranceMilliseconds: Int64
    ) {
        var validBounds: [NoomRecordingFinalizationPhase: TimeInterval] = [:]
        for phase in [
            NoomRecordingFinalizationPhase.stoppingDevice,
            .syncingDevice,
            .submitting,
        ] {
            guard let bound = phaseBounds[phase], bound.isFinite, bound >= 0 else {
                continue
            }
            validBounds[phase] = bound
        }

        self.phaseBounds = validBounds
        self.correlationToleranceMilliseconds = max(0, correlationToleranceMilliseconds)
    }

    func canStartRecording(
        connected _: Bool,
        isFullyConfigured: Bool
    ) -> Bool {
        isFullyConfigured
    }

    func armWatchdog(
        for attempt: NoomRecordingAttempt,
        phase: NoomRecordingFinalizationPhase,
        enteredAt: TimeInterval,
        token: UUID
    ) -> NoomRecordingFinalizationWatchdog {
        NoomRecordingFinalizationWatchdog(
            attempt: attempt,
            phase: phase,
            enteredAt: enteredAt,
            token: token
        )
    }

    func advanceWatchdog(
        _ watchdog: NoomRecordingFinalizationWatchdog,
        to phase: NoomRecordingFinalizationPhase,
        at enteredAt: TimeInterval,
        token: UUID
    ) -> NoomRecordingFinalizationWatchdog {
        NoomRecordingFinalizationWatchdog(
            attempt: watchdog.attempt,
            phase: phase,
            enteredAt: enteredAt,
            token: token,
            hasValidTimeline: watchdog.hasValidTimeline
                && enteredAt.isFinite
                && enteredAt >= watchdog.enteredAt
        )
    }

    func rearmWatchdog(
        _ watchdog: NoomRecordingFinalizationWatchdog,
        at enteredAt: TimeInterval,
        token: UUID
    ) -> NoomRecordingFinalizationWatchdog {
        NoomRecordingFinalizationWatchdog(
            attempt: watchdog.attempt,
            phase: watchdog.phase,
            enteredAt: enteredAt,
            token: token,
            hasValidTimeline: watchdog.hasValidTimeline
                && enteredAt.isFinite
                && enteredAt >= watchdog.enteredAt
        )
    }

    func resolve(
        timeout: NoomRecordingFinalizationWatchdog,
        firedToken: UUID,
        requestID: UUID,
        phase: NoomRecordingFinalizationPhase,
        now: TimeInterval
    ) -> NoomRecordingResolution {
        guard timeout.requestID == requestID,
              timeout.token == firedToken,
              timeout.phase == phase,
              let bound = phaseBounds[phase],
              bound.isFinite,
              bound >= 0,
              timeout.hasValidTimeline,
              timeout.enteredAt.isFinite,
              now.isFinite,
              now >= timeout.enteredAt else {
            return .unresolved
        }

        let elapsed = now - timeout.enteredAt
        guard elapsed.isFinite, elapsed >= bound else {
            return .unresolved
        }

        return .recoverable(.phaseTimedOut(phase))
    }

    func resolve(
        submission: NoomRecordingSubmissionEvidence,
        for attempt: NoomRecordingAttempt
    ) -> NoomRecordingResolution {
        guard submission.requestID == attempt.requestID,
              submission.experience == attempt.experience,
              submission.type == expectedSubmissionType(for: attempt.experience),
              startsCorrelate(
                  submission.startedAtMilliseconds,
                  attempt.startedAtMilliseconds
              ) else {
            return .unresolved
        }

        switch submission.status {
        case .pending:
            return .terminal(.submissionPending)
        case .uploaded:
            return .terminal(.submissionUploaded)
        case .processed:
            return .terminal(.submissionProcessed)
        case .failed:
            return .recoverable(.submissionFailed)
        }
    }

    func resolve(
        biometricResult: NoomBiometricResultEvidence,
        for attempt: NoomRecordingAttempt
    ) -> NoomRecordingResolution {
        guard attempt.experience == .spotCheck,
              biometricResult.requestID == attempt.requestID,
              let resultStartMilliseconds = normalizedEpochMilliseconds(
                  biometricResult.startEpoch
              ),
              startsCorrelate(
                  resultStartMilliseconds,
                  attempt.startedAtMilliseconds
              ) else {
            return .unresolved
        }

        switch biometricResult.outcome {
        case let .success(resultID):
            guard let resultID else { return .unresolved }
            let trimmedResultID = resultID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedResultID.isEmpty else { return .unresolved }
            return .terminal(.biometricResult(resultID: trimmedResultID))
        case .failure:
            return .recoverable(.biometricResultFailed)
        }
    }

    func resolve(
        orchestrationReturn: NoomRecordingAttempt,
        for attempt: NoomRecordingAttempt
    ) -> NoomRecordingResolution {
        guard orchestrationReturn == attempt else { return .unresolved }
        return .terminal(.orchestrationReturned)
    }

    private func expectedSubmissionType(
        for experience: NoomRecordingExperience
    ) -> NoomRecordingSubmissionEvidence.SubmissionType {
        switch experience {
        case .spotCheck:
            return .biometrics
        case .activity:
            return .activity
        }
    }

    private func startsCorrelate(_ lhs: Int64, _ rhs: Int64) -> Bool {
        if lhs >= rhs {
            let (difference, overflow) = lhs.subtractingReportingOverflow(rhs)
            return !overflow && difference <= correlationToleranceMilliseconds
        }

        let (difference, overflow) = rhs.subtractingReportingOverflow(lhs)
        return !overflow && difference <= correlationToleranceMilliseconds
    }

    private func normalizedEpochMilliseconds(_ epoch: Int64) -> Int64? {
        let secondsRange: Range<Int64> = 1_000_000_000..<10_000_000_000
        let millisecondsRange: Range<Int64> = 1_000_000_000_000..<10_000_000_000_000

        if secondsRange.contains(epoch) {
            let (milliseconds, overflow) = epoch.multipliedReportingOverflow(by: 1_000)
            return overflow ? nil : milliseconds
        }

        if millisecondsRange.contains(epoch) {
            return epoch
        }

        return nil
    }
}
