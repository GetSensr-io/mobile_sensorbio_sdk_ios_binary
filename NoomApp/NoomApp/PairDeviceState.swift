import Foundation
import Combine
import Observation
import SensorBioSDK

struct PairingAttemptCorrelation {
    static func canonicalDeviceID(
        selectedDeviceID: String?,
        callbackDeviceID _: String
    ) -> String? {
        selectedDeviceID
    }
}

struct DeviceIdentityPresentation: Equatable {
    private(set) var deviceID: String?
    private(set) var serialNumber: String?

    private var rejectedSerials: Set<String>
    private var serialSourceDeviceID: String?
    private var serialSourceSerial: String?
    private var canAcceptSerial: Bool

    init(deviceID: String? = nil, serialNumber: String? = nil) {
        let normalizedDeviceID = Self.normalized(deviceID)
        let normalizedSerial = Self.normalized(serialNumber)
        self.deviceID = normalizedDeviceID
        self.serialNumber = normalizedDeviceID == nil ? nil : normalizedSerial
        self.rejectedSerials = []
        self.serialSourceDeviceID = self.serialNumber == nil ? nil : normalizedDeviceID
        self.serialSourceSerial = self.serialNumber
        self.canAcceptSerial = normalizedDeviceID != nil
    }

    mutating func begin(
        deviceID: String?,
        currentSDKSerial: String?,
        waitForConnection: Bool
    ) {
        let normalizedDeviceID = Self.normalized(deviceID)
        let normalizedCurrentSerial = Self.normalized(currentSDKSerial)
        self.deviceID = normalizedDeviceID
        serialNumber = nil
        rejectedSerials.removeAll()
        if let normalizedDeviceID {
            if serialSourceDeviceID != normalizedDeviceID,
               let serialSourceSerial {
                rejectedSerials.insert(serialSourceSerial)
            }
            if let normalizedCurrentSerial,
               serialSourceDeviceID != normalizedDeviceID
                    || serialSourceSerial != normalizedCurrentSerial {
                rejectedSerials.insert(normalizedCurrentSerial)
            }
        }
        canAcceptSerial = normalizedDeviceID != nil && !waitForConnection
    }

    mutating func connectionEstablished(deviceID connectedDeviceID: String?, currentSDKSerial: String?) {
        guard let deviceID,
              Self.normalized(connectedDeviceID) == deviceID else { return }
        if let currentSerial = Self.normalized(currentSDKSerial),
           let serialSourceSerial,
           serialSourceDeviceID != deviceID,
           currentSerial != serialSourceSerial {
            rejectedSerials.remove(currentSerial)
        }
        canAcceptSerial = true
        observe(serial: currentSDKSerial, currentSDKSerial: currentSDKSerial)
    }

    mutating func observe(serial emittedSerial: String?, currentSDKSerial: String?) {
        guard deviceID != nil else { return }

        let candidate = Self.normalized(emittedSerial)
        let current = Self.normalized(currentSDKSerial)
        guard candidate == current else { return }

        guard let candidate else {
            serialNumber = nil
            return
        }
        guard canAcceptSerial else { return }
        if serialSourceDeviceID == deviceID,
           let serialSourceSerial,
           candidate != serialSourceSerial {
            return
        }
        guard !rejectedSerials.contains(candidate) else { return }

        serialNumber = candidate
        serialSourceDeviceID = deviceID
        serialSourceSerial = candidate
        rejectedSerials.removeAll()
    }

    static func serialsOnMain<P: Publisher>(_ publisher: P) -> AnyPublisher<String?, Never>
    where P.Output == String?, P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
    var identity = DeviceIdentityPresentation(
        deviceID: sensorBio.pairedDevice?.macAddress,
        serialNumber: sensorBio.serialNumber
    )

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

        DeviceIdentityPresentation.serialsOnMain(sensorBio.$serialNumber)
            .sink { [weak self] serialNumber in
                guard let self else { return }
                self.identity.observe(
                    serial: serialNumber,
                    currentSDKSerial: sensorBio.serialNumber
                )
            }
            .store(in: &subscriptions)

        sensorBio.pairingConnection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connectedDeviceID in
                guard let self,
                      self.phase == .connecting,
                      let canonicalDeviceID = PairingAttemptCorrelation.canonicalDeviceID(
                        selectedDeviceID: self.selectedDevice?.id,
                        callbackDeviceID: connectedDeviceID
                      ) else { return }
                self.identity.connectionEstablished(
                    deviceID: canonicalDeviceID,
                    currentSDKSerial: sensorBio.serialNumber
                )
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
        identity.begin(
            deviceID: nil,
            currentSDKSerial: sensorBio.serialNumber,
            waitForConnection: true
        )
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
        identity.begin(
            deviceID: nil,
            currentSDKSerial: sensorBio.serialNumber,
            waitForConnection: true
        )
        phase = .idle
    }

    @MainActor
    func connect(_ device: SB_DiscoveredDevice) {
        cancelWatchdog()
        selectedDevice = device
        identity.begin(
            deviceID: device.id,
            currentSDKSerial: sensorBio.serialNumber,
            waitForConnection: true
        )
        phase = .connecting
        sensorBio.connect(device.id, pairing: true)
        startWatchdog(after: 30) { [weak self] in
            self?.phase = .error("Timed out connecting to Noom Band.")
        }
    }

    /// Persists the freshly paired device via the SDK. `persistPairedDevice`
    /// serializes the identity, updates `haveDevice` / `pairedDevice`, and
    /// registers the device with the BLE layer. The SDK owns paired-device
    /// persistence end-to-end; the app never rebuilds its device dictionary.
    @MainActor
    func finish() {
        sensorBio.setAskForDeviceResponse(false)
        guard let device = selectedDevice else { return }
        sensorBio.persistPairedDevice(
            macAddress: device.id,
            name: device.name,
            type: device.deviceType
        )
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
