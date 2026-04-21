import SwiftUI
import WatchKit

struct WatchContentView: View {
    @EnvironmentObject var peripheral: WatchPasskeyPeripheral
    @EnvironmentObject var sync: WatchSyncManager

    private var enrolled: Bool { SecretStore.load() != nil }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(
                        peripheral.isAdvertising ? Color.green.opacity(0.3) : Color.gray.opacity(0.15),
                        lineWidth: 6)
                    .frame(width: 70, height: 70)

                Image(systemName: enrolled ? "key.fill" : "key.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(peripheral.isAdvertising ? .green : .gray)
            }

            Text(peripheral.isAdvertising ? "Ready" : "Inactive")
                .font(.headline)

            Text(peripheral.lastEvent)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !enrolled {
                Text("Open iPhone app to sync key")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
