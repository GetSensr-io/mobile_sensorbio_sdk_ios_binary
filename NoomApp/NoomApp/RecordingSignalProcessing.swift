import Foundation

/// Immutable, display-ready elapsed-time copy for the spot-check timer.
struct NoomSpotCheckTimerPresentation: Equatable, Sendable {
    let text: String
    let unit: String
    let accessibilityLabel: String

    init(elapsed: TimeInterval, target: TimeInterval) {
        let validTarget = target.isFinite && target > 0 ? target : nil
        let safeElapsed: TimeInterval

        if elapsed.isNaN || elapsed == -Double.infinity {
            safeElapsed = 0
        } else if elapsed == Double.infinity {
            safeElapsed = validTarget ?? 0
        } else if let validTarget {
            safeElapsed = min(max(elapsed, 0), validTarget)
        } else {
            safeElapsed = max(elapsed, 0)
        }

        let elapsedSeconds = Self.wholeSeconds(from: safeElapsed)
        text = Self.formattedTime(elapsedSeconds)
        unit = elapsedSeconds < 60 ? "SEC ELAPSED" : "MIN:SEC ELAPSED"

        let spokenElapsed = Self.spokenTime(elapsedSeconds)
        if let validTarget {
            let spokenTotal = Self.spokenTime(Self.wholeSeconds(from: validTarget))
            accessibilityLabel = "\(spokenElapsed) elapsed of \(spokenTotal) total."
        } else {
            accessibilityLabel = "\(spokenElapsed) elapsed. Total duration unavailable."
        }
    }

    private static func wholeSeconds(from interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }

        let floored = interval.rounded(.down)
        guard floored < Double(Int.max) else { return Int.max }
        return Int(floored)
    }

    private static func formattedTime(_ seconds: Int) -> String {
        guard seconds >= 60 else { return String(seconds) }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static func spokenTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes == 0 {
            return "\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")"
        }

        let spokenMinutes = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        guard remainingSeconds > 0 else { return spokenMinutes }

        return "\(spokenMinutes) \(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")"
    }
}

/// Signal-quality conversion shared by recording presentation code.
enum NoomSignalQuality {
    /// Sensor Bio iOS parity: `SpotCheckSignalTileViewModel` divides each raw SDK ratio
    /// by 10 before applying `10 * log10`. SB-1026 intentionally removed its EMA so
    /// every displayed value reflects the current packet rather than signal history.
    static func displayDecibels(rawSNR: Double) -> Double? {
        guard rawSNR.isFinite, rawSNR > 0, rawSNR != 255 else { return nil }

        let correctedRatio = rawSNR / 10
        guard correctedRatio.isFinite, correctedRatio > 0 else { return nil }

        let decibels = 10 * log10(correctedRatio)
        return decibels.isFinite ? decibels : nil
    }
}

/// Spreads queued PPG samples across display frames using bounded linear interpolation.
struct NoomPPGSampleInterpolator: Sendable {
    private static let defaultSamplesPerFrame = 0.22

    private let samplesPerFrame: Double
    private let maximumBufferedSamples: Int
    private var storage: [Double]
    private var readIndex = 0
    private var sampleCount = 0

    private var segmentStart: Double?
    private var segmentEnd: Double?
    private var segmentProgress = 0.0

    init(
        samplesPerFrame: Double = 0.22,
        maximumBufferedSamples: Int = 1_024
    ) {
        let safeMaximum = max(1, maximumBufferedSamples)
        let safeRate: Double
        if samplesPerFrame.isFinite, samplesPerFrame > 0 {
            // At most one source interval per frame ensures a local extremum is emitted
            // before interpolation begins toward the following sample.
            safeRate = min(samplesPerFrame, 1)
        } else {
            safeRate = Self.defaultSamplesPerFrame
        }

        self.samplesPerFrame = safeRate
        self.maximumBufferedSamples = safeMaximum
        self.storage = Array(repeating: 0, count: safeMaximum)
    }

    var bufferedSampleCount: Int { sampleCount }

    mutating func enqueue(_ sample: Double) {
        guard sample.isFinite else { return }

        if sampleCount == maximumBufferedSamples {
            // Overwrite the oldest pending sample and advance the FIFO head.
            storage[readIndex] = sample
            readIndex = (readIndex + 1) % maximumBufferedSamples
        } else {
            let writeIndex = (readIndex + sampleCount) % maximumBufferedSamples
            storage[writeIndex] = sample
            sampleCount += 1
        }
    }

    mutating func enqueue(_ samples: [Double]) {
        for sample in samples {
            enqueue(sample)
        }
    }

    /// Returns one finite interpolated value per display frame, or `nil` before data arrives.
    mutating func nextFrame() -> Double? {
        if segmentStart == nil {
            guard let firstSample = dequeue() else { return nil }
            segmentStart = firstSample
            segmentProgress = 0
            return firstSample
        }

        guard let start = segmentStart else { return nil }

        if segmentEnd == nil {
            segmentEnd = dequeue()
            segmentProgress = 0
        }

        guard let end = segmentEnd else {
            return start
        }

        let advancedProgress = segmentProgress + samplesPerFrame
        if advancedProgress >= 1 {
            // Emit each real sample exactly at a segment boundary. Carry fractional
            // cadence forward, but never skip a local peak in order to catch up.
            segmentStart = end
            segmentEnd = dequeue()
            segmentProgress = segmentEnd == nil ? 0 : advancedProgress - 1
            return end
        }

        segmentProgress = advancedProgress
        return Self.interpolate(from: start, to: end, fraction: advancedProgress)
    }

    mutating func reset() {
        storage = Array(repeating: 0, count: maximumBufferedSamples)
        readIndex = 0
        sampleCount = 0
        segmentStart = nil
        segmentEnd = nil
        segmentProgress = 0
    }

    private mutating func dequeue() -> Double? {
        guard sampleCount > 0 else { return nil }

        let sample = storage[readIndex]
        readIndex = (readIndex + 1) % maximumBufferedSamples
        sampleCount -= 1
        return sample
    }

    private static func interpolate(from start: Double, to end: Double, fraction: Double) -> Double {
        let value = start * (1 - fraction) + end * fraction
        guard value.isFinite else {
            // Both endpoints are finite. This fallback only applies to floating-point
            // overflow at extreme magnitudes and keeps the frame finite and bounded.
            return fraction < 0.5 ? start : end
        }

        return min(max(value, min(start, end)), max(start, end))
    }
}

/// Computes a padded PPG Y range and eases subsequent updates to avoid axis jumps.
struct NoomPPGYRangeSmoother: Sendable {
    private static let defaultMinimumRange = 0.5
    private static let defaultPaddingFraction = 0.1
    private static let defaultBlend = 0.1

    private let minimumRange: Double
    private let paddingFraction: Double
    private let blend: Double
    private var smoothedRange: ClosedRange<Double>?

    init(
        minimumRange: Double = 0.5,
        paddingFraction: Double = 0.1,
        blend: Double = 0.1
    ) {
        self.minimumRange = minimumRange.isFinite && minimumRange > 0
            ? minimumRange
            : Self.defaultMinimumRange
        self.paddingFraction = paddingFraction.isFinite
            ? min(max(paddingFraction, 0), 1)
            : Self.defaultPaddingFraction
        self.blend = blend.isFinite
            ? min(max(blend, 0), 1)
            : Self.defaultBlend
    }

    mutating func update(with samples: [Double]) -> ClosedRange<Double>? {
        guard let targetRange = targetRange(for: samples) else { return nil }

        let nextRange: ClosedRange<Double>
        if let smoothedRange {
            let lower: Double
            if targetRange.lowerBound < smoothedRange.lowerBound {
                lower = targetRange.lowerBound
            } else {
                lower = min(
                    Self.blendedValue(smoothedRange.lowerBound, toward: targetRange.lowerBound, by: blend),
                    targetRange.lowerBound
                )
            }

            let upper: Double
            if targetRange.upperBound > smoothedRange.upperBound {
                upper = targetRange.upperBound
            } else {
                upper = max(
                    Self.blendedValue(smoothedRange.upperBound, toward: targetRange.upperBound, by: blend),
                    targetRange.upperBound
                )
            }
            nextRange = lower <= upper ? lower...upper : targetRange
        } else {
            nextRange = targetRange
        }

        smoothedRange = nextRange
        return nextRange
    }

    mutating func reset() {
        smoothedRange = nil
    }

    private func targetRange(for samples: [Double]) -> ClosedRange<Double>? {
        var minimum: Double?
        var maximum: Double?

        for sample in samples where sample.isFinite {
            minimum = minimum.map { min($0, sample) } ?? sample
            maximum = maximum.map { max($0, sample) } ?? sample
        }

        guard let minimum, let maximum else { return nil }

        let observedRange = maximum - minimum
        guard observedRange.isFinite else { return nil }

        let effectiveRange = max(observedRange, minimumRange)
        let center = minimum + observedRange / 2
        let padding = effectiveRange * paddingFraction
        let targetMinimum = center - effectiveRange / 2 - padding
        let targetMaximum = center + effectiveRange / 2 + padding

        guard targetMinimum.isFinite,
              targetMaximum.isFinite,
              targetMinimum <= targetMaximum else {
            return nil
        }

        return targetMinimum...targetMaximum
    }

    private static func blendedValue(_ current: Double, toward target: Double, by fraction: Double) -> Double {
        let value = current + (target - current) * fraction
        if value.isFinite {
            return value
        }

        // A convex blend should remain finite for finite endpoints; use the target if
        // arithmetic overflow at extreme magnitudes prevents representing the midpoint.
        return target
    }
}
