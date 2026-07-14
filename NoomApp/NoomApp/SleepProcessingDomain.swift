import Foundation
import SensorBioSDK

/// A calendar-local day encoded as the stable numeric `yyyyMMdd` value used by
/// the sleep domain. Date conversion depends only on the supplied calendar and
/// session time zone; it never consults process-global calendar defaults.
struct SleepLocalDay: Codable, Hashable, Sendable {
    let rawValue: Int32

    init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    init(date: Date, calendar: Calendar, timeZone: TimeZone) {
        var sessionCalendar = calendar
        sessionCalendar.timeZone = timeZone
        let components = sessionCalendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            preconditionFailure("The supplied calendar could not produce a local day")
        }
        rawValue = Int32(year * 10_000 + month * 100 + day)
    }
}

/// Exact SDK identity for one sleep session. Every field participates in the
/// synthesized equality and hash implementations.
struct SleepSessionIdentity: Codable, Hashable, Sendable {
    let endDate: Int32
    let endTimestamp: Int64
    let timezoneMinutes: Int32
}

/// SDK session data retained separately from exact identity for correlation,
/// deterministic selection, and eventual local start/end presentation.
struct SleepSessionSummary: Codable, Hashable, Sendable {
    let identity: SleepSessionIdentity
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let asleepMinutes: Int32

    init(
        identity: SleepSessionIdentity,
        startMilliseconds: Int64,
        endMilliseconds: Int64,
        asleepMinutes: Int32
    ) {
        self.identity = identity
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.asleepMinutes = asleepMinutes
    }

    init(item: SB_SleepItem) {
        self.init(
            identity: SleepSessionIdentity(
                endDate: item.endDate,
                endTimestamp: item.endTimestamp,
                timezoneMinutes: item.timezone
            ),
            startMilliseconds: item.start,
            endMilliseconds: item.end,
            asleepMinutes: item.asleepTime
        )
    }
}

/// The result of choosing one exact session while retaining the complete,
/// unmodified fetched input for multi-session UI and reconciliation.
struct SleepSessionSelection: Equatable, Sendable {
    enum Reason: String, Codable, Equatable, Sendable {
        case retainedSelection
        case correlatedDetection
        case longestSessionDefault
    }

    let allSessions: [SleepSessionSummary]
    let selectedSession: SleepSessionSummary?
    let reason: Reason?

    static func select(
        from sessions: [SleepSessionSummary],
        preferredIdentity: SleepSessionIdentity?,
        provisionalEndTimestampMilliseconds: Int64?,
        maxCorrelationDistanceMilliseconds: Int64
    ) -> SleepSessionSelection {
        if let preferredIdentity,
           let retained = sessions.first(where: { $0.identity == preferredIdentity }) {
            return SleepSessionSelection(
                allSessions: sessions,
                selectedSession: retained,
                reason: .retainedSelection
            )
        }

        if let provisionalEndTimestampMilliseconds,
           maxCorrelationDistanceMilliseconds >= 0 {
            let maximumDistance = UInt64(maxCorrelationDistanceMilliseconds)
            let correlated = sessions
                .filter {
                    timestampDistance(
                        $0.endMilliseconds,
                        provisionalEndTimestampMilliseconds
                    ) <= maximumDistance
                }
                .min { lhs, rhs in
                    let lhsDistance = timestampDistance(
                        lhs.endMilliseconds,
                        provisionalEndTimestampMilliseconds
                    )
                    let rhsDistance = timestampDistance(
                        rhs.endMilliseconds,
                        provisionalEndTimestampMilliseconds
                    )
                    if lhsDistance != rhsDistance {
                        return lhsDistance < rhsDistance
                    }
                    return prefersForDefault(lhs, over: rhs)
                }

            if let correlated {
                return SleepSessionSelection(
                    allSessions: sessions,
                    selectedSession: correlated,
                    reason: .correlatedDetection
                )
            }
        }

        guard let first = sessions.first else {
            return SleepSessionSelection(
                allSessions: sessions,
                selectedSession: nil,
                reason: nil
            )
        }
        let longest = sessions.dropFirst().reduce(first) { current, candidate in
            prefersForDefault(candidate, over: current) ? candidate : current
        }
        return SleepSessionSelection(
            allSessions: sessions,
            selectedSession: longest,
            reason: .longestSessionDefault
        )
    }

    private static func timestampDistance(_ lhs: Int64, _ rhs: Int64) -> UInt64 {
        let signBit = UInt64(1) << 63
        let orderedLHS = UInt64(bitPattern: lhs) ^ signBit
        let orderedRHS = UInt64(bitPattern: rhs) ^ signBit
        return orderedLHS >= orderedRHS
            ? orderedLHS - orderedRHS
            : orderedRHS - orderedLHS
    }

    private static func prefersForDefault(
        _ lhs: SleepSessionSummary,
        over rhs: SleepSessionSummary
    ) -> Bool {
        if lhs.asleepMinutes != rhs.asleepMinutes {
            return lhs.asleepMinutes > rhs.asleepMinutes
        }
        if lhs.endMilliseconds != rhs.endMilliseconds {
            return lhs.endMilliseconds > rhs.endMilliseconds
        }
        if lhs.identity.endTimestamp != rhs.identity.endTimestamp {
            return lhs.identity.endTimestamp > rhs.identity.endTimestamp
        }
        if lhs.identity.endDate != rhs.identity.endDate {
            return lhs.identity.endDate > rhs.identity.endDate
        }
        return lhs.identity.timezoneMinutes > rhs.identity.timezoneMinutes
    }
}

/// Independent key for a provisional detected candidate. `accountScope` is an
/// opaque caller-provided scope, not a raw account identifier.
struct SleepCandidateKey: Codable, Hashable, Sendable {
    let accountScope: String
    let localDay: SleepLocalDay
    let candidateGeneration: UInt64
}

/// Provisional timing is correlation-only numeric data. This type deliberately
/// provides no formatted or presentation-facing timing copy.
struct SleepPendingCandidate: Codable, Hashable, Sendable {
    let key: SleepCandidateKey
    let correlationProvisionalEndTimestampMilliseconds: Int64
    var boundSessionIdentity: SleepSessionIdentity?
    var retryAttempt: Int
    var isRetryExhausted: Bool
}

/// Full lineage for an exact-session detail request.
struct SleepRequestKey: Codable, Hashable, Sendable {
    let accountScope: String
    let localDay: SleepLocalDay
    let sessionIdentity: SleepSessionIdentity
    let requestGeneration: UInt64
}

enum SleepAnalysisOutcome: String, Codable, Equatable, Sendable {
    case unknown
    case processing
    case processedSuccessfully
    case shortSession
    case processedWithError
    case invalidDailyAggregate

    var permitsBodyStatus: Bool {
        self == .processedSuccessfully
    }
}

enum SleepCircadianAvailability: String, Codable, Equatable, Sendable {
    case unknown
    case generating
    case available
    case unavailable
}

enum SleepTransportState: String, Codable, Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

enum SleepFreshness: String, Codable, Equatable, Sendable {
    case fresh
    case stale
}

/// One indivisible daily-detail result and all lineage required to decide
/// whether that result may power Body Status.
struct SleepAtomicSnapshot: Equatable, Sendable {
    let accountScope: String
    let localDay: SleepLocalDay
    let sessionIdentity: SleepSessionIdentity
    let detail: SB_SleepDetailDay
    let outcome: SleepAnalysisOutcome
    let circadianAvailability: SleepCircadianAvailability
    let sourceDay: SleepLocalDay
    let requestGeneration: UInt64
    let freshness: SleepFreshness

    func permitsBodyStatus(
        forAccountScope accountScope: String,
        localDay: SleepLocalDay,
        sessionIdentity: SleepSessionIdentity
    ) -> Bool {
        outcome.permitsBodyStatus
            && self.accountScope == accountScope
            && self.localDay == localDay
            && sourceDay == localDay
            && self.sessionIdentity == sessionIdentity
    }
}
