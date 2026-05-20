import SwiftUI
import AppKit
import FolderLockCore

@main
struct FolderLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = OperationCoordinator.shared

    var body: some Scene {
        WindowGroup("FolderLock") {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 560, minHeight: 420)
                .onOpenURL { url in
                    coordinator.handleIncoming(url: url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Lock File or Folder…") {
                    coordinator.promptOpenForLock()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Unlock Locked Item…") {
                    coordinator.promptOpenForUnlock()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            OperationCoordinator.shared.handleIncoming(url: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
