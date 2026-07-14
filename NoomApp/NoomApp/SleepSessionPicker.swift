import SwiftUI

struct SleepSessionPicker: View {
    let sessions: [SleepSessionSummary]
    let selectedIdentity: SleepSessionIdentity?
    let selectionReason: SleepSessionSelection.Reason?
    let onSelect: (SleepSessionIdentity) -> Void

    private var selectedSession: SleepSessionSummary? {
        guard let selectedIdentity else { return nil }
        return sessions.first(where: { $0.identity == selectedIdentity })
    }

    private var disclosure: String {
        if sessions.count == 1 {
            return "One sleep session found for this day."
        }
        switch selectionReason {
        case .retainedSelection:
            return "Your selected session is shown."
        case .correlatedDetection:
            return "Matched to the detected wake window."
        case .longestSessionDefault:
            return "The longest session is selected by default."
        case nil:
            return "Choose which sleep session to view."
        }
    }

    var body: some View {
        if sessions.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(Array(sessions.enumerated()), id: \.element.identity) { index, session in
                        Button {
                            onSelect(session.identity)
                        } label: {
                            if session.identity == selectedIdentity {
                                Label(sessionLabel(session, index: index), systemImage: "checkmark")
                            } else {
                                Text(sessionLabel(session, index: index))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.stars")
                            .accessibilityHidden(true)
                        Text(selectedSessionLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .accessibilityLabel("Selected sleep session, \(selectedSessionLabel)")
                .accessibilityHint("Opens all sleep sessions recorded for this day")
                .accessibilityIdentifier("sleep-session-picker")

                Text(disclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedSessionLabel: String {
        guard
            let selectedSession,
            let index = sessions.firstIndex(of: selectedSession)
        else {
            return "Choose a session"
        }
        return sessionLabel(selectedSession, index: index)
    }

    private func sessionLabel(_ session: SleepSessionSummary, index: Int) -> String {
        let duration = session.asleepMinutes > 0
            ? " · \(session.asleepMinutes / 60)h \(session.asleepMinutes % 60)m"
            : ""

        guard session.startMilliseconds > 0, session.endMilliseconds > 0 else {
            return "Session \(index + 1)\(duration)"
        }

        let start = Date(timeIntervalSince1970: TimeInterval(session.startMilliseconds) / 1_000)
        let end = Date(timeIntervalSince1970: TimeInterval(session.endMilliseconds) / 1_000)
        let seconds = Int(session.identity.timezoneMinutes) * 60
        let timeZone = TimeZone(secondsFromGMT: seconds) ?? .gmt
        let style = Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            timeZone: timeZone
        )
        return "\(start.formatted(style))–\(end.formatted(style))\(duration)"
    }
}
