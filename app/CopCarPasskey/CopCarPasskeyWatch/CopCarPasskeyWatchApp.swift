import SwiftUI

@main
struct CopCarPasskeyWatchApp: App {
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
