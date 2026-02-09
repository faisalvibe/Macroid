import SwiftUI

@main
struct MacroidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncManager = SyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView(syncManager: syncManager)
                .frame(minWidth: 500, minHeight: 400)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 700, height: 500)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup handled by SyncManager deinit
    }
}
