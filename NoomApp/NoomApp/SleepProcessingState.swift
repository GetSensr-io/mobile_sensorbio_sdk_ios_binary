import SensorBioSDK

enum SleepProcessingPhase: Equatable, Sendable {
    case idle
    case detected
    case stored
    case uploaded
    case processing
    case ready
    case shortSession
    case retryableError
    case calibrating

    init(
        detailProcessing: Bool,
        processState: SB_SleepScoreProcessState
    ) {
        if detailProcessing {
            self = .processing
            return
        }

        switch processState {
        case .processing:
            self = .processing
        case .processedSuccessfully:
            self = .ready
        case .aggregated:
            self = .retryableError
        case .shortSession:
            self = .shortSession
        case .processedWithError:
            self = .retryableError
        case .circadianGenerating:
            self = .calibrating
        @unknown default:
            self = .retryableError
        }
    }

    var title: String {
        presentation.title
    }

    var detail: String {
        presentation.detail
    }

    var systemImage: String {
        presentation.systemImage
    }

    private var presentation: (
        title: String,
        detail: String,
        systemImage: String
    ) {
        switch self {
        case .idle:
            return (
                "No sleep analysis yet",
                "Record a sleep session to begin an analysis.",
                "moon"
            )
        case .detected:
            return (
                "Preparing sleep analysis",
                "A new sleep session was detected and is being prepared for analysis.",
                "moon.stars"
            )
        case .stored:
            return (
                "Preparing sleep analysis",
                "Your sleep session was saved and is being prepared for analysis.",
                "internaldrive"
            )
        case .uploaded:
            return (
                "Preparing sleep analysis",
                "Your sleep data is waiting to be processed for analysis.",
                "icloud.and.arrow.up"
            )
        case .processing:
            return (
                "Processing sleep analysis",
                "Your sleep data is being analyzed.",
                "hourglass"
            )
        case .ready:
            return (
                "Sleep analysis ready",
                "Your sleep analysis is complete and available.",
                "checkmark.circle"
            )
        case .shortSession:
            return (
                "Sleep session too short",
                "This session did not contain enough sleep data for an analysis.",
                "moon.zzz"
            )
        case .retryableError:
            return (
                "Sleep analysis unavailable",
                "We could not process this sleep session. Please try again.",
                "exclamationmark.triangle"
            )
        case .calibrating:
            return (
                "Circadian calibration in progress",
                "Circadian insights are still being prepared.",
                "clock.arrow.circlepath"
            )
        }
    }
}

enum SleepProcessingEvent: Equatable, Sendable {
    case detected
    case stored
    case uploaded
    case processing
}

struct SleepProcessingState: Equatable, Sendable {
    private(set) var phase: SleepProcessingPhase
    private(set) var generation: Int

    init(phase: SleepProcessingPhase = .idle, generation: Int = 0) {
        self.phase = phase
        self.generation = generation
    }

    mutating func transition(_ event: SleepProcessingEvent) {
        if isTerminal {
            guard event == .detected else {
                return
            }
            generation += 1
            phase = .detected
            return
        }

        let targetPhase: SleepProcessingPhase
        switch event {
        case .detected:
            targetPhase = .detected
        case .stored:
            targetPhase = .stored
        case .uploaded:
            targetPhase = .uploaded
        case .processing:
            targetPhase = .processing
        }

        let currentOrder = phase.lifecycleOrder ?? -1
        guard let targetOrder = targetPhase.lifecycleOrder, targetOrder > currentOrder else {
            return
        }
        if phase == .idle, targetPhase == .detected {
            generation += 1
        }
        phase = targetPhase
    }

    var isPending: Bool {
        switch phase {
        case .detected, .stored, .uploaded, .processing:
            true
        case .idle, .ready, .shortSession, .retryableError, .calibrating:
            false
        }
    }

    var isTerminal: Bool {
        switch phase {
        case .ready, .shortSession, .retryableError, .calibrating:
            true
        case .idle, .detected, .stored, .uploaded, .processing:
            false
        }
    }

    var permitsBodyStatus: Bool {
        phase == .ready
    }
}

private extension SleepProcessingPhase {
    var lifecycleOrder: Int? {
        switch self {
        case .idle:
            0
        case .detected:
            1
        case .stored:
            2
        case .uploaded:
            3
        case .processing:
            4
        case .ready, .shortSession, .retryableError, .calibrating:
            nil
        }
    }
}
