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
                personalInsightUnavailableCard
            } else if let insights = state.personal {
                personalCards(insights)
            } else {
                personalInsightUnavailableCard
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await state.loadPersonal()
        }
        .refreshable {
            await state.loadPersonal()
        }
    }

    @ViewBuilder
    private func personalCards(_ insights: SB_NewInsights) -> some View {
        if insights.predictions.isEmpty && insights.recommendations.isEmpty && insights.positiveInfluencers.isEmpty && insights.negativeInfluencers.isEmpty && insights.suggestedExperiment == nil {
            NoomSignalCardPublic(
                title: "No new personal insight",
                status: "Synced",
                detail: "Your health signals remain available. There isn't a new personalized recommendation right now.",
                tint: NoomTheme.mint
            )
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

    private var personalInsightUnavailableCard: some View {
        NoomEmptyStateCard(
            title: "No new personal insight",
            message: "Your health signals remain available. Personalized recommendations will appear here when the insights service returns an update.",
            systemImage: "chart.line.uptrend.xyaxis"
        )
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
