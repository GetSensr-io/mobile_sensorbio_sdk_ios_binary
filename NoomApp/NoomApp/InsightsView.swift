import SwiftUI
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
            } else if state.personalError != nil, state.personal == nil {
                noSignalsCard
            } else if let insights = state.personal {
                personalCards(insights)
            } else {
                noSignalsCard
            }

            populationInsightsSection
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await state.loadPersonal()
            await state.loadFilters()
            await state.loadPopulation()
        }
        .refreshable {
            await state.loadPersonal()
            await state.loadFilters()
            await state.loadPopulation()
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
                        }
                    }
                }

                if state.isLoadingPopulation {
                    loadingCard("Loading population insight")
                } else if let error = state.populationError {
                    NoomEmptyStateCard(title: "Population insight unavailable", message: error, systemImage: "chart.bar.xaxis")
                } else if let histogram = state.populationHistogram {
                    populationHistogramCard(histogram)
                } else {
                    NoomEmptyStateCard(title: "No population insight yet", message: "Choose an available metric and age range to load comparison data.", systemImage: "person.3.fill")
                }

                if let radar = state.populationRadarChart, !radar.insightText.isEmpty || !radar.populationRadarText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !radar.insightText.isEmpty { Text(radar.insightText).noomBody() }
                        if !radar.populationRadarText.isEmpty { Text(radar.populationRadarText).noomBody() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func populationHistogramCard(_ histogram: SB_PopulationInsightsHistogram) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !histogram.insightText.isEmpty { Text(histogram.insightText).noomBody() }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(histogram.histogramData.enumerated()), id: \.offset) { _, pair in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(NoomTheme.red.opacity(0.36))
                        .frame(height: CGFloat(max(6, min(120, pair.yValue * 120))))
                        .accessibilityLabel("Population bucket \(formatNumber(pair.xStartValue)) to \(formatNumber(pair.xEndValue))")
                }
            }
            .frame(height: 124, alignment: .bottom)
            Text("Your value: \(formatNumber(histogram.userXValue))").noomLabel()
        }
    }

    @ViewBuilder
    private func personalCards(_ insights: SB_NewInsights) -> some View {
        if insights.predictions.isEmpty && insights.recommendations.isEmpty && insights.positiveInfluencers.isEmpty && insights.negativeInfluencers.isEmpty && insights.suggestedExperiment == nil {
            NoomSignalCardPublic(title: "No signals yet", status: "Soon", detail: "Keep wearing Noom Band. Trends appear after enough context is available.", tint: NoomTheme.rose)
        } else {
            ForEach(recommendationSummaries(insights), id: \.title) { item in
                NoomSignalCardPublic(title: item.title, status: item.status, detail: item.detail, tint: item.tint)
            }
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
            summaries.append(SignalSummary(title: "Suggested experiment", status: "Read-only", detail: exp.reason + method + " Feature-gated until backend lifecycle is integrated.", tint: NoomTheme.mint))
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
        NoomCard {
            HStack(spacing: 12) {
                ProgressView().tint(NoomTheme.red)
                Text(text).noomBody()
            }
        }
    }

    private var noSignalsCard: some View {
        NoomEmptyStateCard(
            title: "Signals are still warming up",
            message: "Keep wearing Noom Band. Personalized insights appear after Noom has enough sleep, recovery, and movement context.",
            systemImage: "chart.line.uptrend.xyaxis"
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

    private func formatNumber(_ value: Float) -> String {
        value.rounded() == value ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }
}

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
