import Foundation

/// Top-level entry point. Dispatches between FileLocker and FolderLocker based on the item.
public enum Locker {
    public static let lockedExtension = "locked"

    public static func isLocked(url: URL) -> Bool {
        url.pathExtension == lockedExtension
    }

    /// Locks a file or folder. Returns the URL of the resulting `.locked` item.
    public static func lock(itemAt url: URL, password: String) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw LockError.itemNotFound(url.path)
        }
        if isDir.boolValue {
            return try FolderLocker.lock(folderURL: url, password: password)
        } else {
            return try FileLocker.lock(fileURL: url, password: password)
        }
    }

    /// Unlocks a `.locked` item by reading its header and routing accordingly.
    public static func unlock(itemAt url: URL, password: String) throws -> URL {
        let data = try Data(contentsOf: url)
        let locked = try LockedFile.deserialize(data)
        if locked.header.isDirectory {
            return try FolderLocker.unlock(lockedURL: url, password: password)
        } else {
            return try FileLocker.unlock(lockedURL: url, password: password)
        }
    }
}
