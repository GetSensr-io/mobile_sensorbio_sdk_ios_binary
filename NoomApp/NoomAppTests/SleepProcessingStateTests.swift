import XCTest
import SensorBioSDK
@testable import NoomApp

final class SleepProcessingStateTests: XCTestCase {
    func testPresentationCopyIsNonemptyTruthfulAndDistinctForEveryPhase() {
        let presentations: [(
            phase: SleepProcessingPhase,
            title: String,
            detail: String,
            systemImage: String
        )] = [
            (.idle, "No sleep analysis yet", "Record a sleep session to begin an analysis.", "moon"),
            (
                .detected,
                "Preparing sleep analysis",
                "A new sleep session was detected and is being prepared for analysis.",
                "moon.stars"
            ),
            (
                .stored,
                "Preparing sleep analysis",
                "Your sleep session was saved and is being prepared for analysis.",
                "internaldrive"
            ),
            (
                .uploaded,
                "Preparing sleep analysis",
                "Your sleep data is waiting to be processed for analysis.",
                "icloud.and.arrow.up"
            ),
            (
                .processing,
                "Processing sleep analysis",
                "Your sleep data is being analyzed.",
                "hourglass"
            ),
            (
                .ready,
                "Sleep analysis ready",
                "Your sleep analysis is complete and available.",
                "checkmark.circle"
            ),
            (
                .shortSession,
                "Sleep session too short",
                "This session did not contain enough sleep data for an analysis.",
                "moon.zzz"
            ),
            (
                .retryableError,
                "Sleep analysis unavailable",
                "We could not process this sleep session. Please try again.",
                "exclamationmark.triangle"
            ),
            (
                .calibrating,
                "Circadian calibration in progress",
                "Circadian insights are still being prepared.",
                "clock.arrow.circlepath"
            ),
        ]

        for presentation in presentations {
            XCTAssertEqual(presentation.phase.title, presentation.title)
            XCTAssertEqual(presentation.phase.detail, presentation.detail)
            XCTAssertEqual(presentation.phase.systemImage, presentation.systemImage)
            XCTAssertFalse(presentation.phase.title.isEmpty)
            XCTAssertFalse(presentation.phase.detail.isEmpty)
            XCTAssertFalse(presentation.phase.systemImage.isEmpty)
        }

        let pendingPhases: [SleepProcessingPhase] = [
            .detected, .stored, .uploaded, .processing,
        ]
        for phase in pendingPhases {
            let copy = "\(phase.title) \(phase.detail)".lowercased()
            XCTAssertTrue(
                ["processing", "preparing", "analysis"].contains { copy.contains($0) },
                "Expected pending copy for \(phase) to describe ongoing work"
            )
            for completionClaim in ["complete", "ready", "finished", "available"] {
                XCTAssertFalse(
                    copy.contains(completionClaim),
                    "Pending copy for \(phase) must not claim completion"
                )
            }
        }

        let distinctTerminalPresentations = [
            SleepProcessingPhase.shortSession,
            .retryableError,
            .calibrating,
        ].map { phase in
            "\(phase.title)|\(phase.detail)|\(phase.systemImage)"
        }
        XCTAssertEqual(
            Set(distinctTerminalPresentations).count,
            distinctTerminalPresentations.count
        )
    }

    func testPresentationPhaseMapsEverySDKStateAndDetailProcessingOverridesAll() {
        let mappings: [(SB_SleepScoreProcessState, SleepProcessingPhase)] = [
            (.processing, .processing),
            (.processedSuccessfully, .ready),
            (.aggregated, .retryableError),
            (.shortSession, .shortSession),
            (.processedWithError, .retryableError),
            (.circadianGenerating, .calibrating),
        ]

        for (processState, expectedPhase) in mappings {
            XCTAssertEqual(
                SleepProcessingPhase(
                    detailProcessing: false,
                    processState: processState
                ),
                expectedPhase,
                "Unexpected phase for \(processState)"
            )
            XCTAssertEqual(
                SleepProcessingPhase(
                    detailProcessing: true,
                    processState: processState
                ),
                .processing,
                "Detail processing should override \(processState)"
            )
        }
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(SleepProcessingState().phase, .idle)
    }

    func testPendingClassificationIncludesEveryInFlightPhase() {
        let pending: [SleepProcessingPhase] = [
            .detected, .stored, .uploaded, .processing,
        ]
        let notPending: [SleepProcessingPhase] = [
            .idle, .ready, .shortSession, .retryableError, .calibrating,
        ]

        for phase in pending {
            XCTAssertTrue(SleepProcessingState(phase: phase).isPending, "Expected \(phase) to be pending")
        }
        for phase in notPending {
            XCTAssertFalse(SleepProcessingState(phase: phase).isPending, "Expected \(phase) not to be pending")
        }
    }

    func testTerminalClassificationIncludesEveryFinalOutcome() {
        let terminal: [SleepProcessingPhase] = [
            .ready, .shortSession, .retryableError, .calibrating,
        ]
        let nonterminal: [SleepProcessingPhase] = [
            .idle, .detected, .stored, .uploaded, .processing,
        ]

        for phase in terminal {
            XCTAssertTrue(SleepProcessingState(phase: phase).isTerminal, "Expected \(phase) to be terminal")
        }
        for phase in nonterminal {
            XCTAssertFalse(SleepProcessingState(phase: phase).isTerminal, "Expected \(phase) not to be terminal")
        }
    }

    func testOnlyReadyPermitsBodyStatus() {
        XCTAssertTrue(SleepProcessingState(phase: .ready).permitsBodyStatus)

        let blocked: [SleepProcessingPhase] = [
            .idle, .detected, .stored, .uploaded, .processing,
            .shortSession, .retryableError, .calibrating,
        ]
        for phase in blocked {
            XCTAssertFalse(
                SleepProcessingState(phase: phase).permitsBodyStatus,
                "Expected \(phase) to block Body Status"
            )
        }
    }

    func testLifecycleEventsAdvanceThroughEveryInFlightPhase() {
        var state = SleepProcessingState()

        state.transition(.detected)
        XCTAssertEqual(state.phase, .detected)
        state.transition(.stored)
        XCTAssertEqual(state.phase, .stored)
        state.transition(.uploaded)
        XCTAssertEqual(state.phase, .uploaded)
        state.transition(.processing)
        XCTAssertEqual(state.phase, .processing)
    }

    func testLifecycleEventsNeverRegressCurrentInFlightPhase() {
        let scenarios: [(SleepProcessingPhase, [SleepProcessingEvent])] = [
            (.detected, [.detected]),
            (.stored, [.stored, .detected]),
            (.uploaded, [.uploaded, .stored, .detected]),
            (.processing, [.processing, .uploaded, .stored, .detected]),
        ]

        for (currentPhase, staleEvents) in scenarios {
            var state = SleepProcessingState(phase: currentPhase)
            for event in staleEvents {
                state.transition(event)
                XCTAssertEqual(
                    state.phase,
                    currentPhase,
                    "Expected \(event) not to regress \(currentPhase)"
                )
            }
        }
    }

    func testLateLifecycleEventsCannotDowngradeTerminalOutcomes() {
        let terminalPhases: [SleepProcessingPhase] = [
            .ready, .shortSession, .retryableError, .calibrating,
        ]
        let lateEvents: [SleepProcessingEvent] = [
            .stored, .uploaded, .processing,
        ]

        for terminalPhase in terminalPhases {
            var state = SleepProcessingState(phase: terminalPhase)
            for event in lateEvents {
                state.transition(event)
                XCTAssertEqual(
                    state.phase,
                    terminalPhase,
                    "Expected \(event) not to downgrade \(terminalPhase)"
                )
            }
        }
    }

    func testDetectionStartsFirstGenerationWithoutCountingDuplicates() {
        var state = SleepProcessingState()
        XCTAssertEqual(state.generation, 0)

        state.transition(.detected)
        XCTAssertEqual(state.generation, 1)

        state.transition(.detected)
        XCTAssertEqual(state.generation, 1)
    }

    func testDetectionAfterTerminalOutcomeStartsNewGeneration() {
        let terminalPhases: [SleepProcessingPhase] = [
            .ready, .shortSession, .retryableError, .calibrating,
        ]

        for terminalPhase in terminalPhases {
            var state = SleepProcessingState(phase: terminalPhase, generation: 7)

            state.transition(.detected)

            XCTAssertEqual(state.phase, .detected)
            XCTAssertEqual(state.generation, 8)
        }
    }
}
