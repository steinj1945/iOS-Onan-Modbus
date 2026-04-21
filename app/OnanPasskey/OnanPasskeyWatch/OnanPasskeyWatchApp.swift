import SwiftUI

@main
struct OnanPasskeyWatchApp: App {
    @StateObject private var peripheral = WatchPasskeyPeripheral()
    @StateObject private var sync       = WatchSyncManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(peripheral)
                .environmentObject(sync)
        }
    }
}
