import Foundation
import Combine
import Observation
import SensorBioSDK

@Observable
final class PairDeviceState {
    enum Phase: Equatable {
        case idle
        case scanning
        case scanTimeout
        case connecting
        case confirming
        case allSet
        case error(String)

        var displayName: String {
            switch self {
            case .idle:        return "Idle"
            case .scanning:    return "Scanning"
            case .scanTimeout: return "Scan Timeout"
            case .connecting:  return "Connecting"
            case .confirming:  return "Confirming"
            case .allSet:      return "All Set"
            case .error:       return "Error"
                @unknown default:
                    return "?"
            }
        }
    }

    var phase: Phase = .idle
    var devices: [SB_DiscoveredDevice] = []
    var selectedDevice: SB_DiscoveredDevice?

    private var subscriptions: Set<AnyCancellable> = []
    private var watchdog: Task<Void, Never>?

    init() {
        sensorBio.deviceDiscovered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] device in
                guard let self else { return }
                guard self.phase == .scanning else { return }
                if !self.devices.contains(where: { $0.id == device.id }) {
                    self.devices.append(device)
                }
            }
            .store(in: &subscriptions)

        sensorBio.pairingConnection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.phase == .connecting else { return }
                self.cancelWatchdog()
                sensorBio.stopScan()
                self.phase = .confirming
                Task { try? await sensorBio.userLED(blue: true, blink: true, for: 5) }
                sensorBio.setAskForDeviceResponse(true)
                self.startWatchdog(after: 30) { [weak self] in
                    sensorBio.setAskForDeviceResponse(false)
                    self?.phase = .error("Timed out waiting for the Noom Band button press.")
                }
            }
            .store(in: &subscriptions)

        sensorBio.deviceDisconnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.phase == .connecting || self.phase == .confirming {
                    self.cancelWatchdog()
                    if self.phase == .confirming {
                        sensorBio.setAskForDeviceResponse(false)
                    }
                    self.phase = .error("Noom Band disconnected before setup finished.")
                }
            }
            .store(in: &subscriptions)

        sensorBio.$buttonTaps
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.phase == .confirming else { return }
                self.cancelWatchdog()
                sensorBio.setAskForDeviceResponse(false)
                self.phase = .allSet
            }
            .store(in: &subscriptions)
    }

    deinit {
        watchdog?.cancel()
        sensorBio.setAskForDeviceResponse(false)
    }

    @MainActor
    func start() {
        devices.removeAll()
        selectedDevice = nil
        phase = .scanning
        sensorBio.startScan()
        startWatchdog(after: 30) { [weak self] in
            sensorBio.stopScan()
            self?.phase = .scanTimeout
        }
    }

    @MainActor
    func cancel() {
        cancelWatchdog()
        sensorBio.setAskForDeviceResponse(false)
        sensorBio.stopScan()
        if sensorBio.isDeviceConnected {
            sensorBio.disconnect()
        }
        devices.removeAll()
        selectedDevice = nil
        phase = .idle
    }

    @MainActor
    func connect(_ device: SB_DiscoveredDevice) {
        cancelWatchdog()
        selectedDevice = device
        phase = .connecting
        sensorBio.connect(device.id, pairing: true)
        startWatchdog(after: 30) { [weak self] in
            self?.phase = .error("Timed out connecting to Noom Band.")
        }
    }

    /// Persists the freshly paired device through the v0.12 SDK-owned paired
    /// device store so `pairedDevice` and `haveDevice` update consistently.
    @MainActor
    func finish() {
        sensorBio.setAskForDeviceResponse(false)
        guard let device = selectedDevice else { return }
        sensorBio.persistPairedDevice(macAddress: device.id, name: device.name, type: device.deviceType)
        sensorBio.disconnect()
    }

    // MARK: - watchdog

    private func startWatchdog(after seconds: TimeInterval, action: @escaping () -> Void) {
        watchdog?.cancel()
        watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }
}
