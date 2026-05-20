import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {

    private static let lockedExtension = "locked"

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "FolderLock")
        guard menuKind == .contextualMenuForItems else { return menu }

        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selected.isEmpty else { return menu }

        let lockedCount = selected.filter { $0.pathExtension == FinderSync.lockedExtension }.count
        let totalCount = selected.count

        if lockedCount == 0 {
            let item = NSMenuItem(
                title: "Lock with FolderLock",
                action: #selector(lockSelected(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Lock")
            item.target = self
            menu.addItem(item)
        } else if lockedCount == totalCount {
            let item = NSMenuItem(
                title: "Unlock with FolderLock",
                action: #selector(unlockSelected(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: "Unlock")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @IBAction func lockSelected(_ sender: AnyObject?) {
        launchHost(action: "lock")
    }

    @IBAction func unlockSelected(_ sender: AnyObject?) {
        launchHost(action: "unlock")
    }

    private func launchHost(action: String) {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selected.isEmpty else { return }
        var comps = URLComponents()
        comps.scheme = "folderlock"
        comps.host = action
        comps.queryItems = selected.map { URLQueryItem(name: "path", value: $0.path) }
        guard let url = comps.url else { return }
        NSWorkspace.shared.open(url)
    }
}
