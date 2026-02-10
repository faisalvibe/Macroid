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
        .commands {
            // Override Edit > Paste (Cmd+V) to also send to phone
            CommandGroup(replacing: .pasteboard) {
                Button("Paste") {
                    syncManager.sendClipboardContent()
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }
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
