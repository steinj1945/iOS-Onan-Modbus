import Foundation

@MainActor
final class EnrollmentManager: ObservableObject {
    @Published private(set) var isEnrolled: Bool = false
    @Published private(set) var enrolledLabel: String = ""

    init() {
        refresh()
    }

    func refresh() {
        isEnrolled   = SecretStore.load() != nil
        enrolledLabel = UserDefaults.standard.string(forKey: "enrolledLabel") ?? ""
    }

    /// Called when the user scans the QR code deep-link.
    /// URL format: CopCarpasskey://enroll?secret=<hex64>&label=<name>
    func enroll(from url: URL) throws {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == DeepLink.scheme,
            components.host   == DeepLink.enrollHost,
            let secretHex = components.queryItems?.first(where: { $0.name == "secret" })?.value,
            let label     = components.queryItems?.first(where: { $0.name == "label" })?.value,
            let secretData = Data(hexString: secretHex)
        else {
            throw EnrollmentError.invalidURL
        }

        try SecretStore.save(secretData)
        UserDefaults.standard.set(label, forKey: "enrolledLabel")
        refresh()
    }

    func removeKey() {
        SecretStore.delete()
        UserDefaults.standard.removeObject(forKey: "enrolledLabel")
        refresh()
    }

    enum EnrollmentError: LocalizedError {
        case invalidURL
        var errorDescription: String? { "Invalid enrollment QR code" }
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespaces)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
