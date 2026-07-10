import Foundation
import Observation

/// Single source of truth for the date the user is browsing across the
/// signed-in tree. Dashboard's toolbar DatePicker writes here; each
/// detail screen reads (and may also write via its own picker). Loaders
/// key their `.task(id:)` on this so date changes refetch.
@Observable
final class AppDateContext {
    var selectedDate: Date = Date()
}
