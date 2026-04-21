import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var enrollment: EnrollmentManager
    @StateObject private var watchSync  = WatchSyncManager.shared
    @State private var showConfirmRemove = false
    @State private var syncFeedback: String?

    var body: some View {
        List {
            Section("Key") {
                if enrollment.isEnrolled {
                    LabeledContent("Device", value: enrollment.enrolledLabel)
                    Button("Sync to Apple Watch") {
                        watchSync.pushSecretToWatch()
                        syncFeedback = watchSync.syncStatus
                    }
                    if let feedback = syncFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Remove Key", role: .destructive) {
                        showConfirmRemove = true
                    }
                } else {
                    Text("No key enrolled. Scan a QR code from the admin portal.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Watch Sync", value: watchSync.syncStatus)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove Key", isPresented: $showConfirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { enrollment.removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device will no longer be able to unlock. You can re-enroll from the admin portal.")
        }
    }
}
