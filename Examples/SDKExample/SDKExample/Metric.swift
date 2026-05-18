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
        }
    }
}

enum MetricFormatting {
    /// SDK time-value points encode `timestamp` as a *local epoch* — the
    /// recording's local-time digits packed as if they were UTC. To render
    /// "what time did the device say it was when this sample was taken",
    /// extract h:mm via a UTC calendar so the digits come out literally.
    /// (`timezoneOffsetMinutes` is metadata only; not applied as a shift.)
    static func dayTimeLabel(timestampMillis: Int64, timezoneOffsetMinutes: Int32) -> String {
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
