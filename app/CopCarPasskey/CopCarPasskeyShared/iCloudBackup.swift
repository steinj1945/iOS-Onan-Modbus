import Foundation

/// Stores the enrolled key in the app's iCloud Documents container so it
/// appears under the app in iCloud Settings and survives reinstalls / new phones.
///
/// Requires the iCloud Documents capability (iCloud.com.copcar.passkey container).
enum iCloudBackup {
    private static let containerID = "iCloud.com.copcar.passkey"
    private static let fileName    = "passkey-backup.json"

    private struct Payload: Codable {
        let secret: Data
        let label: String
        let savedAt: Date
    }

    static func save(secret: Data, label: String) async throws {
        let dir = try await documentsURL()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Payload(secret: secret, label: label, savedAt: Date()))
        try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
    }

    static func load() async throws -> (secret: Data, label: String, savedAt: Date)? {
        let dir  = try await documentsURL()
        let file = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: file))
        return (payload.secret, payload.label, payload.savedAt)
    }

    // Runs url(forUbiquityContainerIdentifier:) off the main thread — it can block.
    private static func documentsURL() async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard let base = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
                throw BackupError.unavailable
            }
            return base.appendingPathComponent("Documents")
        }.value
    }

    enum BackupError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "iCloud is not available. Sign in to iCloud in Settings and enable iCloud Drive, then try again."
        }
    }
}
