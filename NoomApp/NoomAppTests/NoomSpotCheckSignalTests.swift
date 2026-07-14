import XCTest
@testable import NoomApp

final class NoomSpotCheckTimerPresentationTests: XCTestCase {
    func testNegativeElapsedClampsToZero() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: -3, target: 180)

        XCTAssertEqual(presentation.text, "0")
        XCTAssertEqual(presentation.unit, "SEC ELAPSED")
    }

    func testZeroElapsedUsesSecondsPresentation() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 0, target: 180)

        XCTAssertEqual(presentation.text, "0")
        XCTAssertEqual(presentation.unit, "SEC ELAPSED")
    }

    func testSubMinuteElapsedFloorsFractionalSeconds() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 59.9, target: 180)

        XCTAssertEqual(presentation.text, "59")
        XCTAssertEqual(presentation.unit, "SEC ELAPSED")
    }

    func testSixtySecondsSwitchesToMinuteSecondPresentation() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 60, target: 180)

        XCTAssertEqual(presentation.text, "1:00")
        XCTAssertEqual(presentation.unit, "MIN:SEC ELAPSED")
    }

    func testElapsedMinuteSecondPresentationIncludesSeconds() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 61, target: 180)

        XCTAssertEqual(presentation.text, "1:01")
        XCTAssertEqual(presentation.unit, "MIN:SEC ELAPSED")
    }

    func testVisualElapsedCapsAtTarget() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 600, target: 180)

        XCTAssertEqual(presentation.text, "3:00")
        XCTAssertEqual(presentation.unit, "MIN:SEC ELAPSED")
    }

    func testSubMinuteAccessibilitySpeaksSecondsAndTotalMinutes() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 59, target: 180)
        let label = presentation.accessibilityLabel.lowercased()

        XCTAssertEqual(presentation.text, "59")
        XCTAssertEqual(presentation.unit, "SEC ELAPSED")
        XCTAssertTrue(label.contains("59 seconds"))
        XCTAssertTrue(label.contains("3 minutes"))
        XCTAssertTrue(label.contains("elapsed"))
        XCTAssertTrue(label.contains("total"))
        XCTAssertFalse(label.contains("remaining"))
        XCTAssertFalse(label.contains("3:00"))
    }

    func testMinuteSecondAccessibilitySpeaksEachUnitAndTotalMinutes() {
        let presentation = NoomSpotCheckTimerPresentation(elapsed: 61, target: 180)
        let label = presentation.accessibilityLabel.lowercased()

        XCTAssertEqual(presentation.text, "1:01")
        XCTAssertEqual(presentation.unit, "MIN:SEC ELAPSED")
        XCTAssertTrue(label.contains("1 minute"))
        XCTAssertTrue(label.contains("1 second"))
        XCTAssertTrue(label.contains("3 minutes"))
        XCTAssertTrue(label.contains("elapsed"))
        XCTAssertTrue(label.contains("total"))
        XCTAssertFalse(label.contains("remaining"))
        XCTAssertFalse(label.contains("1:01"))
        XCTAssertFalse(label.contains("3:00"))
    }
}

final class NoomSignalQualityTests: XCTestCase {
    func testNonfiniteRawSNRIsUnavailable() {
        XCTAssertNil(NoomSignalQuality.displayDecibels(rawSNR: Double.nan))
        XCTAssertNil(NoomSignalQuality.displayDecibels(rawSNR: Double.infinity))
        XCTAssertNil(NoomSignalQuality.displayDecibels(rawSNR: -Double.infinity))
    }

    func testNonpositiveRawSNRIsUnavailable() {
        XCTAssertNil(NoomSignalQuality.displayDecibels(rawSNR: 0))
        XCTAssertNil(NoomSignalQuality.displayDecibels(rawSNR: -1))
    }

    func testSensorBioNoSignalSentinelIsUnavailable() {
        XCTAssertNil(NoomSignalQuality.displayDecibels(rawSNR: 255))
    }

    func testCurrentPacketConvertsFromSensorBioRatioToFiniteDecibels() throws {
        let cases: [(rawSNR: Double, expectedDecibels: Double)] = [
            (10, 0.0),
            (59, 7.708_520_116_421_442),
            (118, 10.718_820_073_061_256),
        ]

        for value in cases {
            let decibels = try XCTUnwrap(
                NoomSignalQuality.displayDecibels(rawSNR: value.rawSNR)
            )

            XCTAssertTrue(decibels.isFinite)
            XCTAssertEqual(decibels, value.expectedDecibels, accuracy: 0.000_000_001)
        }
    }

    func testConversionDoesNotCarryHistoryBetweenPackets() throws {
        let firstHigh = try XCTUnwrap(NoomSignalQuality.displayDecibels(rawSNR: 118))
        let low = try XCTUnwrap(NoomSignalQuality.displayDecibels(rawSNR: 10))
        let secondHigh = try XCTUnwrap(NoomSignalQuality.displayDecibels(rawSNR: 118))

        XCTAssertEqual(firstHigh, 10.718_820_073_061_256, accuracy: 0.000_000_001)
        XCTAssertEqual(low, 0.0, accuracy: 0.000_000_001)
        XCTAssertEqual(secondHigh, firstHigh, accuracy: 0.000_000_001)
    }
}

final class NoomPPGSampleInterpolatorTests: XCTestCase {
    func testEnqueueRetainsEveryFiniteSampleAndRejectsNonfiniteValues() {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.5,
            maximumBufferedSamples: 16
        )

        interpolator.enqueue([
            0,
            Double.nan,
            1,
            Double.infinity,
            -Double.infinity,
            2,
        ])

        XCTAssertEqual(interpolator.bufferedSampleCount, 3)
    }

    func testBufferedSamplesAreBounded() {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.5,
            maximumBufferedSamples: 3
        )

        interpolator.enqueue([0, 1, 2, 3, 4, 5])

        XCTAssertEqual(interpolator.bufferedSampleCount, 3)
    }

    func testBurstIsEmittedAsDeterministicLinearFramesWithoutOvershoot() throws {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.25,
            maximumBufferedSamples: 16
        )
        interpolator.enqueue([2, 6])

        let frames = try takeFrames(5, from: &interpolator)

        assertEqual(frames, [2, 3, 4, 5, 6])
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame, 2)
            XCTAssertLessThanOrEqual(frame, 6)
        }
    }

    func testBurstLocalPeakIsReachedBeforeInterpolationDescends() throws {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.5,
            maximumBufferedSamples: 16
        )
        interpolator.enqueue([0, 1, 0])

        let frames = try takeFrames(5, from: &interpolator)

        assertEqual(frames, [0.0, 0.5, 1.0, 0.5, 0.0])
    }

    func testDescendingBurstEmitsInitialMaximumAndEveryRawEndpoint() throws {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.25,
            maximumBufferedSamples: 16
        )
        interpolator.enqueue([6, 2, -2])

        let frames = try takeFrames(9, from: &interpolator)

        assertEqual(frames, [6, 5, 4, 3, 2, 1, 0, -1, -2])
        XCTAssertEqual(frames.first, 6)
        XCTAssertTrue(frames.contains(2))
        XCTAssertEqual(frames.last, -2)
    }

    func testSingleSampleHoldsFiniteValueWhenNoNewSampleArrives() throws {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.22,
            maximumBufferedSamples: 16
        )
        interpolator.enqueue([42])

        for _ in 0..<30 {
            let frame = try XCTUnwrap(interpolator.nextFrame())
            XCTAssertTrue(frame.isFinite)
            XCTAssertEqual(frame, 42, accuracy: 0.000_000_001)
        }
    }

    func testResetClearsHistoryAndBufferedSamples() throws {
        var interpolator = NoomPPGSampleInterpolator(
            samplesPerFrame: 0.5,
            maximumBufferedSamples: 16
        )
        interpolator.enqueue([0, 1, 2])
        _ = interpolator.nextFrame()

        interpolator.reset()

        XCTAssertEqual(interpolator.bufferedSampleCount, 0)
        XCTAssertNil(interpolator.nextFrame())

        interpolator.enqueue([7])
        let firstFrameAfterReset = try XCTUnwrap(interpolator.nextFrame())
        XCTAssertEqual(firstFrameAfterReset, 7, accuracy: 0.000_000_001)
    }

    private func takeFrames(
        _ count: Int,
        from interpolator: inout NoomPPGSampleInterpolator
    ) throws -> [Double] {
        var frames: [Double] = []
        for _ in 0..<count {
            frames.append(try XCTUnwrap(interpolator.nextFrame()))
        }
        return frames
    }

    private func assertEqual(
        _ actual: [Double],
        _ expected: [Double],
        accuracy: Double = 0.000_000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(
                actualValue,
                expectedValue,
                accuracy: accuracy,
                file: file,
                line: line
            )
        }
    }
}

final class NoomPPGYRangeSmootherTests: XCTestCase {
    func testSingleValueUsesMinimumRangeAndTenPercentPadding() throws {
        var smoother = makeSmoother()

        let range = try XCTUnwrap(smoother.update(with: [10]))

        XCTAssertEqual(range.lowerBound, 9.7, accuracy: 0.000_000_001)
        XCTAssertEqual(range.upperBound, 10.3, accuracy: 0.000_000_001)
    }

    func testRangeIgnoresNonfiniteValues() throws {
        var smoother = makeSmoother()

        let range = try XCTUnwrap(
            smoother.update(with: [Double.nan, 10, Double.infinity, -Double.infinity])
        )

        XCTAssertEqual(range.lowerBound, 9.7, accuracy: 0.000_000_001)
        XCTAssertEqual(range.upperBound, 10.3, accuracy: 0.000_000_001)
    }

    func testAllNonfiniteValuesDoNotCreateRange() {
        var smoother = makeSmoother()

        let range = smoother.update(with: [Double.nan, Double.infinity, -Double.infinity])

        XCTAssertNil(range)
    }

    func testSuddenUpwardShiftExpandsOutwardImmediatelyAndContractsInwardGradually() throws {
        var smoother = makeSmoother()
        _ = smoother.update(with: [0, 1])

        let range = try XCTUnwrap(smoother.update(with: [10, 11]))

        XCTAssertEqual(range.lowerBound, 0.9, accuracy: 0.000_000_001)
        XCTAssertEqual(range.upperBound, 11.1, accuracy: 0.000_000_001)
        assertRange(range, contains: [10, 11], paddedTarget: 9.9...11.1)
    }

    func testDownwardWiderPeakExpandsImmediatelyThenContractsInwardGradually() throws {
        var smoother = makeSmoother()
        _ = smoother.update(with: [10, 11])

        let expanded = try XCTUnwrap(smoother.update(with: [-10, 12]))

        XCTAssertEqual(expanded.lowerBound, -12.2, accuracy: 0.000_000_001)
        XCTAssertEqual(expanded.upperBound, 14.2, accuracy: 0.000_000_001)
        assertRange(expanded, contains: [-10, 12], paddedTarget: -12.2...14.2)

        let contracted = try XCTUnwrap(smoother.update(with: [0, 1]))

        XCTAssertEqual(contracted.lowerBound, -10.99, accuracy: 0.000_000_001)
        XCTAssertEqual(contracted.upperBound, 12.89, accuracy: 0.000_000_001)
        assertRange(contracted, contains: [0, 1], paddedTarget: -0.1...1.1)
    }

    func testResetClearsSmoothedRangeHistory() throws {
        var smoother = makeSmoother()
        _ = smoother.update(with: [0, 1])
        _ = smoother.update(with: [10, 11])

        smoother.reset()
        let range = try XCTUnwrap(smoother.update(with: [10, 11]))

        XCTAssertEqual(range.lowerBound, 9.9, accuracy: 0.000_000_001)
        XCTAssertEqual(range.upperBound, 11.1, accuracy: 0.000_000_001)
    }

    private func makeSmoother() -> NoomPPGYRangeSmoother {
        NoomPPGYRangeSmoother(
            minimumRange: 0.5,
            paddingFraction: 0.1,
            blend: 0.1
        )
    }

    private func assertRange(
        _ range: ClosedRange<Double>,
        contains samples: [Double],
        paddedTarget: ClosedRange<Double>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for sample in samples where sample.isFinite {
            XCTAssertTrue(
                range.contains(sample),
                "Range clipped sample \(sample)",
                file: file,
                line: line
            )
        }
        XCTAssertLessThanOrEqual(
            range.lowerBound,
            paddedTarget.lowerBound,
            "Range clipped lower target padding",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            range.upperBound,
            paddedTarget.upperBound,
            "Range clipped upper target padding",
            file: file,
            line: line
        )
    }
}
