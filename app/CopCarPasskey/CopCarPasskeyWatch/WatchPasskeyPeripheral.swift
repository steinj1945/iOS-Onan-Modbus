import Foundation
import CoreBluetooth

/// watchOS equivalent of PasskeyPeripheral.
/// Identical BLE peripheral logic — advertises the same service UUID
/// and responds to challenge-response requests from the Arduino.
/// The RSSI_THRESHOLD on the Arduino side can be tightened for Watch
/// to require closer proximity (NFC-style tap feel).
@MainActor
final class WatchPasskeyPeripheral: NSObject, ObservableObject {
    @Published private(set) var isAdvertising = false
    @Published private(set) var lastEvent: String = "Idle"
    @Published private(set) var relayOpen: Bool = false

    private var manager: CBPeripheralManager!
    private var responseChar: CBMutableCharacteristic!
    private var statusChar: CBMutableCharacteristic!

    override init() {
        super.init()
        manager = CBPeripheralManager(
            delegate: self,
            queue: .global(qos: .background),
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.CopCar.passkey.watch.peripheral"])
    }

    private func setupServices() {
        manager.removeAllServices()

        responseChar = CBMutableCharacteristic(
            type:        BLEConstants.responseUUID,
            properties:  [.notify],
            value:       nil,
            permissions: .readable)

        statusChar = CBMutableCharacteristic(
            type:        BLEConstants.statusUUID,
            properties:  [.writeWithoutResponse],
            value:       nil,
            permissions: .writeable)

        let challengeChar = CBMutableCharacteristic(
            type:        BLEConstants.challengeUUID,
            properties:  [.writeWithoutResponse],
            value:       nil,
            permissions: .writeable)

        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [challengeChar, responseChar, statusChar]
        manager.add(service)
    }

    @MainActor
    private func handleChallenge(_ nonce: Data) {
        guard let secret = SecretStore.load() else {
            lastEvent = "No key enrolled"
            return
        }
        let mac = HMACAuth.response(for: nonce, secret: secret)
        manager.updateValue(mac, for: responseChar, onSubscribedCentrals: nil)
        lastEvent = "Unlocked \(Date().formatted(date: .omitted, time: .shortened))"
        WKInterfaceDevice.current().play(.success)
    }
}

extension WatchPasskeyPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        if p.state == .poweredOn {
            Task { @MainActor in setupServices() }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        p.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "CopCarPasskey"
        ])
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
        Task { @MainActor in isAdvertising = error == nil }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEConstants.challengeUUID,
                  let nonce = request.value, nonce.count == 32 else { continue }
            Task { @MainActor in handleChallenge(nonce) }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       willRestoreState dict: [String: Any]) {}
}
