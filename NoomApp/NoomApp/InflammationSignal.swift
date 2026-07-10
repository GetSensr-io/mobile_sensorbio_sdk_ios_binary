import Foundation
import SwiftUI

/// Provider-neutral daily wellness-context input. This POC deliberately has no
/// network or demo-backend path; a real source must implement the documented
/// authenticated/SDK contract before it can supply values to release builds.
enum InflammationSignalStatus: Equatable {
    case valid
    case unavailable
    case stale
    case lowConfidence

    var isUsable: Bool { self == .valid }

    var label: String {
        switch self {
        case .valid: return "Available"
        case .unavailable: return "Unavailable"
        case .stale: return "Stale"
        case .lowConfidence: return "Low confidence"
        }
    }
}

struct InflammationSignal: Equatable {
    let score: Int?
    let completedDate: Date
    let generatedAt: Date?
    let algorithmVersion: String?
    let status: InflammationSignalStatus
    let isPreview: Bool

    init(
        score: Int?,
        completedDate: Date,
        generatedAt: Date? = nil,
        algorithmVersion: String? = nil,
        status: InflammationSignalStatus,
        isPreview: Bool = false
    ) {
        self.score = score
        self.completedDate = completedDate
        self.generatedAt = generatedAt
        self.algorithmVersion = algorithmVersion
        self.status = status
        self.isPreview = isPreview
    }

    var validScore: Int? {
        guard status.isUsable, let score, (0...100).contains(score) else { return nil }
        return score
    }

    static func unavailable(for date: Date) -> InflammationSignal {
        InflammationSignal(score: nil, completedDate: date, status: .unavailable)
    }
}

protocol InflammationSignalProviding {
    func signal(for completedDate: Date) -> InflammationSignal
}

struct UnavailableInflammationSignalProvider: InflammationSignalProviding {
    func signal(for completedDate: Date) -> InflammationSignal {
        .unavailable(for: completedDate)
    }
}

#if DEBUG
/// Debug-only synthetic data for layout and deterministic formula QA. It is
/// never routed through the release app or presented as personal health data.
struct MockInflammationSignalProvider: InflammationSignalProviding {
    func signal(for completedDate: Date) -> InflammationSignal {
        InflammationSignal(
            score: 74,
            completedDate: completedDate,
            generatedAt: completedDate,
            algorithmVersion: "preview-v1",
            status: .valid,
            isPreview: true
        )
    }

    func trailingValues(before completedDate: Date) -> [Double] {
        [69, 70, 72, 71, 73, 74, 70, 72, 71, 75, 73, 72, 74, 70, 71, 73, 72, 74, 75, 71, 72, 70, 73, 74, 72, 71, 73, 75, 74, 72]
    }
}
#endif

struct InflammationSignalDetailView: View {
    let signal: InflammationSignal
    var historicalValues: [Double] = []

    private var baseline: PersonalBaseline? {
        guard let score = signal.validScore else { return nil }
        return PersonalBaseline.make(currentValue: Double(score), historicalValues: historicalValues)
    }

    var body: some View {
        Group {
            if let score = signal.validScore {
                BaselineMetricDetail(
                    title: Metric.inflammation.title,
                    symbol: "waveform.path.ecg",
                    accent: NoomTheme.ink,
                    date: signal.completedDate,
                    value: Double(score),
                    valueText: MetricFormatting.humanNumber(score),
                    unit: "/ 100",
                    tone: .inflammation,
                    baseline: baseline,
                    readings: detailReadings
                )
            } else {
                ContentUnavailableView(
                    "Inflammation signal unavailable",
                    systemImage: "waveform.path.ecg",
                    description: Text("A daily overnight signal will appear here after its source integration is available. No value is estimated or substituted.")
                )
                .navigationTitle(Metric.inflammation.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var detailReadings: [MetricReading] {
        var readings = [
            MetricReading(label: "Status", value: signal.status.label),
            MetricReading(label: "Completed date", value: signal.completedDate.formatted(date: .abbreviated, time: .omitted))
        ]
        if let algorithmVersion = signal.algorithmVersion {
            readings.append(MetricReading(label: "Algorithm", value: algorithmVersion))
        }
        if signal.isPreview {
            readings.append(MetricReading(label: "Data", value: "Preview sample — not personal data"))
        }
        return readings
    }
}

#if DEBUG
struct InflammationSignalPreviewView: View {
    private let provider = MockInflammationSignalProvider()
    private let completedDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now

    var body: some View {
        let signal = provider.signal(for: completedDate)
        let status = BodyStatusScore.make(
            restingHeartRate: 58,
            nocturnalHRV: 56,
            sleepScore: 82,
            inflammationSignal: signal
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NoomStateBanner(
                    title: "Preview sample",
                    detail: "Synthetic development data exercises the four-input formula. It is not a personal health result.",
                    systemImage: "wrench.and.screwdriver",
                    tint: NoomTheme.rose
                )
                if let status {
                    NoomCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Overall Body Status").noomSerifTitle(size: 28)
                            Text("Composite score from available overnight signals")
                                .noomBody()
                            Text("\(MetricFormatting.humanNumber(status.score)) / 100")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text(status.coverageDescription).noomBody()
                            NoomDetailValueRow(label: "Resting HR", value: "\(MetricFormatting.humanNumber(status.restingHeartRateComponent)) / 100", verticalPadding: 8)
                            NoomDetailValueRow(label: "Nocturnal HRV", value: "\(MetricFormatting.humanNumber(status.nocturnalHRVComponent)) / 100", verticalPadding: 8)
                            NoomDetailValueRow(label: "Sleep", value: "\(MetricFormatting.humanNumber(status.sleepComponent)) / 100", verticalPadding: 8)
                            NoomDetailValueRow(label: "Inflammation signal", value: "\(MetricFormatting.humanNumber(status.inflammationSignalComponent ?? 0)) / 100", verticalPadding: 8)
                            NoomDetailValueRow(label: "Method", value: status.methodDescription, verticalPadding: 8)
                        }
                    }
                }
                InflammationSignalDetailView(signal: signal, historicalValues: provider.trailingValues(before: completedDate))
                    .frame(minHeight: 680)
            }
            .padding(20)
        }
        .navigationTitle("Inflammation signal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
