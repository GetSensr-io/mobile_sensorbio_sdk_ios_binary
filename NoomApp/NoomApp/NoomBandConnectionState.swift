import Foundation

/// User-facing Noom Band state. A paired device is not considered ready unless
/// the SDK currently reports a live BLE connection.
enum NoomBandConnectionState: Equatable {
    case neverPaired
    case connecting
    case connected
    case pairedDisconnected
    case error(String)

    static func live(paired: Bool, connected: Bool) -> Self {
        if paired && connected { return .connected }
        return paired ? .pairedDisconnected : .neverPaired
    }

    var title: String {
        switch self {
        case .neverPaired: return "Set up Noom Band"
        case .connecting: return "Connecting to Noom Band"
        case .connected: return "Noom Band connected"
        case .pairedDisconnected: return "Reconnect Noom Band"
        case .error: return "Noom Band needs attention"
        }
    }

    var detail: String {
        switch self {
        case .neverPaired: return "Pair your band to add live sleep, recovery, and movement signals."
        case .connecting: return "Keep Noom Band nearby while the connection finishes."
        case .connected: return "Live connection confirmed. Your band can sync current signals."
        case .pairedDisconnected: return "Your band is paired, but there is no live connection right now."
        case .error(let message): return message
        }
    }

    var callToAction: String {
        switch self {
        case .neverPaired: return "Set up"
        case .connecting: return "Connecting"
        case .connected: return "Review connection"
        case .pairedDisconnected: return "Reconnect"
        case .error: return "Try again"
        }
    }

    var isLiveReady: Bool { self == .connected }
}
