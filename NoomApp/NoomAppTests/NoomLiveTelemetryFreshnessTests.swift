import XCTest
@testable import NoomApp

/// Regression suite for the background→resume live-telemetry freeze:
/// values frozen during suspension must not continue to render as LIVE.
final class NoomLiveTelemetryFreshnessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeModel(maximumSampleAge: TimeInterval = 15) -> NoomLiveTelemetryFreshness {
        NoomLiveTelemetryFreshness(maximumSampleAge: maximumSampleAge)
    }

    func testNoSamplesYetReportsAwaitingFirstSample() {
        let model = makeModel()

        XCTAssertEqual(model.presentation(at: start), .awaitingFirstSample)
        XCTAssertFalse(model.isLive(at: start))
    }

    func testFreshForegroundSampleReportsLive() {
        var model = makeModel()
        model.recordSample(at: start)

        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(5)), .live)
        XCTAssertTrue(model.isLive(at: start.addingTimeInterval(5)))
    }

    func testBackgroundingImmediatelyMarksTelemetryStale() {
        var model = makeModel()
        model.recordSample(at: start)
        model.setForeground(false, at: start.addingTimeInterval(1))

        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(2)), .stale)
        XCTAssertFalse(model.isLive(at: start.addingTimeInterval(2)))
    }

    func testForegroundReturnAloneDoesNotRestoreLive() {
        var model = makeModel()
        model.recordSample(at: start)
        model.setForeground(false, at: start.addingTimeInterval(1))
        model.setForeground(true, at: start.addingTimeInterval(300))

        // The 5-minute-old value must stay stale until a fresh sample lands.
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(300)), .stale)
    }

    func testFreshSampleAfterForegroundReturnRestoresLive() {
        var model = makeModel()
        model.recordSample(at: start)
        model.setForeground(false, at: start.addingTimeInterval(1))
        model.setForeground(true, at: start.addingTimeInterval(300))
        model.recordSample(at: start.addingTimeInterval(301))

        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(302)), .live)
    }

    func testBackgroundSampleDoesNotClearStalenessUntilForegroundSample() {
        var model = makeModel()
        model.recordSample(at: start)
        model.setForeground(false, at: start.addingTimeInterval(1))
        // Grace-window delivery while suspended must not flip back to live…
        model.recordSample(at: start.addingTimeInterval(2))

        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(3)), .stale)

        // …but a sample after the app is truly active again does.
        model.setForeground(true, at: start.addingTimeInterval(60))
        model.recordSample(at: start.addingTimeInterval(61))
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(62)), .live)
    }

    func testForegroundSampleGapBeyondMaximumAgeReportsStale() {
        var model = makeModel(maximumSampleAge: 15)
        model.recordSample(at: start)

        // Band drifted out of range without any scene change.
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(16)), .stale)
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(15)), .live)
    }

    func testResetReturnsToAwaitingFirstSampleForNewGeneration() {
        var model = makeModel()
        model.recordSample(at: start)
        model.setForeground(false, at: start.addingTimeInterval(1))
        model.reset()

        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(2)), .awaitingFirstSample)

        // New generation live path works after reset.
        model.setForeground(true, at: start.addingTimeInterval(3))
        model.recordSample(at: start.addingTimeInterval(4))
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(5)), .live)
    }

    func testRepeatedSceneTransitionsAreIdempotent() {
        var model = makeModel()
        model.recordSample(at: start)
        model.setForeground(true, at: start.addingTimeInterval(1)) // no-op
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(2)), .live)

        model.setForeground(false, at: start.addingTimeInterval(3))
        model.setForeground(false, at: start.addingTimeInterval(4)) // no-op
        XCTAssertEqual(model.presentation(at: start.addingTimeInterval(5)), .stale)
    }
}
