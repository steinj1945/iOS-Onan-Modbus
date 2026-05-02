import Foundation
import CoreBluetooth

/// Runs as a BLE peripheral — advertises the CopCar Passkey service and
/// responds to Arduino challenge-response requests without user interaction.
@MainActor
final class PasskeyPeripheral: NSObject, ObservableObject {
    @Published private(set) var isAdvertising = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastEvent: String = "Idle"

    private var manager: CBPeripheralManager!

    // Written once during setupServices() (@MainActor), then read from the BLE
    // queue. nonisolated(unsafe) is safe because writes finish before reads begin.
    nonisolated(unsafe) private var responseChar: CBMutableCharacteristic!

    // Chunked send state — only accessed from the BLE queue.
    nonisolated(unsafe) private var pendingChunkData: Data?
    nonisolated(unsafe) private var pendingChunkOffset = 0
    private let chunkSize = 20

    // Set in willRestoreState so peripheralManagerDidUpdateState skips teardown.
    private var restoredFromBackground = false

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .global(qos: .userInitiated),
                                      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.copcar.passkey.peripheral"])
    }

    func startAdvertising() {
        guard manager.state == .poweredOn else {
            log("startAdvertising called but BT not powered on (state=\(manager.state.rawValue))")
            return
        }
        setupServices()
    }

    func stopAdvertising() {
        manager.stopAdvertising()
        isAdvertising = false
        log("advertising stopped")
    }

    private func setupServices() {
        if manager.isAdvertising {
            manager.stopAdvertising()
            log("stopped stale advertising before reconfiguring")
        }
        manager.removeAllServices()

        responseChar = CBMutableCharacteristic(
            type:        BLEConstants.responseUUID,
            properties:  [.notify],
            value:       nil,
            permissions: .readable)

        let statusChar = CBMutableCharacteristic(
            type:        BLEConstants.statusUUID,
            properties:  [.writeWithoutResponse],
            value:       nil,
            permissions: .writeable)

        let challengeChar = CBMutableCharacteristic(
            type:        BLEConstants.challengeUUID,
            properties:  [.write],
            value:       nil,
            permissions: .writeable)

        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [challengeChar, responseChar, statusChar]
        manager.add(service)
        log("service added, waiting for BLE stack confirmation")
    }

    nonisolated private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[PasskeyPeripheral \(ts)] \(msg)")
    }
}

// MARK: - CBPeripheralManagerDelegate

extension PasskeyPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        let stateName: String
        switch p.state {
        case .poweredOn:     stateName = "poweredOn"
        case .poweredOff:    stateName = "poweredOff"
        case .resetting:     stateName = "resetting"
        case .unauthorized:  stateName = "unauthorized"
        case .unsupported:   stateName = "unsupported"
        case .unknown:       stateName = "unknown"
        @unknown default:    stateName = "unknown(\(p.state.rawValue))"
        }
        Task { @MainActor in
            log("BT state → \(stateName)")
            if p.state == .poweredOn {
                if restoredFromBackground && responseChar != nil {
                    // Services already registered from state restoration — don't tear down.
                    isAdvertising = p.isAdvertising
                    restoredFromBackground = false
                    log("background restore: services intact, isAdvertising=\(isAdvertising)")
                } else {
                    startAdvertising()
                }
            }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let err = error {
                log("didAdd service ERROR: \(err.localizedDescription)")
                return
            }
            log("service registered OK — starting advertising")
            p.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
                CBAdvertisementDataLocalNameKey: "CopCarPasskey"
            ])
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let err = error {
                log("advertising start ERROR: \(err.localizedDescription)")
                isAdvertising = false
            } else {
                log("advertising started")
                isAdvertising = true
            }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       central: CBCentral,
                                       didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in
            log("central \(central.identifier) subscribed")
            lastEvent = "Device connected"
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       central: CBCentral,
                                       didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            log("central \(central.identifier) unsubscribed")
            isAuthenticating = false
            lastEvent = "Device disconnected"
        }
    }

    // MARK: - Challenge handling (runs entirely on the BLE queue)

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEConstants.challengeUUID else {
                p.respond(to: request, withResult: .requestNotSupported)
                continue
            }
            guard let nonce = request.value, nonce.count == 60 else {
                p.respond(to: request, withResult: .attributeNotLong)
                continue
            }

            // Respond to the ATT write immediately on the BLE queue.
            // Any delay here causes the central to time out — do NOT hop to @MainActor first.
            p.respond(to: request, withResult: .success)

            Task { @MainActor in isAuthenticating = true }

            // Full crypto pipeline on the BLE queue — no actor hop needed.
            guard let secret = SecretStore.load() else {
                Task { @MainActor in
                    self.isAuthenticating = false
                    self.lastEvent = "No key enrolled"
                }
                continue
            }
            guard let plainNonce = try? SessionCrypto.decrypt(nonce) else {
                Task { @MainActor in
                    self.isAuthenticating = false
                    self.lastEvent = "Decryption failed"
                }
                continue
            }

            let mac = HMACAuth.response(for: plainNonce, secret: secret)

            guard let encResponse = try? SessionCrypto.encrypt(mac) else {
                Task { @MainActor in
                    self.isAuthenticating = false
                    self.lastEvent = "Encrypt failed"
                }
                continue
            }

            sendChunked(encResponse, peripheral: p)

            let ts = Date().formatted(date: .omitted, time: .shortened)
            Task { @MainActor in
                self.isAuthenticating = false
                self.lastEvent = "Unlocked – \(ts)"
            }
        }
    }

    // Called when the BLE transmit queue drains — resume pending chunked send.
    nonisolated func peripheralManagerIsReady(toUpdateSubscribers p: CBPeripheralManager) {
        guard pendingChunkData != nil else { return }
        log("transmit queue ready — resuming chunk at offset \(pendingChunkOffset)")
        sendNextChunk(peripheral: p)
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       willRestoreState dict: [String: Any]) {
        let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
        Task { @MainActor in
            for service in services {
                for char in service.characteristics ?? [] {
                    if char.uuid == BLEConstants.responseUUID,
                       let mutable = char as? CBMutableCharacteristic {
                        responseChar = mutable
                    }
                }
            }
            restoredFromBackground = true
            log("willRestoreState: \(services.count) service(s), responseChar=\(responseChar != nil ? "captured" : "nil")")
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveRead request: CBATTRequest) {}

    // MARK: - Chunked notification send (BLE queue only)

    nonisolated private func sendChunked(_ data: Data, peripheral: CBPeripheralManager) {
        pendingChunkData   = data
        pendingChunkOffset = 0
        sendNextChunk(peripheral: peripheral)
    }

    nonisolated private func sendNextChunk(peripheral: CBPeripheralManager) {
        guard let data = pendingChunkData else { return }
        let off = pendingChunkOffset
        guard off < data.count else {
            pendingChunkData   = nil
            pendingChunkOffset = 0
            return
        }

        let end   = min(off + chunkSize, data.count)
        let chunk = Data(data[off..<end])
        let ok    = peripheral.updateValue(chunk, for: responseChar, onSubscribedCentrals: nil)

        guard ok else {
            // Queue full — peripheralManagerIsReady will retry from pendingChunkOffset.
            return
        }

        pendingChunkOffset = end

        // Small delay between chunks so the stack can drain the previous notification.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            self.sendNextChunk(peripheral: peripheral)
        }
    }
}

// MARK: - Hex helper (debug logging)

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
