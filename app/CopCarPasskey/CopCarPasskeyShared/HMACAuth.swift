import Foundation
import CryptoKit

enum HMACAuth {
    /// Compute HMAC-SHA256(nonce, secret) — same algorithm as Arduino.
    static func response(for nonce: Data, secret: Data) -> Data {
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: nonce, using: key)
        return Data(mac)
    }

    static func verify(nonce: Data, response: Data, secret: Data) -> Bool {
        let expected = Self.response(for: nonce, secret: secret)
        return expected == response
    }
}
