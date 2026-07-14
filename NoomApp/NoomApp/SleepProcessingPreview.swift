#if DEBUG
import SwiftUI

struct SleepProcessingLifecyclePreview: View {
    let route: String
    private let selectedDate = Date()

    var body: some View {
        NoomScreen(spacing: 14, bottomPadding: 36) {
            NoomTopBar(label: "Sleep lifecycle") {
                NoomPill(
                    title: "DEBUG fixture",
                    color: NoomTheme.rose,
                    foreground: NoomTheme.logoBlack
                )
            }

            NoomStateBanner(
                title: "Synthetic development state",
                detail: "Layout and accessibility fixture only. This is not personal health data and no SDK request is made.",
                systemImage: "wrench.and.screwdriver",
                tint: NoomTheme.rose
            )

            if route == "sleep_processing_multiple_sessions" {
                SleepSessionPicker(
                    sessions: sampleSessions,
                    selectedIdentity: sampleSessions.last?.identity,
                    selectionReason: .longestSessionDefault,
                    onSelect: { _ in }
                )
            }

            SleepProcessingBanner(
                phase: fixture.phase,
                transportState: fixture.transport,
                freshness: fixture.freshness,
                selectedDate: selectedDate,
                sourceDate: fixture.sourceDate,
                canRetry: fixture.canRetry,
                retryAction: {}
            )

            if fixture.showsCompletedResult {
                completedPreview
            } else if fixture.phase == .tooShort {
                NoomEmptyStateCard(
                    title: "Session was too short",
                    message: "No completed score, stages, or Body Status is shown for this terminal outcome.",
                    systemImage: "moon.zzz.fill"
                )
            } else if fixture.phase == .retryableError {
                NoomEmptyStateCard(
                    title: "Sleep analysis needs a retry",
                    message: "The selected session remains exact. Retry does not synthesize a result.",
                    systemImage: "arrow.clockwise.circle.fill"
                )
            } else {
                NoomLoadingExperience(
                    title: fixture.phase.title,
                    detail: fixture.phase.detail,
                    systemImage: "moon.stars.fill",
                    accent: NoomTheme.metricPurple
                )
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("sleepProcessing.preview.\(route)")
    }

    private var completedPreview: some View {
        VStack(spacing: 12) {
            NoomCard(fill: NoomTheme.ink, padding: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Sleep score")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                        Text("82")
                            .font(.system(size: 62, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                        Text("7h 34m asleep")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(NoomTheme.mint)
                }
            }

            NoomCard(fill: Color.white.opacity(0.86), padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Body Status input gate")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Enabled only for this exact processed-successfully account, day, and session lineage.")
                        .noomBody()
                    NoomDetailValueRow(label: "Resting HR", value: "58 bpm", verticalPadding: 7)
                    NoomDetailValueRow(label: "Nocturnal HRV", value: "42 ms", verticalPadding: 7)
                    NoomDetailValueRow(label: "Sleep score", value: "82 / 100", verticalPadding: 7)
                }
            }
        }
    }

    private var fixture: Fixture {
        switch route {
        case "sleep_processing_detected":
            return Fixture(phase: .detected)
        case "sleep_processing_stored":
            return Fixture(phase: .stored)
        case "sleep_processing_uploaded":
            return Fixture(phase: .uploaded)
        case "sleep_processing_analyzing":
            return Fixture(phase: .processing)
        case "sleep_processing_calibrating":
            return Fixture(phase: .calibrating)
        case "sleep_processing_ready":
            return Fixture(phase: .ready, freshness: .fresh, showsCompletedResult: true)
        case "sleep_processing_stale":
            return Fixture(phase: .ready, transport: .loaded, freshness: .stale, showsCompletedResult: true)
        case "sleep_processing_short":
            return Fixture(phase: .tooShort)
        case "sleep_processing_error":
            return Fixture(phase: .retryableError, transport: .failed, canRetry: true)
        case "sleep_processing_history_pending", "sleep_processing_pending_with_history":
            return Fixture(
                phase: .processing,
                freshness: .stale,
                sourceDate: Calendar.current.date(byAdding: .day, value: -1, to: selectedDate),
                showsCompletedResult: true
            )
        case "sleep_processing_multiple_sessions":
            return Fixture(phase: .ready, freshness: .fresh, showsCompletedResult: true)
        default:
            return Fixture(phase: .idle)
        }
    }

    private var sampleSessions: [SleepSessionSummary] {
        let day = SleepLocalDay(date: selectedDate)
        let base = Int64(selectedDate.timeIntervalSince1970 * 1_000)
        return [
            SleepSessionSummary(
                identity: SleepSessionIdentity(
                    endDate: day.rawValue,
                    endTimestamp: base - 4 * 60 * 60 * 1_000,
                    timezoneMinutes: 0
                ),
                startMilliseconds: base - 6 * 60 * 60 * 1_000,
                endMilliseconds: base - 4 * 60 * 60 * 1_000,
                asleepMinutes: 105
            ),
            SleepSessionSummary(
                identity: SleepSessionIdentity(
                    endDate: day.rawValue,
                    endTimestamp: base,
                    timezoneMinutes: 0
                ),
                startMilliseconds: base - 8 * 60 * 60 * 1_000,
                endMilliseconds: base,
                asleepMinutes: 454
            ),
        ]
    }

    private struct Fixture {
        let phase: SleepProcessingPhase
        var transport: SleepTransportState = .loaded
        var freshness: SleepFreshness = .unknown
        var sourceDate: Date? = nil
        var showsCompletedResult = false
        var canRetry = false
    }
}
#endif
