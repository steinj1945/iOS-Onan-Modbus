import Foundation
import CoreBluetooth

enum BLEConstants {
    static let serviceUUID      = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
    static let challengeUUID    = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")
    static let responseUUID     = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")
    static let statusUUID       = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567893")
}

enum KeychainKeys {
    static let sharedSecret = "com.CopCar.passkey.shared-secret"
}

enum DeepLink {
    // CopCarpasskey://enroll?secret=<hex>&label=<name>
    static let scheme = "CopCarpasskey"
    static let enrollHost = "enroll"
}
