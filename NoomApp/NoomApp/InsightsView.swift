import Foundation
import SwiftUI
import Charts
import SensorBioSDK

struct InsightsView: View {
    @State private var state = InsightsState()

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Signals") {
                NoomPill(title: "SDK-backed", color: NoomTheme.ink)
            }

            if state.isLoadingPersonal && state.personal == nil {
                loadingCard("Loading signals")
            } else if let error = state.personalError, state.personal == nil {
                NoomEmptyStateCard(
                    title: "Personal insights unavailable",
                    message: error,
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                )
            } else if let insights = state.personal,
                      !recommendationSummaries(insights).isEmpty {
                personalCards(insights)
            }

            populationInsightsSection
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let personalLoad: Void = state.loadPersonal()
            async let populationLoad: Void = state.loadPopulation()
            _ = await (personalLoad, populationLoad)
        }
        .refreshable {
            async let personalLoad: Void = state.loadPersonal()
            async let populationLoad: Void = state.retryPopulation()
            _ = await (personalLoad, populationLoad)
        }
    }

    @ViewBuilder
    private var populationInsightsSection: some View {
        NoomCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Population insights").noomSerifTitle(size: 28)
                Text("Compare your available signals with population distributions returned by the SDK.").noomBody()

                if let filters = state.populationFilters, !filters.metrics.isEmpty, !filters.ageGroups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters.metrics.indices, id: \.self) { index in
                                let metric = filters.metrics[index]
                                Button(metric.metricName.isEmpty ? "Metric \(index + 1)" : metric.metricName) {
                                    state.selectedPopulationMetric = metric
                                    Task { await state.loadPopulation() }
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(NoomTheme.logoBlack)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(metric.metricType == state.selectedPopulationMetric?.metricType ? NoomTheme.rose : Color.white.opacity(0.68), in: Capsule())
                                .accessibilityAddTraits(metric.metricType == state.selectedPopulationMetric?.metricType ? .isSelected : [])
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters.ageGroups.indices, id: \.self) { index in
                                let age = filters.ageGroups[index]
                                Button("\(age.ageStart)-\(age.ageEnd)") {
                                    state.selectedAgeGroup = age
                                    Task { await state.loadPopulation() }
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(NoomTheme.logoBlack)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(age.ageStart == state.selectedAgeGroup?.ageStart && age.ageEnd == state.selectedAgeGroup?.ageEnd ? NoomTheme.rose : Color.white.opacity(0.68), in: Capsule())
                                .accessibilityAddTraits(age.ageStart == state.selectedAgeGroup?.ageStart && age.ageEnd == state.selectedAgeGroup?.ageEnd ? .isSelected : [])
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach([SB_PopulationGender.all, .male, .female], id: \.rawValue) { gender in
                            Button(populationGenderLabel(gender)) {
                                state.selectedGender = gender
                                Task { await state.loadPopulation() }
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NoomTheme.logoBlack)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(gender == state.selectedGender ? NoomTheme.rose : Color.white.opacity(0.68), in: Capsule())
                            .accessibilityAddTraits(gender == state.selectedGender ? .isSelected : [])
                        }
                    }
                }

                if state.isLoadingPopulation {
                    loadingCard("Loading population insight")
                } else if let error = state.populationError {
                    VStack(alignment: .leading, spacing: 10) {
                        NoomEmptyStateCard(
                            title: "Population insight unavailable",
                            message: error,
                            systemImage: "chart.bar.xaxis"
                        )
                        Button("Try again") {
                            Task { await state.retryPopulation() }
                        }
                        .buttonStyle(NoomPrimaryButtonStyle())
                        .accessibilityHint("Reloads population filters and comparison data")
                    }
                } else if let histogram = state.populationHistogram {
                    populationHistogramCard(histogram)
                } else {
                    NoomEmptyStateCard(title: "No population insight yet", message: "Choose an available metric and age range to load comparison data.", systemImage: "person.3.fill")
                }

                if let radar = state.populationRadarChart {
                    let radarData = radarRelativePoints(radar.points)
                    if !radarData.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Signal profile").noomLabel()
                            if !radar.insightText.isEmpty { Text(radar.insightText).noomBody() }
                            if radarData.count >= 3 {
                                PopulationRadarChartView(points: radarData)
                            } else {
                                PopulationRadarFallbackView(points: radarData)
                            }
                            if !radar.populationRadarText.isEmpty { Text(radar.populationRadarText).noomBody() }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func populationHistogramCard(_ histogram: SB_PopulationInsightsHistogram) -> some View {
        let data = validHistogramData(histogram.histogramData)
        let userValue = histogram.userXValue.isFinite ? histogram.userXValue : nil
        let xAxisTitle = state.selectedPopulationMetric?.xLegend.isEmpty == false
            ? state.selectedPopulationMetric?.xLegend ?? "Value"
            : state.selectedPopulationMetric?.metricName ?? "Value"

        VStack(alignment: .leading, spacing: 10) {
            if !histogram.insightText.isEmpty { Text(histogram.insightText).noomBody() }
            if data.isEmpty {
                NoomEmptyStateCard(
                    title: "No chart data yet",
                    message: "This comparison did not include any valid population ranges.",
                    systemImage: "chart.bar.xaxis"
                )
            } else {
                PopulationHistogramChartView(data: data, userValue: userValue, xAxisTitle: xAxisTitle)
            }
        }
    }

    private func validHistogramData(_ pairs: [SB_HistogramPair]) -> [PopulationHistogramDatum] {
        pairs.enumerated().compactMap { index, pair in
            guard pair.xStartValue.isFinite,
                  pair.xEndValue.isFinite,
                  pair.yValue.isFinite,
                  pair.xEndValue > pair.xStartValue,
                  pair.yValue >= 0 else { return nil }
            return PopulationHistogramDatum(
                id: index,
                lowerBound: pair.xStartValue,
                upperBound: pair.xEndValue,
                population: pair.yValue
            )
        }
    }

    private func radarRelativePoints(_ points: [SB_RadarChartPoint]) -> [PopulationRadarDatum] {
        let valid = points.filter {
            !$0.metricName.isEmpty &&
            $0.relativePair.userValue.isFinite &&
            $0.relativePair.populationValue.isFinite
        }
        return valid.enumerated().map { index, point in
            PopulationRadarDatum(
                id: index,
                label: point.metricName,
                userRelative: min(1, max(0, point.relativePair.userValue)),
                populationRelative: min(1, max(0, point.relativePair.populationValue)),
                userActual: point.actualPair.userValue.isFinite ? point.actualPair.userValue : nil,
                populationActual: point.actualPair.populationValue.isFinite ? point.actualPair.populationValue : nil
            )
        }
    }

    @ViewBuilder
    private func personalCards(_ insights: SB_NewInsights) -> some View {
        let summaries = recommendationSummaries(insights)
        ForEach(summaries, id: \.title) { item in
            NoomSignalCardPublic(title: item.title, status: item.status, detail: item.detail, tint: item.tint)
        }
        if !summaries.isEmpty {
            feedbackControls
        }
    }

    private var feedbackControls: some View {
        NoomCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Was this insight helpful?").noomLabel()
                HStack(spacing: 10) {
                    Button("Helpful") { Task { await state.submitFeedback(.helpful) } }
                        .buttonStyle(NoomPrimaryButtonStyle())
                    Button("Not helpful") { Task { await state.submitFeedback(.notHelpful) } }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NoomTheme.logoBlack)
                }
                if let message = state.feedbackMessage { Text(message).noomBody() }
            }
        }
    }

    private func recommendationSummaries(_ insights: SB_NewInsights) -> [SignalSummary] {
        var summaries: [SignalSummary] = []
        if !insights.recommendations.isEmpty {
            summaries.append(SignalSummary(title: "Personal recommendation", status: "Returned", detail: firstItemText(from: insights.recommendations) ?? "Personal Insights returned a recommendation for today.", tint: NoomTheme.mint))
        }
        if !insights.predictions.isEmpty {
            summaries.append(SignalSummary(title: "Body signal forecast", status: "Updated", detail: firstItemText(from: insights.predictions) ?? "Noom is reading your latest recovery and movement patterns.", tint: Color.white.opacity(0.58)))
        }
        if !insights.positiveInfluencers.isEmpty {
            summaries.append(SignalSummary(title: "Supportive signals", status: "Helpful", detail: insights.positiveInfluencers.first?.featureName ?? "Sleep and activity are supporting today's plan.", tint: Color.white.opacity(0.58)))
        }
        if !insights.negativeInfluencers.isEmpty {
            summaries.append(SignalSummary(title: "Signals to watch", status: "Notice", detail: insights.negativeInfluencers.first?.featureName ?? "Some signals may call for a lighter plan.", tint: NoomTheme.rose))
        }
        if let exp = insights.suggestedExperiment, !exp.reason.isEmpty {
            let method = exp.methodNames.first.map { " - \($0)" } ?? ""
            summaries.append(SignalSummary(title: "Suggested experiment", status: "Read-only", detail: exp.reason + method + " Noom can save and track the related experiment from Today.", tint: NoomTheme.mint))
        }
        return summaries
    }

    private func firstItemText(from groups: [SB_InsightItemGroup]) -> String? {
        for group in groups {
            if let item = group.items.first {
                if !item.extraData.isEmpty { return item.extraData }
                if !item.name.isEmpty { return item.name }
            }
        }
        return nil
    }

    private func loadingCard(_ text: String) -> some View {
        NoomLoadingExperience(
            title: text,
            detail: "Looking for a useful pattern—not just another number.",
            systemImage: "sparkles",
            accent: NoomTheme.red,
            compact: true
        )
    }

    private func populationGenderLabel(_ gender: SB_PopulationGender) -> String {
        switch gender {
        case .all: return "All"
        case .male: return "Male"
        case .female: return "Female"
        @unknown default: return "All"
        }
    }
}

private struct PopulationHistogramDatum: Identifiable {
    let id: Int
    let lowerBound: Float
    let upperBound: Float
    let population: Float
}

private struct PopulationHistogramChartView: View {
    let data: [PopulationHistogramDatum]
    let userValue: Float?
    let xAxisTitle: String

    private var yAxisMaximum: Float {
        let maximum = data.map(\.population).filter { $0 > 0 }.max() ?? 0
        return maximum > 0 ? maximum * 1.12 : 1
    }

    private var domainData: [PopulationHistogramDatum] {
        let populated = data.filter { $0.population > 0 }
        return populated.isEmpty ? data : populated
    }

    private var xAxisDomain: ClosedRange<Float> {
        let values = domainData.flatMap { [$0.lowerBound, $0.upperBound] }
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        let span = max(upper - lower, Float.ulpOfOne)
        let widths = domainData
            .map { $0.upperBound - $0.lowerBound }
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        let medianWidth = widths.isEmpty ? span : widths[widths.count / 2]
        let padding = max(span * 0.04, min(medianWidth * 0.35, span * 0.10))
        let paddedLower = lower >= 0 ? max(0, lower - padding) : lower - padding
        return paddedLower...(upper + padding)
    }

    private var xAxisTickValues: [Float] {
        let lower = xAxisDomain.lowerBound
        let upper = xAxisDomain.upperBound
        let step = niceAxisStep(for: upper - lower)
        guard step.isFinite, step > 0 else { return [lower, upper] }

        let first = ceil(lower / step) * step
        var ticks: [Float] = []
        var value = first
        while value <= upper + (step * 0.001), ticks.count < 8 {
            ticks.append(value == -0 ? 0 : value)
            value += step
        }
        return ticks.count >= 2 ? ticks : [lower, upper]
    }

    private func niceAxisStep(for span: Float) -> Float {
        guard span.isFinite, span > 0 else { return 1 }
        let roughStep = Double(span) / 4
        let magnitude = pow(10, floor(log10(roughStep)))
        let normalized = roughStep / magnitude
        let factor: Double
        switch normalized {
        case ...1: factor = 1
        case ...2: factor = 2
        case ...2.5: factor = 2.5
        case ...5: factor = 5
        default: factor = 10
        }
        return Float(factor * magnitude)
    }

    private var visibleUserValue: Float? {
        guard let userValue, xAxisDomain.contains(userValue) else { return nil }
        return userValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(data) { bucket in
                    RectangleMark(
                        xStart: .value("Range start", bucket.lowerBound),
                        xEnd: .value("Range end", bucket.upperBound),
                        yStart: .value("Baseline", 0),
                        yEnd: .value("Population", bucket.population)
                    )
                    .foregroundStyle(NoomTheme.red.opacity(0.45))
                    .cornerRadius(4)
                    .accessibilityLabel("Population bucket \(MetricFormatting.humanNumber(bucket.lowerBound)) to \(MetricFormatting.humanNumber(bucket.upperBound))")
                    .accessibilityValue(MetricFormatting.humanNumber(bucket.population))
                }

                if let visibleUserValue {
                    RuleMark(x: .value("Your value", visibleUserValue))
                        .foregroundStyle(NoomTheme.logoBlack)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .annotation(position: .top, alignment: .center) {
                            Text("You")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(NoomTheme.logoBlack)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(NoomTheme.mint, in: Capsule())
                        }
                }
            }
            .chartXScale(domain: xAxisDomain)
            .chartYScale(domain: 0...yAxisMaximum)
            .chartXAxis {
                AxisMarks(values: xAxisTickValues) { axisValue in
                    AxisGridLine().foregroundStyle(NoomTheme.ink.opacity(0.08))
                    AxisTick().foregroundStyle(NoomTheme.ink.opacity(0.25))
                    AxisValueLabel {
                        if let value = axisValue.as(Float.self) {
                            Text(MetricFormatting.humanNumber(value))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(NoomTheme.ink.opacity(0.08))
                    AxisTick().foregroundStyle(NoomTheme.ink.opacity(0.25))
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel(xAxisTitle)
            .chartYAxisLabel("Population")
            .frame(height: 220)

            if let userValue {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Your value: \(MetricFormatting.humanNumber(userValue))").noomLabel()
                    if visibleUserValue == nil {
                        Text("Outside the displayed population range")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(NoomTheme.ink.opacity(0.68))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Population distribution for \(xAxisTitle)")
    }
}

private struct PopulationRadarDatum: Identifiable {
    let id: Int
    let label: String
    let userRelative: Float
    let populationRelative: Float
    let userActual: Float?
    let populationActual: Float?
}

private struct PopulationRadarFallbackView: View {
    let points: [PopulationRadarDatum]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comparison values").noomLabel()
            ForEach(points) { point in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(point.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Spacer()
                    Text("You \(displayValue(point.userActual, relative: point.userRelative)) • Population \(displayValue(point.populationActual, relative: point.populationRelative))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(NoomTheme.ink.opacity(0.74))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func displayValue(_ actual: Float?, relative: Float) -> String {
        actual.map { MetricFormatting.humanNumber($0) }
            ?? "\(MetricFormatting.humanNumber(relative * 100))%"
    }
}

private struct PopulationRadarChartView: View {
    let points: [PopulationRadarDatum]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Canvas { context, size in
                guard points.count >= 3 else { return }

                for level in 1...4 {
                    let fraction = Float(level) / 4
                    let path = polygonPath(values: Array(repeating: fraction, count: points.count), size: size)
                    context.stroke(path, with: .color(NoomTheme.ink.opacity(0.12)), lineWidth: 1)
                }

                for index in points.indices {
                    var axis = Path()
                    axis.move(to: center(in: size))
                    axis.addLine(to: vertex(index: index, value: 1, size: size))
                    context.stroke(axis, with: .color(NoomTheme.ink.opacity(0.10)), lineWidth: 1)
                }

                let populationPath = polygonPath(values: points.map(\.populationRelative), size: size)
                context.fill(populationPath, with: .color(NoomTheme.ink.opacity(0.10)))
                context.stroke(populationPath, with: .color(NoomTheme.ink.opacity(0.50)), lineWidth: 2)

                let userPath = polygonPath(values: points.map(\.userRelative), size: size)
                context.fill(userPath, with: .color(NoomTheme.red.opacity(0.16)))
                context.stroke(userPath, with: .color(NoomTheme.red), lineWidth: 3)

                for index in points.indices {
                    let labelPoint = vertex(index: index, value: 1.20, size: size)
                    context.draw(
                        Text(points[index].label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(NoomTheme.logoBlack),
                        at: labelPoint,
                        anchor: .center
                    )
                }
            }
            .frame(height: 200)

            HStack(spacing: 18) {
                legendItem(title: "You", color: NoomTheme.red)
                legendItem(title: "Population", color: NoomTheme.ink.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal profile comparison")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        points.map { point in
            let user = point.userActual.map { MetricFormatting.humanNumber($0) } ?? "unavailable"
            let population = point.populationActual.map { MetricFormatting.humanNumber($0) } ?? "unavailable"
            return "\(point.label): you \(user), population \(population)"
        }
        .joined(separator: "; ")
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).noomLabel()
        }
    }

    private func polygonPath(values: [Float], size: CGSize) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        for index in values.indices {
            let point = vertex(index: index, value: values[index], size: size)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func vertex(index: Int, value: Float, size: CGSize) -> CGPoint {
        let angle = -Double.pi / 2 + (Double(index) / Double(points.count)) * 2 * Double.pi
        let radius = min(size.width, size.height) * 0.32 * CGFloat(value)
        let center = center(in: size)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }
}

#if DEBUG
struct PopulationInsightsGraphPreviewView: View {
    private let histogram = [
        PopulationHistogramDatum(id: 0, lowerBound: 35, upperBound: 45, population: 12),
        PopulationHistogramDatum(id: 1, lowerBound: 45, upperBound: 55, population: 28),
        PopulationHistogramDatum(id: 2, lowerBound: 55, upperBound: 65, population: 42),
        PopulationHistogramDatum(id: 3, lowerBound: 65, upperBound: 75, population: 31),
        PopulationHistogramDatum(id: 4, lowerBound: 75, upperBound: 85, population: 14),
    ]

    private let radar = [
        PopulationRadarDatum(id: 0, label: "HRV", userRelative: 0.76, populationRelative: 0.60, userActual: 68, populationActual: 54),
        PopulationRadarDatum(id: 1, label: "Sleep", userRelative: 0.68, populationRelative: 0.74, userActual: 7.1, populationActual: 7.6),
        PopulationRadarDatum(id: 2, label: "Steps", userRelative: 0.82, populationRelative: 0.64, userActual: 9_840, populationActual: 7_600),
        PopulationRadarDatum(id: 3, label: "Resting HR", userRelative: 0.63, populationRelative: 0.70, userActual: 58, populationActual: 64),
        PopulationRadarDatum(id: 4, label: "Recovery", userRelative: 0.72, populationRelative: 0.66, userActual: 74, populationActual: 67),
    ]

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Signals") {
                NoomPill(title: "SDK-backed", color: NoomTheme.ink)
            }
            NoomCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Population insights").noomSerifTitle(size: 28)
                    Text("See how your recent signals compare with the broader population.").noomBody()
                    PopulationHistogramChartView(data: histogram, userValue: 62, xAxisTitle: "Resting heart rate (bpm)")
                    Divider().opacity(0.25)
                    Text("Signal profile").noomLabel()
                    PopulationRadarChartView(points: radar)
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PopulationHistogramMetricPreviewView: View {
    let metric: PopulationHistogramPreviewMetric

    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Insights") {
                NoomPill(title: "QA sample", color: NoomTheme.rose, foreground: NoomTheme.logoBlack)
            }
            NoomCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(metric.title).noomSerifTitle(size: 28)
                    Text("Synthetic development distribution with an intentionally oversized empty tail.")
                        .noomBody()
                    PopulationHistogramChartView(
                        data: metric.data,
                        userValue: metric.userValue,
                        xAxisTitle: metric.xAxisTitle
                    )
                }
            }
        }
        .navigationTitle("Population insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PopulationHistogramPreviewMetric {
    let title: String
    let xAxisTitle: String
    let userValue: Float
    fileprivate let data: [PopulationHistogramDatum]

    static let hrv = PopulationHistogramPreviewMetric(
        title: "HRV",
        xAxisTitle: "Milliseconds",
        userValue: 54,
        data: histogram(start: 20, width: 15, populations: [4, 13, 27, 22, 9], emptyTailStart: 95)
    )

    static let restingHR = PopulationHistogramPreviewMetric(
        title: "Resting HR",
        xAxisTitle: "Beats Per Min",
        userValue: 54,
        data: histogram(start: 35, width: 10, populations: [8, 20, 31, 24, 10], emptyTailStart: 85)
    )

    static let respiratory = PopulationHistogramPreviewMetric(
        title: "Respiratory rate",
        xAxisTitle: "Breaths Per Min",
        userValue: 14.8,
        data: histogram(start: 10, width: 2, populations: [5, 18, 30, 21, 7], emptyTailStart: 20)
    )

    static let sleep = PopulationHistogramPreviewMetric(
        title: "Total sleep",
        xAxisTitle: "Hours",
        userValue: 7.2,
        data: histogram(start: 4, width: 1, populations: [3, 12, 26, 29, 14, 5], emptyTailStart: 10)
    )

    private static func histogram(
        start: Float,
        width: Float,
        populations: [Float],
        emptyTailStart: Float
    ) -> [PopulationHistogramDatum] {
        let populated = populations.enumerated().map { index, population in
            let lower = start + (Float(index) * width)
            return PopulationHistogramDatum(
                id: index,
                lowerBound: lower,
                upperBound: lower + width,
                population: population
            )
        }
        return populated + [
            PopulationHistogramDatum(
                id: populations.count,
                lowerBound: emptyTailStart,
                upperBound: 1_000,
                population: 0
            )
        ]
    }
}
#endif

struct NoomSignalCardPublic: View {
    let title: String
    let status: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                Spacer()
                NoomPill(title: status, color: tint, foreground: NoomTheme.logoBlack)
            }
            Text(detail).noomBody()
        }
        .padding(14)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SignalSummary {
    let title: String
    let status: String
    let detail: String
    let tint: Color
}

#Preview {
    NavigationStack { InsightsView() }
}
