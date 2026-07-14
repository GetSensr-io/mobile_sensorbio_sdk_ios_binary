import Foundation

/// Tracks whether live recording telemetry is actually fresh, so the UI can
/// stop labeling frozen values "LIVE" after a background suspension.
///
/// The SDK's live publishers (`hr`, `hrv`, `bbi`, `snr`, `ppg`, …) do not
/// replay while the app is suspended, and delivery on the main run loop
/// pauses. Without this model the last pre-background values remain on
/// screen labeled as live. `NoomLiveTelemetryFreshness` is a pure value
/// type: the view feeds it sample arrivals and scene transitions with
/// explicit dates, and it answers one question — may these values be shown
/// as live right now?
struct NoomLiveTelemetryFreshness: Equatable, Sendable {
    enum Presentation: Equatable, Sendable {
        /// Values received recently in the foreground; render normally.
        case live
        /// The app was backgrounded (or samples stopped) and no fresh
        /// sample has arrived since; values must be labeled stale and the
        /// UI should explain that live values resume with fresh samples.
        case stale
        /// No sample has ever arrived for this recording generation.
        case awaitingFirstSample
    }

    /// Maximum age a sample may have and still be rendered as live while
    /// the app stays in the foreground.
    let maximumSampleAge: TimeInterval

    private(set) var lastSampleReceivedAt: Date?
    private(set) var isForeground: Bool
    private(set) var becameStaleOnBackground: Bool

    init(maximumSampleAge: TimeInterval = 15) {
        self.maximumSampleAge = maximumSampleAge
        self.lastSampleReceivedAt = nil
        self.isForeground = true
        self.becameStaleOnBackground = false
    }

    /// Record a finite live sample arrival. Samples received while
    /// backgrounded are still recorded (the SDK may deliver briefly during
    /// the background grace window) but do not clear staleness until the
    /// app is foregrounded and a fresh sample arrives afterwards.
    mutating func recordSample(at date: Date) {
        lastSampleReceivedAt = date
        if isForeground {
            becameStaleOnBackground = false
        }
    }

    /// Scene became active/inactive. Backgrounding immediately marks the
    /// telemetry stale: whatever is on screen is the last pre-suspension
    /// value and must not continue to claim "LIVE".
    mutating func setForeground(_ foreground: Bool, at date: Date) {
        guard foreground != isForeground else { return }
        isForeground = foreground
        if !foreground {
            becameStaleOnBackground = true
        }
    }

    /// Reset for a new recording generation (start, restore, or clear).
    mutating func reset() {
        lastSampleReceivedAt = nil
        becameStaleOnBackground = false
    }

    /// The truthful presentation for the current instant.
    func presentation(at date: Date) -> Presentation {
        guard let lastSampleReceivedAt else { return .awaitingFirstSample }
        if becameStaleOnBackground { return .stale }
        if date.timeIntervalSince(lastSampleReceivedAt) > maximumSampleAge {
            return .stale
        }
        return .live
    }

    /// Whether individual metric values (HR, HRV, IBI, SNR) may be shown.
    /// Stale values remain visible but must carry the stale treatment;
    /// this only reports which treatment applies.
    func isLive(at date: Date) -> Bool {
        presentation(at: date) == .live
    }
}
