import Foundation
import CoreBluetooth

/// Runs as a BLE central — scans for the CopCar ESP32 peripheral and performs
/// the challenge-response authentication. Works reliably in background and when
/// the phone is locked; iOS's bluetooth-central background mode wakes the app
/// whenever the car's service UUID is detected.
///
/// ESP32 firmware must run as a peripheral and:
///   • Advertise serviceUUID
///   • challengeUUID char: notify — send encrypted 60-byte challenge on subscribe
///   • responseUUID char:  write  — receive encrypted HMAC response from iOS
///
/// Timing note: background BLE takes 3–17s total (scan + connect + discovery).
/// The ESP32 must wait at least 20s after a connection before timing out.
@MainActor
final class PasskeyCentral: NSObject, ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isKeyPresent = false
    @Published private(set) var lastEvent: String = "Idle"

    private var manager: CBCentralManager!
    private let peripheralIDKey = "com.copcar.passkey.peripheralUUID"

    // Accessed from BLE queue delegate callbacks; written before any concurrent reads.
    nonisolated(unsafe) private var carPeripheral: CBPeripheral?
    nonisolated(unsafe) private var challengeChar: CBCharacteristic?
    nonisolated(unsafe) private var responseChar: CBCharacteristic?
    nonisolated(unsafe) private var incomingBuffer = Data()

    override init() {
        super.init()
        manager = CBCentralManager(
            delegate: self,
            queue: .global(qos: .userInitiated),
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.copcar.passkey.central"]
        )
    }

    // MARK: - Scanning

    /// Start scanning, preferring a direct connection to the previously seen ESP32
    /// to skip the slow background scan phase (~1–15s) on repeat visits.
    func startScanning(useCached: Bool = true) {
        guard manager.state == .poweredOn else { return }

        if useCached,
           let savedID = UserDefaults.standard.string(forKey: peripheralIDKey),
           let uuid    = UUID(uuidString: savedID) {
            let known = manager.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                carPeripheral = p
                p.delegate    = self
                manager.connect(p, options: nil)
                log("direct-connecting to cached peripheral (skipping scan)")
                return
            }
        }

        manager.scanForPeripherals(withServices: [BLEConstants.serviceUUID], options: nil)
        isScanning = true
        log("scanning started")
    }

    func stopScanning() {
        manager.stopScan()
        isScanning = false
        log("scanning stopped")
    }

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[PasskeyCentral \(ts)] \(msg)")
    }
}

// MARK: - CBCentralManagerDelegate

extension PasskeyCentral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            log("BT state → \(central.state.rawValue)")
            if central.state == .poweredOn {
                startScanning()
            } else {
                isScanning = false
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        carPeripheral = peripheral
        central.stopScan()
        central.connect(peripheral, options: nil)
        Task { @MainActor in
            isScanning = false
            log("discovered \(peripheral.name ?? peripheral.identifier.uuidString), connecting…")
            lastEvent = "Car detected"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        incomingBuffer = Data()
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.serviceUUID])
        Task { @MainActor in
            isConnected = true
            isKeyPresent = false
            lastEvent = "Connected"
            log("connected — discovering services")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        carPeripheral = nil
        Task { @MainActor in
            isConnected = false
            log("connect failed: \(error?.localizedDescription ?? "unknown") — falling back to full scan")
            lastEvent = "Connection failed"
            // Skip cache so we don't retry a broken cached UUID immediately.
            startScanning(useCached: false)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        carPeripheral = nil
        challengeChar = nil
        responseChar  = nil
        incomingBuffer = Data()
        Task { @MainActor in
            isConnected = false
            isKeyPresent = false
            isAuthenticating = false
            log("disconnected — resuming scan")
            lastEvent = "Disconnected"
            if manager.state == .poweredOn { startScanning() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = peripherals.first {
            carPeripheral = p
            p.delegate = self
        }
    }
}

// MARK: - CBPeripheralDelegate

extension PasskeyCentral: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID })
        else {
            Task { @MainActor in log("service discovery failed: \(error?.localizedDescription ?? "not found")") }
            return
        }
        peripheral.discoverCharacteristics([BLEConstants.challengeUUID, BLEConstants.responseUUID],
                                           for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == BLEConstants.challengeUUID { challengeChar = char }
            if char.uuid == BLEConstants.responseUUID  { responseChar  = char }
        }
        if let cc = challengeChar {
            peripheral.setNotifyValue(true, for: cc)
            Task { @MainActor in log("subscribed to challenge — ready") }
        }
    }

    // MARK: - Challenge handling (runs entirely on the BLE queue)

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard characteristic.uuid == BLEConstants.challengeUUID,
              let chunk = characteristic.value else { return }

        // Accumulate chunks until we have the full 60-byte encrypted challenge.
        incomingBuffer.append(chunk)
        guard incomingBuffer.count >= 60 else { return }

        let nonce = Data(incomingBuffer.prefix(60))
        incomingBuffer = Data()

        Task { @MainActor in isAuthenticating = true }

        guard let secret = SecretStore.load() else {
            Task { @MainActor in isAuthenticating = false; lastEvent = "No key enrolled" }
            return
        }
        guard let plainNonce = try? SessionCrypto.decrypt(nonce) else {
            Task { @MainActor in isAuthenticating = false; lastEvent = "Decryption failed" }
            return
        }

        let mac = HMACAuth.response(for: plainNonce, secret: secret)

        guard let encResponse = try? SessionCrypto.encrypt(mac) else {
            Task { @MainActor in isAuthenticating = false; lastEvent = "Encrypt failed" }
            return
        }

        guard let rc = responseChar else { return }

        // Write response in chunks respecting the negotiated MTU.
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        var offset = 0
        while offset < encResponse.count {
            let end = min(offset + mtu, encResponse.count)
            peripheral.writeValue(Data(encResponse[offset..<end]), for: rc, type: .withoutResponse)
            offset = end
        }

        // Cache this peripheral's UUID so future visits skip the scan phase.
        let peripheralID = peripheral.identifier.uuidString
        let ts = Date().formatted(date: .omitted, time: .shortened)
        Task { @MainActor in
            UserDefaults.standard.set(peripheralID, forKey: peripheralIDKey)
            isAuthenticating = false
            isKeyPresent = true
            lastEvent = "Authenticated – \(ts)"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let err = error {
            Task { @MainActor in
                isAuthenticating = false
                lastEvent = "Write error: \(err.localizedDescription)"
            }
        }
    }
}
