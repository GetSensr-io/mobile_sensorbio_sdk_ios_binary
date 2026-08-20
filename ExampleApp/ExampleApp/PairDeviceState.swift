import Foundation
import Combine
import Observation
import SensorBioSDK

/// Host side of a pairing transaction.
///
/// Pairing is one transaction owned by the SDK, so this type is almost
/// entirely a pass-through: it republishes `sensorBio.$pairingState` for
/// SwiftUI to render, and makes the three calls that drive it —
/// `beginPairing()`, `selectDevice(_:)`, `endPairing()`.
///
/// Note what is *absent*. No scan start/stop, no connect, no LED or haptic
/// choreography, no button-tap subscription, no persistence call, no server
/// registration, and no timeout watchdogs — the SDK owns all of it, including
/// every timeout that produces a `.failed` state. A host that finds itself
/// sequencing those steps is working against the API rather than with it.
@Observable
final class PairDeviceState {

    /// Mirrors `sensorBio.pairingState`. `nil` means no transaction is open.
    var pairingState: SB_PairingState?

    private var subscriptions: Set<AnyCancellable> = []

    init() {
        sensorBio.$pairingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.pairingState = state
            }
            .store(in: &subscriptions)
    }

    /// Open the transaction and start scanning. Also the Retry path — calling
    /// it again restarts a transaction that is already open.
    @MainActor
    func start() {
        sensorBio.beginPairing()
    }

    /// Pair with one of the bands from the current `.scanning` payload.
    @MainActor
    func select(_ device: SB_DiscoveredDevice) {
        sensorBio.selectDevice(device.id)
    }

    /// Close the transaction — cancels one still in flight, or dismisses one
    /// that already reached `.paired` / `.failed`. Idempotent and safe from
    /// any state, so Cancel and Done are the same call.
    @MainActor
    func close() {
        sensorBio.endPairing()
    }
}

extension SB_PairingFailure {
    /// Failure copy is the host's call — the SDK reports the reason, the app
    /// decides how to say it.
    var message: String {
        switch self {
        case .scanTimeout:
            return "No device found. Tap Retry to scan again."
        case .connectTimeout:
            return "Couldn't connect to the device. Move closer and retry."
        case .connectionLost:
            return "The device disconnected before pairing finished."
        case .notConfirmed:
            return "No button press received. Tap Retry and press the button on the device."
        case .deviceUnavailable:
            return "That device is no longer nearby. Tap Retry to scan again."
        }
    }
}
