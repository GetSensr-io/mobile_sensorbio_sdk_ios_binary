import Foundation
import XCTest
import SensorBioSDK
@testable import NoomApp

final class SleepProcessingDomainTests: XCTestCase {
    private func makeIdentity(
        endDate: Int32 = 20260713,
        endTimestamp: Int64 = 1_700_000_000_000,
        timezoneMinutes: Int32 = -420
    ) -> SleepSessionIdentity {
        SleepSessionIdentity(
            endDate: endDate,
            endTimestamp: endTimestamp,
            timezoneMinutes: timezoneMinutes
        )
    }

    private func makeSummary(
        identity: SleepSessionIdentity,
        startMilliseconds: Int64 = 1_000,
        endMilliseconds: Int64 = 2_000,
        asleepMinutes: Int32 = 400
    ) -> SleepSessionSummary {
        SleepSessionSummary(
            identity: identity,
            startMilliseconds: startMilliseconds,
            endMilliseconds: endMilliseconds,
            asleepMinutes: asleepMinutes
        )
    }

    private func makeDetail() -> SB_SleepDetailDay {
        SB_SleepDetailDay(
            sleepScore: SB_SleepScore(
                processState: .processedSuccessfully,
                score: 91
            ),
            sleepTimeSec: 25_200,
            sleepOnset: 1_700_000_000_000,
            wakeUpTime: 1_700_025_200_000,
            timezone: -420,
            processing: false
        )
    }

    private func assertCodableRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func requireSendable<T: Sendable>(_: T) {}

    func testLocalDayUsesInjectedCalendarAndTimezoneAndHasStableCodableValue() throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-01-01T00:30:00Z")
        )
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US_POSIX")

        let utcDay = SleepLocalDay(
            date: instant,
            calendar: gregorian,
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )
        let losAngelesDay = SleepLocalDay(
            date: instant,
            calendar: gregorian,
            timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        )

        XCTAssertEqual(utcDay.rawValue, 20260101)
        XCTAssertEqual(losAngelesDay.rawValue, 20251231)
        XCTAssertNotEqual(utcDay, losAngelesDay)
        try assertCodableRoundTrip(utcDay)
        requireSendable(utcDay)
    }

    func testExactSessionIdentityIncludesEverySDKIdentityField() throws {
        let base = makeIdentity()
        let changedEndDate = makeIdentity(endDate: base.endDate + 1)
        let changedEndTimestamp = makeIdentity(endTimestamp: base.endTimestamp + 1)
        let changedTimezone = makeIdentity(timezoneMinutes: base.timezoneMinutes + 1)

        XCTAssertEqual(base.endDate, 20260713)
        XCTAssertEqual(base.endTimestamp, 1_700_000_000_000)
        XCTAssertEqual(base.timezoneMinutes, -420)
        XCTAssertEqual(
            Set([base, changedEndDate, changedEndTimestamp, changedTimezone]).count,
            4
        )
        try assertCodableRoundTrip(base)
        requireSendable(base)
    }

    func testSessionSummaryAdaptsAllRequiredFieldsFromSDKItem() {
        let item = SB_SleepItem(
            start: 1_700_000_000_000,
            end: 1_700_025_200_000,
            endTimestamp: 1_700_025_201_234,
            endDate: 20260713,
            timezone: -420,
            asleepTime: 402
        )

        let summary = SleepSessionSummary(item: item)

        XCTAssertEqual(
            summary.identity,
            SleepSessionIdentity(
                endDate: 20260713,
                endTimestamp: 1_700_025_201_234,
                timezoneMinutes: -420
            )
        )
        XCTAssertEqual(summary.startMilliseconds, 1_700_000_000_000)
        XCTAssertEqual(summary.endMilliseconds, 1_700_025_200_000)
        XCTAssertEqual(summary.asleepMinutes, 402)
        requireSendable(summary)
    }

    func testSelectionRetainsExactPreferredIdentityAndAllInputs() {
        let preferred = makeSummary(
            identity: makeIdentity(endTimestamp: 100),
            endMilliseconds: 10_000,
            asleepMinutes: 120
        )
        let longer = makeSummary(
            identity: makeIdentity(endTimestamp: 200),
            endMilliseconds: 20_000,
            asleepMinutes: 500
        )
        let sessions = [longer, preferred]

        let selection = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: preferred.identity,
            provisionalEndTimestampMilliseconds: 20_000,
            maxCorrelationDistanceMilliseconds: 1_000
        )

        XCTAssertEqual(selection.allSessions, sessions)
        XCTAssertEqual(selection.selectedSession, preferred)
        XCTAssertEqual(selection.reason, .retainedSelection)
    }

    func testSelectionCorrelatesNearestProvisionalEndWithinInclusiveBound() {
        let nearest = makeSummary(
            identity: makeIdentity(endTimestamp: 100),
            endMilliseconds: 10_500,
            asleepMinutes: 120
        )
        let longer = makeSummary(
            identity: makeIdentity(endTimestamp: 200),
            endMilliseconds: 30_000,
            asleepMinutes: 500
        )
        let sessions = [longer, nearest]

        let selection = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: 10_000,
            maxCorrelationDistanceMilliseconds: 500
        )

        XCTAssertEqual(selection.allSessions, sessions)
        XCTAssertEqual(selection.selectedSession, nearest)
        XCTAssertEqual(selection.reason, .correlatedDetection)
    }

    func testSelectionCorrelatesNearestAmongMultipleCandidatesInsideBound() {
        let nearest = makeSummary(
            identity: makeIdentity(endTimestamp: 100),
            endMilliseconds: 10_250,
            asleepMinutes: 120
        )
        let fartherButLonger = makeSummary(
            identity: makeIdentity(endTimestamp: 200),
            endMilliseconds: 10_900,
            asleepMinutes: 500
        )
        let sessions = [fartherButLonger, nearest]

        let selection = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: 10_000,
            maxCorrelationDistanceMilliseconds: 1_000
        )

        XCTAssertEqual(selection.allSessions, sessions)
        XCTAssertEqual(selection.selectedSession, nearest)
        XCTAssertEqual(selection.reason, .correlatedDetection)
    }

    func testEqualDistanceCorrelationUsesDeterministicFallbackComparator() {
        let cases: [(
            name: String,
            expected: SleepSessionSummary,
            other: SleepSessionSummary
        )] = [
            (
                name: "asleep minutes",
                expected: makeSummary(
                    identity: makeIdentity(endTimestamp: 100),
                    endMilliseconds: 9_500,
                    asleepMinutes: 401
                ),
                other: makeSummary(
                    identity: makeIdentity(endTimestamp: 900),
                    endMilliseconds: 10_500,
                    asleepMinutes: 400
                )
            ),
            (
                name: "actual end milliseconds",
                expected: makeSummary(
                    identity: makeIdentity(endTimestamp: 100),
                    endMilliseconds: 10_500,
                    asleepMinutes: 400
                ),
                other: makeSummary(
                    identity: makeIdentity(endTimestamp: 900),
                    endMilliseconds: 9_500,
                    asleepMinutes: 400
                )
            ),
            (
                name: "identity end timestamp",
                expected: makeSummary(
                    identity: makeIdentity(endTimestamp: 200),
                    endMilliseconds: 10_500,
                    asleepMinutes: 400
                ),
                other: makeSummary(
                    identity: makeIdentity(endTimestamp: 100),
                    endMilliseconds: 10_500,
                    asleepMinutes: 400
                )
            ),
        ]

        for testCase in cases {
            let inputOrders = [
                [testCase.expected, testCase.other],
                [testCase.other, testCase.expected],
            ]

            for sessions in inputOrders {
                let selection = SleepSessionSelection.select(
                    from: sessions,
                    preferredIdentity: nil,
                    provisionalEndTimestampMilliseconds: 10_000,
                    maxCorrelationDistanceMilliseconds: 500
                )

                XCTAssertEqual(
                    selection.selectedSession,
                    testCase.expected,
                    "Failed fallback tier: \(testCase.name)"
                )
                XCTAssertEqual(selection.reason, .correlatedDetection)
            }
        }
    }

    func testEqualDistanceCorrelationExactIdentityTieUsesEndDateThenTimezone() {
        let olderDateWithHigherTimezone = makeSummary(
            identity: makeIdentity(
                endDate: 20260712,
                endTimestamp: 200,
                timezoneMinutes: 600
            ),
            endMilliseconds: 10_500,
            asleepMinutes: 400
        )
        let laterDateWithLowerTimezone = makeSummary(
            identity: makeIdentity(
                endDate: 20260713,
                endTimestamp: 200,
                timezoneMinutes: -60
            ),
            endMilliseconds: 10_500,
            asleepMinutes: 400
        )
        let deterministicWinner = makeSummary(
            identity: makeIdentity(
                endDate: 20260713,
                endTimestamp: 200,
                timezoneMinutes: 60
            ),
            endMilliseconds: 10_500,
            asleepMinutes: 400
        )
        let sessions = [
            deterministicWinner,
            olderDateWithHigherTimezone,
            laterDateWithLowerTimezone,
        ]

        let first = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: 10_000,
            maxCorrelationDistanceMilliseconds: 500
        )
        let reordered = SleepSessionSelection.select(
            from: Array(sessions.reversed()),
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: 10_000,
            maxCorrelationDistanceMilliseconds: 500
        )

        XCTAssertEqual(first.selectedSession, deterministicWinner)
        XCTAssertEqual(reordered.selectedSession, deterministicWinner)
        XCTAssertEqual(first.reason, .correlatedDetection)
        XCTAssertEqual(reordered.reason, .correlatedDetection)
    }

    func testSelectionFallsBackWhenProvisionalEndIsOutsideBound() {
        let nearerButShorter = makeSummary(
            identity: makeIdentity(endTimestamp: 100),
            endMilliseconds: 11_001,
            asleepMinutes: 120
        )
        let longest = makeSummary(
            identity: makeIdentity(endTimestamp: 200),
            endMilliseconds: 30_000,
            asleepMinutes: 500
        )
        let sessions = [nearerButShorter, longest]

        let selection = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: 10_000,
            maxCorrelationDistanceMilliseconds: 1_000
        )

        XCTAssertEqual(selection.allSessions, sessions)
        XCTAssertEqual(selection.selectedSession, longest)
        XCTAssertEqual(selection.reason, .longestSessionDefault)
    }

    func testLongestFallbackUsesLatestEndTimestampThenExactIdentityDeterministically() {
        let older = makeSummary(
            identity: makeIdentity(endTimestamp: 100, timezoneMinutes: 0),
            asleepMinutes: 500
        )
        let lowerExactIdentity = makeSummary(
            identity: makeIdentity(endTimestamp: 200, timezoneMinutes: -60),
            asleepMinutes: 500
        )
        let deterministicWinner = makeSummary(
            identity: makeIdentity(endTimestamp: 200, timezoneMinutes: 60),
            asleepMinutes: 500
        )
        let sessions = [deterministicWinner, older, lowerExactIdentity]

        let first = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )
        let reordered = SleepSessionSelection.select(
            from: Array(sessions.reversed()),
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )

        XCTAssertEqual(first.allSessions, sessions)
        XCTAssertEqual(first.selectedSession, deterministicWinner)
        XCTAssertEqual(reordered.selectedSession, deterministicWinner)
        XCTAssertEqual(first.reason, .longestSessionDefault)
    }

    func testLongestFallbackPrefersLaterActualEndOverIdentityEndTimestamp() {
        let earlierActualEndWithLaterIdentityTimestamp = makeSummary(
            identity: makeIdentity(endTimestamp: 900),
            endMilliseconds: 10_000,
            asleepMinutes: 500
        )
        let deterministicWinner = makeSummary(
            identity: makeIdentity(endTimestamp: 100),
            endMilliseconds: 20_000,
            asleepMinutes: 500
        )
        let sessions = [
            deterministicWinner,
            earlierActualEndWithLaterIdentityTimestamp,
        ]

        let first = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )
        let reordered = SleepSessionSelection.select(
            from: Array(sessions.reversed()),
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )

        XCTAssertEqual(first.selectedSession, deterministicWinner)
        XCTAssertEqual(reordered.selectedSession, deterministicWinner)
        XCTAssertEqual(first.reason, .longestSessionDefault)
        XCTAssertEqual(reordered.reason, .longestSessionDefault)
    }

    func testPendingCandidatesWithIndependentGenerationsCoexistInDictionaryAndSet() {
        let day = SleepLocalDay(rawValue: 20260713)
        let firstKey = SleepCandidateKey(
            accountScope: "opaque-account-a",
            localDay: day,
            candidateGeneration: 1
        )
        let secondKey = SleepCandidateKey(
            accountScope: "opaque-account-a",
            localDay: day,
            candidateGeneration: 2
        )
        let first = SleepPendingCandidate(
            key: firstKey,
            correlationProvisionalEndTimestampMilliseconds: 10_000,
            boundSessionIdentity: nil,
            retryAttempt: 1,
            isRetryExhausted: false
        )
        let second = SleepPendingCandidate(
            key: secondKey,
            correlationProvisionalEndTimestampMilliseconds: 10_000,
            boundSessionIdentity: makeIdentity(),
            retryAttempt: 10,
            isRetryExhausted: true
        )

        let dictionary = [first.key: first, second.key: second]
        let candidates = Set([first, second])

        XCTAssertEqual(dictionary.count, 2)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertNil(dictionary[firstKey]?.boundSessionIdentity)
        XCTAssertEqual(dictionary[secondKey]?.boundSessionIdentity, makeIdentity())
        XCTAssertEqual(dictionary[secondKey]?.retryAttempt, 10)
        XCTAssertEqual(dictionary[secondKey]?.isRetryExhausted, true)
        requireSendable(first)
    }

    func testRequestKeyChangesForEveryExactLineageField() {
        let day = SleepLocalDay(rawValue: 20260713)
        let identity = makeIdentity()
        let base = SleepRequestKey(
            accountScope: "opaque-account-a",
            localDay: day,
            sessionIdentity: identity,
            requestGeneration: 7
        )
        let variations: [SleepRequestKey] = [
            SleepRequestKey(
                accountScope: "opaque-account-b",
                localDay: day,
                sessionIdentity: identity,
                requestGeneration: 7
            ),
            SleepRequestKey(
                accountScope: base.accountScope,
                localDay: SleepLocalDay(rawValue: 20260714),
                sessionIdentity: identity,
                requestGeneration: 7
            ),
            SleepRequestKey(
                accountScope: base.accountScope,
                localDay: day,
                sessionIdentity: makeIdentity(endDate: identity.endDate + 1),
                requestGeneration: 7
            ),
            SleepRequestKey(
                accountScope: base.accountScope,
                localDay: day,
                sessionIdentity: makeIdentity(endTimestamp: identity.endTimestamp + 1),
                requestGeneration: 7
            ),
            SleepRequestKey(
                accountScope: base.accountScope,
                localDay: day,
                sessionIdentity: makeIdentity(timezoneMinutes: identity.timezoneMinutes + 1),
                requestGeneration: 7
            ),
            SleepRequestKey(
                accountScope: base.accountScope,
                localDay: day,
                sessionIdentity: identity,
                requestGeneration: 8
            ),
        ]

        for variation in variations {
            XCTAssertNotEqual(base, variation)
        }
        XCTAssertEqual(Set([base] + variations).count, variations.count + 1)
        requireSendable(base)
    }

    func testOrthogonalStatesAreCodableAndOnlySuccessfulOutcomePermitsBodyStatus() throws {
        let outcomes: [SleepAnalysisOutcome] = [
            .unknown,
            .processing,
            .processedSuccessfully,
            .shortSession,
            .processedWithError,
            .invalidDailyAggregate,
        ]
        XCTAssertEqual(outcomes.filter(\.permitsBodyStatus), [.processedSuccessfully])

        try assertCodableRoundTrip(outcomes)
        try assertCodableRoundTrip([
            SleepCircadianAvailability.unknown,
            .generating,
            .available,
            .unavailable,
        ])
        try assertCodableRoundTrip([
            SleepTransportState.idle,
            .loading,
            .loaded,
            .failed,
        ])
        try assertCodableRoundTrip([SleepFreshness.fresh, .stale])
        requireSendable(outcomes)
    }

    func testAtomicSnapshotPreservesSourceDayAndRequiresExactSuccessfulLineage() {
        let sourceDay = SleepLocalDay(rawValue: 20260712)
        let identity = makeIdentity(endDate: sourceDay.rawValue)
        let snapshot = SleepAtomicSnapshot(
            accountScope: "opaque-account-a",
            localDay: sourceDay,
            sessionIdentity: identity,
            detail: makeDetail(),
            outcome: .processedSuccessfully,
            circadianAvailability: .available,
            sourceDay: sourceDay,
            requestGeneration: 9,
            freshness: .stale
        )

        XCTAssertEqual(snapshot.sourceDay, sourceDay)
        XCTAssertEqual(snapshot.localDay, sourceDay)
        XCTAssertEqual(snapshot.detail, makeDetail())
        XCTAssertEqual(snapshot.requestGeneration, 9)
        XCTAssertEqual(snapshot.freshness, .stale)
        XCTAssertTrue(
            snapshot.permitsBodyStatus(
                forAccountScope: "opaque-account-a",
                localDay: sourceDay,
                sessionIdentity: identity
            )
        )
        XCTAssertFalse(
            snapshot.permitsBodyStatus(
                forAccountScope: "opaque-account-b",
                localDay: sourceDay,
                sessionIdentity: identity
            )
        )
        XCTAssertFalse(
            snapshot.permitsBodyStatus(
                forAccountScope: "opaque-account-a",
                localDay: SleepLocalDay(rawValue: 20260713),
                sessionIdentity: identity
            )
        )
        XCTAssertFalse(
            snapshot.permitsBodyStatus(
                forAccountScope: "opaque-account-a",
                localDay: sourceDay,
                sessionIdentity: makeIdentity(
                    endDate: identity.endDate,
                    endTimestamp: identity.endTimestamp + 1,
                    timezoneMinutes: identity.timezoneMinutes
                )
            )
        )

        let nonSuccessOutcomes: [SleepAnalysisOutcome] = [
            .unknown,
            .processing,
            .shortSession,
            .processedWithError,
            .invalidDailyAggregate,
        ]
        for outcome in nonSuccessOutcomes {
            let blocked = SleepAtomicSnapshot(
                accountScope: snapshot.accountScope,
                localDay: snapshot.localDay,
                sessionIdentity: snapshot.sessionIdentity,
                detail: snapshot.detail,
                outcome: outcome,
                circadianAvailability: snapshot.circadianAvailability,
                sourceDay: snapshot.sourceDay,
                requestGeneration: snapshot.requestGeneration,
                freshness: snapshot.freshness
            )
            XCTAssertFalse(
                blocked.permitsBodyStatus(
                    forAccountScope: snapshot.accountScope,
                    localDay: snapshot.localDay,
                    sessionIdentity: snapshot.sessionIdentity
                ),
                "Expected \(outcome) to block Body Status"
            )
        }
        requireSendable(snapshot)
    }
}
