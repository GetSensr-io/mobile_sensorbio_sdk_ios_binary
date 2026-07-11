import Foundation
import SwiftUI
import Charts
import SensorBioSDK

enum Metric: Hashable {
    case recovery
    case sleep
    case steps
    case calories
    case hr
    case hrv
    case rr
    case inflammation

    var title: String {
        switch self {
        case .recovery: return "Recovery"
        case .sleep:    return "Sleep"
        case .steps:    return "Steps"
        case .calories: return "Active Calories"
        case .hr:       return "Resting Heart Rate"
        case .hrv:      return "Heart Rate Variability"
        case .rr:       return "Respiratory Rate"
        case .inflammation: return "Inflammation signal"
            @unknown default:
                return "?"
        }
    }
}

extension SB_ViewGranularity {
    var displayName: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
            @unknown default:
                return "?"
        }
    }
}

enum MetricFormatting {
    /// Localized metric formatter: `1,250` on a U.S. device rather than `1250`.
    static func humanNumber(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func humanNumber(_ value: Float, maximumFractionDigits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        if value.rounded() == value { return humanNumber(Int(value)) }
        return value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
    }

    static func humanNumber(_ value: Double, maximumFractionDigits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        if value.rounded() == value { return humanNumber(Int(value)) }
        return value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
    }

    /// SDK time-value points encode `timestamp` as a *local epoch* — the
    /// recording's local-time digits packed as if they were UTC. To render
    /// "what time did the device say it was when this sample was taken",
    /// extract h:mm via a UTC calendar so the digits come out literally.
    /// (`timezoneOffsetMinutes` is metadata only; not applied as a shift.)
    static func dayTimeLabel(timestampMillis: Int64, timezoneOffsetMinutes: Int32) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// `SB_DateValuePoint.date` is encoded as YYYYMMDD (e.g. 20260515).
    /// Format adapts to granularity: year view shows "Jan 2026"; smaller
    /// ranges show "Jan 5".
    static func rangeDateLabel(packedDate: Int32, granularity: SB_ViewGranularity) -> String {
        let raw = Int(packedDate)
        let year = raw / 10_000
        let month = (raw / 100) % 100
        let day = raw % 100
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = Calendar(identifier: .gregorian).date(from: comps) else {
            return "\(packedDate)"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = granularity == .year ? "MMM yyyy" : "MMM d"
        return fmt.string(from: date)
    }
}

/// A transparent morning wellness orientation based on overnight signals.
/// It is not a medical assessment, diagnosis, or treatment recommendation.
struct BodyStatusScore: Equatable {
    let score: Int
    let restingHeartRateComponent: Int
    let nocturnalHRVComponent: Int
    let sleepComponent: Int
    let inflammationSignalComponent: Int?
    let availableComponentCount: Int
    let totalComponentCount: Int = 4

    static func make(
        restingHeartRate: Int,
        nocturnalHRV: Int,
        sleepScore: Int,
        inflammationSignal: InflammationSignal? = nil
    ) -> BodyStatusScore? {
        guard (25...120).contains(restingHeartRate),
              (5...200).contains(nocturnalHRV),
              (0...100).contains(sleepScore) else {
            return nil
        }

        // Each valid input has a 25% base weight. If an approved input is
        // unavailable, valid inputs are renormalized and coverage is shown.
        // These fixed display normalizers are not a clinical interpretation.
        let restingHeartRateComponent = clamp(100 - Double(restingHeartRate - 45) * 1.6)
        let nocturnalHRVComponent = clamp(Double(nocturnalHRV - 10) * 1.4)
        let sleepComponent = clamp(Double(sleepScore))
        let inflammationSignalComponent = inflammationSignal?.validScore
        let components = [
            restingHeartRateComponent,
            nocturnalHRVComponent,
            sleepComponent
        ] + (inflammationSignalComponent.map { [$0] } ?? [])
        let score = weightedAverage(components)

        return BodyStatusScore(
            score: score,
            restingHeartRateComponent: restingHeartRateComponent,
            nocturnalHRVComponent: nocturnalHRVComponent,
            sleepComponent: sleepComponent,
            inflammationSignalComponent: inflammationSignalComponent,
            availableComponentCount: components.count
        )
    }

    var coverageDescription: String {
        "Based on \(availableComponentCount) of \(totalComponentCount) available signals"
    }

    var methodDescription: String {
        availableComponentCount == totalComponentCount
            ? "Four overnight signals, equal 25% weight"
            : "Four equal base inputs; available signals are reweighted"
    }

    var stage: String {
        switch score {
        case 80...: return "Strong"
        case 65..<80: return "Steady"
        case 45..<65: return "Building"
        default: return "Rest"
        }
    }

    var summary: String {
        switch score {
        case 80...: return "Your overnight signals look supportive today."
        case 65..<80: return "Your overnight signals look steady today."
        case 45..<65: return "Your overnight signals suggest an easier pace."
        default: return "Your overnight signals suggest making room for rest."
        }
    }

    private static func weightedAverage(_ components: [Int]) -> Int {
        Int((Double(components.reduce(0, +)) / Double(components.count)).rounded())
    }

    private static func clamp(_ value: Double) -> Int {
        Int(min(max(value, 0), 100).rounded())
    }
}

struct DetailHeaderControls: View {
    @Environment(AppDateContext.self) private var dateContext
    @Binding var granularity: SB_ViewGranularity

    var body: some View {
        @Bindable var ctx = dateContext
        VStack(spacing: 12) {
            NoomDayNavigator(selection: $ctx.selectedDate)
            Picker("Range", selection: $granularity) {
                Text("Day").tag(SB_ViewGranularity.day)
                Text("Week").tag(SB_ViewGranularity.week)
                Text("Month").tag(SB_ViewGranularity.month)
                Text("Year").tag(SB_ViewGranularity.year)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            Divider()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

/// Composite key for `.task(id:)` so detail screens refetch when either
/// the selected date or the granularity changes.
struct DetailLoadKey: Hashable {
    let date: Date
    let granularity: SB_ViewGranularity
}

struct BaselineObservation: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// A local personal reference built from completed days before the selected date.
/// It intentionally does not compare someone to a cohort aggregate or a clinical target.
struct PersonalBaseline: Equatable {
    enum Position: Equatable { case belowUsual, withinUsual, aboveUsual }

    let median: Double
    let lowerBound: Double
    let upperBound: Double
    let sampleCount: Int
    let observations: [BaselineObservation]
    var values: [Double] { observations.map(\.value) }

    static func make(
        currentValue: Double,
        historicalValues: [Double],
        selectedDate: Date = .now
    ) -> PersonalBaseline? {
        let calendar = Calendar.current
        let validValues = historicalValues.filter { $0.isFinite && $0 > 0 }
        let observations = validValues.enumerated().compactMap { index, value -> BaselineObservation? in
            let daysBeforeSelected = validValues.count - index
            guard let date = calendar.date(byAdding: .day, value: -daysBeforeSelected, to: selectedDate) else { return nil }
            return BaselineObservation(date: calendar.startOfDay(for: date), value: value)
        }
        return make(currentValue: currentValue, observations: observations)
    }

    static func make(currentValue: Double, observations: [BaselineObservation]) -> PersonalBaseline? {
        let observations = observations
            .filter { $0.value.isFinite && $0.value > 0 }
            .sorted { $0.date < $1.date }
        let values = observations.map(\.value)
        guard values.count >= PersonalBaselineLoader.minimumSampleCount else { return nil }
        let center = median(values)
        let medianAbsoluteDeviation = median(values.map { abs($0 - center) })
        // MAD resists a handful of unusual days better than an arithmetic mean.
        let robustSpread = max(medianAbsoluteDeviation * 1.4826 * 1.5, max(abs(center) * 0.03, 0.5))
        return PersonalBaseline(
            median: center,
            lowerBound: max(0, center - robustSpread),
            upperBound: center + robustSpread,
            sampleCount: values.count,
            observations: observations
        )
    }

    var usualRange: ClosedRange<Double> { lowerBound...upperBound }

    func position(of value: Double) -> Position {
        if value < lowerBound { return .belowUsual }
        if value > upperBound { return .aboveUsual }
        return .withinUsual
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[midpoint - 1] + sorted[midpoint]) / 2
            : sorted[midpoint]
    }
}

enum BaselineMetric {
    case steps, calories, restingHeartRate, hrv, respiratoryRate
}

enum PersonalBaselineLoader {
    static let trailingDays = 30
    static let minimumSampleCount = 14

    /// Loads the 30 completed calendar days before `selectedDate`; the selected
    /// day is deliberately excluded so it cannot influence its own comparison.
    static func trailingObservations(for metric: BaselineMetric, selectedDate: Date) async throws -> [BaselineObservation] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let startDate = calendar.date(byAdding: .day, value: -trailingDays, to: calendar.startOfDay(for: selectedDate)) else {
            return []
        }
        let stats = try await sensorBio.fetchDailyStats(
            startDate: packedDate(startDate),
            days: Int32(trailingDays),
            includeBiometrics: true,
            includeSleep: true,
            includeSteps: true
        )
        return stats.days.sorted { $0.date < $1.date }.compactMap { day in
            guard let date = unpackedDate(day.date), let value = value(for: metric, day: day) else { return nil }
            return BaselineObservation(date: date, value: value)
        }
    }

    static func trailingValues(for metric: BaselineMetric, selectedDate: Date) async throws -> [Double] {
        try await trailingObservations(for: metric, selectedDate: selectedDate).map(\.value)
    }

    private static func value(for metric: BaselineMetric, day: SB_DailyStats) -> Double? {
        switch metric {
        case .steps:
            return nonZero(day.physicalStats.reduce(0) { $0 + Double($1.steps) })
        case .calories:
            // `totalStepCalories` is the SDK's per-day movement-calorie field.
            return nonZero(day.physicalStats.reduce(0) { $0 + Double($1.totalStepCalories) })
        case .restingHeartRate:
            let mainSleep = day.sleepStats.first(where: { $0.mainSleep }) ?? day.sleepStats.first
            return mainSleep.flatMap { nonZero(Double($0.restingBpm)) }
        case .hrv:
            return robustDailyValue(day.cardioStats.map { Double($0.hrv) })
        case .respiratoryRate:
            return robustDailyValue(day.cardioStats.map { Double($0.brpm) })
        }
    }

    private static func robustDailyValue(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !valid.isEmpty else { return nil }
        let midpoint = valid.count / 2
        return valid.count.isMultiple(of: 2) ? (valid[midpoint - 1] + valid[midpoint]) / 2 : valid[midpoint]
    }

    private static func nonZero(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private static func unpackedDate(_ packedDate: Int32) -> Date? {
        let raw = Int(packedDate)
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = raw / 10_000
        components.month = (raw / 100) % 100
        components.day = raw % 100
        return components.date.map { Calendar.current.startOfDay(for: $0) }
    }

    private static func packedDate(_ date: Date) -> Int32 {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Int32((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
    }
}

struct MetricReading: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

enum BaselineDetailTone {
    case activity, heartRate, variability, respiratory, inflammation

    func comparisonCopy(_ position: PersonalBaseline.Position) -> String {
        switch (self, position) {
        case (.inflammation, .aboveUsual): return "More favorable than your recent usual"
        case (.inflammation, .belowUsual): return "Less favorable than your recent usual"
        case (.inflammation, .withinUsual): return "Within your recent usual"
        case (.activity, .aboveUsual): return "Above your recent usual"
        case (.activity, .belowUsual): return "Below your recent usual"
        case (.activity, .withinUsual): return "Within your recent usual"
        case (_, .aboveUsual): return "Higher than your recent usual"
        case (_, .belowUsual): return "Lower than your recent usual"
        case (_, .withinUsual): return "Within your recent usual"
        }
    }
}

/// Shared metric-detail surface inspired by the quiet hierarchy of current
/// wearable-health products: one clear value, a personal context card, then
/// supporting readings—not an undifferentiated table of raw samples.
struct BaselineMetricDetail: View {
    let title: String
    let symbol: String
    let accent: Color
    let date: Date
    let value: Double
    let valueText: String
    let unit: String
    let tone: BaselineDetailTone
    let baseline: PersonalBaseline?
    let readings: [MetricReading]
    var previewDisclosure: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let previewDisclosure {
                    NoomStateBanner(
                        title: "Preview sample",
                        detail: previewDisclosure,
                        systemImage: "wrench.and.screwdriver",
                        tint: NoomTheme.rose
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.68))
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                        Text(valueText)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(unit)
                            .font(.headline)
                            .foregroundStyle(Color.primary.opacity(0.68))
                    }
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.68))
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                baselineCard

                if let baseline, baseline.values.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your recent pattern")
                            .font(.headline)
                        InteractiveBaselineChart(
                            baseline: baseline,
                            selectedDate: date,
                            selectedValue: value,
                            unit: unit,
                            accent: accent
                        )
                        Text("Tap, hold, or drag across the chart to inspect the date (X) and value (Y). The shaded band is your typical range; the filled dot is the selected-day marker.")
                            .font(.footnote)
                            .foregroundStyle(Color.primary.opacity(0.68))
                    }
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if !readings.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Today’s readings")
                            .font(.headline)
                            .padding(.bottom, 8)
                        ForEach(readings) { reading in
                            HStack {
                                Text(reading.label)
                                Spacer()
                                Text(reading.value)
                                    .foregroundStyle(Color.primary.opacity(0.68))
                            }
                            .font(.subheadline)
                            .padding(.vertical, 13)
                            Divider()
                        }
                    }
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                Text("Your baseline uses up to the 30 completed days before this date and needs at least 14 valid days. It is personal context. Not a medical assessment.")
                    .font(.footnote)
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .noomDetailBackButton()
    }

    @ViewBuilder
    private var baselineCard: some View {
        if let baseline {
            let position = baseline.position(of: value)
            VStack(alignment: .leading, spacing: 8) {
                Text("30-day personal baseline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.68))
                Text(tone.comparisonCopy(position))
                    .font(.title3.weight(.bold))
                Text(deltaDescription(for: baseline))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.76))
                HStack {
                    Label("Typical range", systemImage: "chart.line.uptrend.xyaxis")
                    Spacer()
                    Text("\(MetricFormatting.humanNumber(baseline.lowerBound))–\(MetricFormatting.humanNumber(baseline.upperBound)) \(unit)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                Text("Based on \(baseline.sampleCount) valid completed days")
                    .font(.footnote)
                    .foregroundStyle(Color.primary.opacity(0.68))
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Building your 30-day personal baseline")
                    .font(.headline)
                Text("We’ll show your usual range after 14 valid completed days. Today’s data is still available below.")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.68))
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func deltaDescription(for baseline: PersonalBaseline) -> String {
        let delta = value - baseline.median
        let magnitude = MetricFormatting.humanNumber(abs(delta))
        let median = MetricFormatting.humanNumber(baseline.median)
        if delta == 0 { return "Matches your 30-day median (\(median) \(unit))" }
        let direction = delta > 0 ? "above" : "below"
        return "\(magnitude) \(unit) \(direction) your 30-day median (\(median) \(unit))"
    }
}

private struct InteractiveBaselineChart: View {
    let baseline: PersonalBaseline
    let selectedDate: Date
    let selectedValue: Double
    let unit: String
    let accent: Color

    @State private var selectedObservation: BaselineObservation?

    private var currentObservation: BaselineObservation {
        BaselineObservation(date: Calendar.current.startOfDay(for: selectedDate), value: selectedValue)
    }

    private var observations: [BaselineObservation] {
        (baseline.observations + [currentObservation]).sorted { $0.date < $1.date }
    }

    private var displayedObservation: BaselineObservation { selectedObservation ?? currentObservation }

    private var yDomain: ClosedRange<Double> {
        let values = observations.map(\.value) + [baseline.lowerBound, baseline.upperBound]
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.16, max(abs(high) * 0.04, 1))
        return max(0, low - padding)...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                coordinateChip(label: "X", value: displayedObservation.date.formatted(.dateTime.month(.abbreviated).day()))
                coordinateChip(label: "Y", value: "\(MetricFormatting.humanNumber(displayedObservation.value)) \(unit)")
            }

            let medianLine = baseline.median
            Chart {
                ForEach(observations) { observation in
                    AreaMark(
                        x: .value("Date", observation.date),
                        yStart: .value("Typical low", baseline.lowerBound),
                        yEnd: .value("Typical high", baseline.upperBound)
                    )
                    .foregroundStyle(accent.opacity(0.12))

                    LineMark(
                        x: .value("Date", observation.date),
                        y: .value("Value", observation.value)
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    if observation.id == currentObservation.id {
                        PointMark(
                            x: .value("Selected date", observation.date),
                            y: .value("Selected value", observation.value)
                        )
                        .foregroundStyle(accent)
                        .symbolSize(82)
                    }
                }

                RuleMark(y: .value("30-day median", medianLine))
                    .foregroundStyle(accent.opacity(0.40))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))

                if let selectedObservation {
                    RuleMark(x: .value("Inspected date", selectedObservation.date))
                        .foregroundStyle(accent.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    PointMark(
                        x: .value("Inspected date", selectedObservation.date),
                        y: .value("Inspected value", selectedObservation.value)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(105)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisTick().foregroundStyle(Color.secondary.opacity(0.45))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.14))
                    AxisValueLabel()
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    updateSelection(at: gesture.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }
            .frame(height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Interactive 30-day personal baseline chart")
            .accessibilityValue("X: \(displayedObservation.date.formatted(date: .abbreviated, time: .omitted)). Y: \(MetricFormatting.humanNumber(displayedObservation.value)) \(unit).")
            .accessibilityHint("Swipe up or down to inspect adjacent days.")
            .accessibilityAdjustableAction { direction in
                moveSelection(direction)
            }
        }
    }

    private func coordinateChip(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text("\(label):")
                .foregroundStyle(Color.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = min(max(location.x - frame.origin.x, 0), frame.width)
        guard let date: Date = proxy.value(atX: x) else { return }
        selectedObservation = observations.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func moveSelection(_ direction: AccessibilityAdjustmentDirection) {
        let current = displayedObservation
        guard let index = observations.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex: Int
        switch direction {
        case .increment: nextIndex = min(index + 1, observations.count - 1)
        case .decrement: nextIndex = max(index - 1, 0)
        @unknown default: return
        }
        selectedObservation = observations[nextIndex]
    }
}
