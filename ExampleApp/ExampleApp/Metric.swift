import Foundation
import SwiftUI
import SensorBioSDK

enum Metric: Hashable {
    case recovery
    case sleep
    case steps
    case calories
    case hr
    case hrv
    case rr

    var title: String {
        switch self {
        case .recovery: return "Recovery"
        case .sleep:    return "Sleep"
        case .steps:    return "Steps"
        case .calories: return "Active Calories"
        case .hr:       return "Resting Heart Rate"
        case .hrv:      return "Heart Rate Variability"
        case .rr:       return "Respiratory Rate"
            @unknown default:
                return "?"
        }
    }
}

extension SB_ViewGranularity {
    var displayName: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
            @unknown default:
                return "?"
        }
    }
}

extension SB_BiometricValueType {
    /// Whether the server flagged this sample as an unreliable measurement.
    ///
    /// Lives here rather than on the SDK type: which samples a host chooses to
    /// hide is a presentation decision, and the SDK deliberately hands back
    /// every sample it received.
    var isOutlier: Bool {
        switch self {
        case .awakeOutlier, .sleepOutlier:
            return true
        case .awake, .sleep, .unknown,
             .awakeAbnormalRhythmSingleOccurrence, .awakeAbnormalRhythmClusteredOccurrence,
             .sleepAbnormalRhythmSingleOccurrence, .sleepAbnormalRhythmClusteredOccurrence:
            return false
        }
    }
}

enum MetricFormatting {
    /// h:mm for a sample whose `timestamp` is an **absolute** millisecond epoch,
    /// rendered in the viewer's own time zone. This is the convention the daily
    /// biometric graphs use (`SB_BiometricPoint`) since SB-1737 dropped their
    /// per-sample timezone — a day recorded elsewhere lands at the viewer's
    /// clock position, which is the point of the change.
    static func sampleTimeLabel(timestampMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// h:mm for an **hourly bucket** on the calories / steps reads, whose
    /// `timestamp` the API encodes as wall-clock-packed-as-UTC rather than as a
    /// real epoch (the local-first path pre-shifts its buckets to match). Extract
    /// h:mm via a UTC calendar so those digits come out literally.
    ///
    /// Deliberately separate from `sampleTimeLabel` — the two point families no
    /// longer share a timestamp convention, so one formatter cannot serve both.
    static func hourBucketLabel(timestampMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// `SB_DateValuePoint.date` is encoded as YYYYMMDD (e.g. 20260515).
    /// Format adapts to granularity: year view shows "Jan 2026"; smaller
    /// ranges show "Jan 5".
    static func rangeDateLabel(packedDate: Int32, granularity: SB_ViewGranularity) -> String {
        let raw = Int(packedDate)
        let year = raw / 10_000
        let month = (raw / 100) % 100
        let day = raw % 100
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = Calendar(identifier: .gregorian).date(from: comps) else {
            return "\(packedDate)"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = granularity == .year ? "MMM yyyy" : "MMM d"
        return fmt.string(from: date)
    }
}

struct DetailHeaderControls: View {
    @Environment(AppDateContext.self) private var dateContext
    @Binding var granularity: SB_ViewGranularity

    var body: some View {
        @Bindable var ctx = dateContext
        VStack(spacing: 8) {
            DatePicker("Date", selection: $ctx.selectedDate, in: ...Date(), displayedComponents: .date)
            Picker("Range", selection: $granularity) {
                Text("Day").tag(SB_ViewGranularity.day)
                Text("Week").tag(SB_ViewGranularity.week)
                Text("Month").tag(SB_ViewGranularity.month)
                Text("Year").tag(SB_ViewGranularity.year)
            }
            .pickerStyle(.segmented)
            Divider()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Composite key for `.task(id:)` so detail screens refetch when either
/// the selected date or the granularity changes.
struct DetailLoadKey: Hashable {
    let date: Date
    let granularity: SB_ViewGranularity
}
