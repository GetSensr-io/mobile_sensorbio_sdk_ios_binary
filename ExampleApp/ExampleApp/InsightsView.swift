import SwiftUI
import SensorBioSDK

struct InsightsView: View {
    @State private var state = InsightsState()

    var body: some View {
        List {
            personalSections
            populationFilterSection
            populationSections
        }
        .navigationTitle("Insights")
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

    // MARK: - Personal insights

    @ViewBuilder
    private var personalSections: some View {
        if state.isLoadingPersonal && state.personal == nil {
            Section {
                HStack { ProgressView(); Text("Loading insights\u{2026}").foregroundStyle(.secondary) }
            }
        } else if let error = state.personalError, state.personal == nil {
            Section {
                Label(error, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        } else if let insights = state.personal {
            if !insights.predictions.isEmpty {
                Section("Predictions") {
                    ForEach(insights.predictions.indices, id: \.self) { idx in
                        groupItems(insights.predictions[idx])
                    }
                }
            }
            if !insights.recommendations.isEmpty {
                Section("Recommendations") {
                    ForEach(insights.recommendations.indices, id: \.self) { idx in
                        groupItems(insights.recommendations[idx])
                    }
                }
            }
            if !insights.positiveInfluencers.isEmpty {
                Section("Positive Influencers") {
                    ForEach(insights.positiveInfluencers.indices, id: \.self) { idx in
                        influencerRow(insights.positiveInfluencers[idx])
                    }
                }
            }
            if !insights.negativeInfluencers.isEmpty {
                Section("Negative Influencers") {
                    ForEach(insights.negativeInfluencers.indices, id: \.self) { idx in
                        influencerRow(insights.negativeInfluencers[idx])
                    }
                }
            }
            if let exp = insights.suggestedExperiment {
                Section("Suggested Experiment") {
                    if !exp.reason.isEmpty {
                        Text(exp.reason).foregroundStyle(.secondary)
                    }
                    ForEach(exp.methodNames, id: \.self) { name in
                        Text(name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupItems(_ group: SB_InsightItemGroup) -> some View {
        ForEach(group.items.indices, id: \.self) { i in
            let item = group.items[i]
            let valueLabel = item.value.stringValue.isEmpty
                ? "\(Int(item.value.value)) \(item.value.unit)".trimmingCharacters(in: .whitespaces)
                : item.value.stringValue
            LabeledContent(item.name.isEmpty ? "Insight" : item.name, value: valueLabel)
            if !item.extraData.isEmpty {
                Text(item.extraData)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func influencerRow(_ influencer: SB_InsightInfluencer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(influencer.featureName)
                Spacer()
                Text("\(Int(influencer.featurePercentagesScaled))%")
                    .foregroundStyle(.secondary)
            }
            if let output = influencer.featureOutput {
                Text(output).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Population comparison

    @ViewBuilder
    private var populationFilterSection: some View {
        if let filters = state.filterList {
            @Bindable var s = state
            Section("Compare Against Population") {
                Picker("Gender", selection: $s.selectedGender) {
                    Text("All").tag(SB_PopulationGender.all)
                    Text("Male").tag(SB_PopulationGender.male)
                    Text("Female").tag(SB_PopulationGender.female)
                }
                Picker("Age", selection: $s.selectedAgeStart) {
                    ForEach(filters.ageGroups, id: \.ageStart) { group in
                        Text("\(group.ageStart)\u{2013}\(group.ageEnd)").tag(group.ageStart)
                    }
                }
                Picker("Metric", selection: $s.selectedMetricType) {
                    ForEach(filters.metrics, id: \.metricType.rawValue) { metric in
                        Text(metric.metricName.isEmpty ? "Metric" : metric.metricName)
                            .tag(metric.metricType)
                    }
                }
            }
            .onChange(of: state.selectedGender) { _, _ in Task { await state.loadPopulation() } }
            .onChange(of: state.selectedAgeStart) { _, _ in Task { await state.loadPopulation() } }
            .onChange(of: state.selectedMetricType) { _, _ in Task { await state.loadPopulation() } }
        }
    }

    @ViewBuilder
    private var populationSections: some View {
        if state.isLoadingPopulation {
            Section {
                HStack { ProgressView(); Text("Loading comparison\u{2026}").foregroundStyle(.secondary) }
            }
        } else if let error = state.populationError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } else {
            if let histogram = state.populationHistogram {
                Section(histogramSectionTitle(histogram)) {
                    if !histogram.insightText.isEmpty {
                        Text(histogram.insightText).foregroundStyle(.secondary)
                    }
                    if histogram.histogramData.isEmpty {
                        Text("No data").foregroundStyle(.secondary)
                    } else {
                        ForEach(histogram.histogramData.indices, id: \.self) { idx in
                            histogramRow(histogram, index: idx)
                        }
                    }
                }
            }
            if let radar = state.populationRadar {
                Section("Radar") {
                    if !radar.insightText.isEmpty {
                        Text(radar.insightText).foregroundStyle(.secondary)
                    }
                    if !radar.populationRadarText.isEmpty {
                        Text(radar.populationRadarText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(radar.points.indices, id: \.self) { idx in
                        radarRow(radar.points[idx])
                    }
                }
            }
        }
    }

    private func histogramSectionTitle(_ histogram: SB_PopulationInsightsHistogram) -> String {
        let metricName = state.selectedMetric?.metricName ?? "Metric"
        return "Histogram — \(metricName)"
    }

    @ViewBuilder
    private func histogramRow(_ histogram: SB_PopulationInsightsHistogram, index: Int) -> some View {
        let bin = histogram.histogramData[index]
        let isUserBin = Int(histogram.userXPosition) == index
        HStack {
            Text("\(formatted(bin.xStartValue))\u{2013}\(formatted(bin.xEndValue))")
                .foregroundStyle(isUserBin ? .orange : .primary)
                .fontWeight(isUserBin ? .semibold : .regular)
            Spacer()
            Text(formatted(bin.yValue))
                .foregroundStyle(isUserBin ? .orange : .secondary)
                .fontWeight(isUserBin ? .semibold : .regular)
            if isUserBin {
                Image(systemName: "person.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func radarRow(_ point: SB_RadarChartPoint) -> some View {
        HStack {
            Text(point.metricName)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("you: \(formatted(point.actualPair.userValue))")
                    .foregroundStyle(.orange)
                Text("pop: \(formatted(point.actualPair.populationValue))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func formatted(_ value: Float) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack { InsightsView() }
}
