import SwiftUI

/// Shared, non-metric presentation for the account-scoped sleep lifecycle.
///
/// The banner deliberately accepts no SDK detail and no provisional timestamps.
/// It can therefore explain transport/analysis progress without presenting
/// detection timing as final sleep onset or wake time.
struct SleepProcessingBanner: View {
    let phase: SleepProcessingPhase
    let transportState: SleepTransportState
    let freshness: SleepFreshness
    let selectedDate: Date
    let sourceDate: Date?
    let canRetry: Bool
    let retryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        phase: SleepProcessingPhase,
        transportState: SleepTransportState,
        freshness: SleepFreshness,
        selectedDate: Date,
        sourceDate: Date? = nil,
        canRetry: Bool = false,
        retryAction: (() -> Void)? = nil
    ) {
        self.phase = phase
        self.transportState = transportState
        self.freshness = freshness
        self.selectedDate = selectedDate
        self.sourceDate = sourceDate
        self.canRetry = canRetry
        self.retryAction = retryAction
    }

    private var isPending: Bool {
        switch phase {
        case .detected, .stored, .uploaded, .processing:
            true
        case .idle, .ready, .shortSession, .retryableError, .calibrating:
            false
        }
    }

    private var tint: Color {
        switch phase {
        case .ready:
            Color.green
        case .shortSession, .calibrating:
            Color.orange
        case .retryableError:
            Color.red
        case .idle, .detected, .stored, .uploaded, .processing:
            Color.blue
        }
    }

    private var supportingMessage: String? {
        if transportState == .failed {
            return "We could not refresh sleep right now. Your last completed sleep is unchanged."
        }
        if freshness == .stale {
            return "Showing saved sleep while Noom+ waits for a fresh update."
        }
        return nil
    }

    private var historicalMessage: String? {
        guard
            let sourceDate,
            !Calendar.current.isDate(sourceDate, inSameDayAs: selectedDate)
        else {
            return nil
        }
        let completed = sourceDate.formatted(.dateTime.month(.abbreviated).day())
        let selected = selectedDate.formatted(.dateTime.month(.abbreviated).day())
        return "Showing completed sleep from \(completed) while \(selected) is still pending."
    }

    private var accessibilitySummary: String {
        let clauses = [phase.title, phase.detail, historicalMessage, supportingMessage]
            .compactMap { $0 }
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            .filter { !$0.isEmpty }
        return clauses.joined(separator: ". ") + "."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 42, height: 42)
                if isPending {
                    ProgressView()
                        .tint(tint)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: phase.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(phase.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(phase.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let historicalMessage {
                        Label(historicalMessage, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let supportingMessage {
                        Label(supportingMessage, systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityIdentifier("sleep-processing-banner")

                if canRetry, let retryAction {
                    Button("Retry sleep update", action: retryAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                        .accessibilityHint("Fetches the exact selected sleep session again")
                        .accessibilityIdentifier("sleep-processing-retry")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
    }
}
