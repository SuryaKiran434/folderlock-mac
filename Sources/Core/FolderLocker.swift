import Foundation

public enum FolderLocker {
    /// Zips a folder, encrypts the archive, replaces the folder with a `.locked` file.
    public static func lock(folderURL: URL, password: String) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir) else {
            throw LockError.itemNotFound(folderURL.path)
        }
        guard isDir.boolValue else {
            throw LockError.wrongType("Use FileLocker for files")
        }

        let outURL = folderURL.appendingPathExtension("locked")
        guard !fm.fileExists(atPath: outURL.path) else {
            throw LockError.alreadyExists(outURL.lastPathComponent)
        }

        let workDir = fm.temporaryDirectory.appendingPathComponent("folderlock-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let zipURL = workDir.appendingPathComponent("payload.zip")
        try runZip(source: folderURL, destination: zipURL)

        let zipData = try Data(contentsOf: zipURL)
        let salt = CryptoEngine.randomSalt()
        let iterations = LockedFileHeader.defaultIterations
        let key = try CryptoEngine.deriveKey(password: password, salt: salt, iterations: iterations)
        let box = try CryptoEngine.encrypt(data: zipData, key: key)

        let header = LockedFileHeader(
            isDirectory: true,
            iterations: iterations,
            salt: salt,
            nonce: Data(box.nonce),
            originalName: folderURL.lastPathComponent
        )
        let locked = LockedFile(header: header, ciphertext: box.ciphertext, tag: box.tag)
        try locked.serialize().write(to: outURL, options: [.atomic])
        try fm.removeItem(at: folderURL)
        return outURL
    }

    /// Decrypts a folder-locked file and restores the original folder.
    public static func unlock(lockedURL: URL, password: String) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: lockedURL.path) else {
            throw LockError.itemNotFound(lockedURL.path)
        }
        let data = try Data(contentsOf: lockedURL)
        let locked = try LockedFile.deserialize(data)
        guard locked.header.isDirectory else {
            throw LockError.wrongType("This locked item is a file. Use FileLocker.")
        }

        let parent = lockedURL.deletingLastPathComponent()
        let restored = parent.appendingPathComponent(locked.header.originalName)
        guard !fm.fileExists(atPath: restored.path) else {
            throw LockError.alreadyExists(locked.header.originalName)
        }

        let key = try CryptoEngine.deriveKey(
            password: password,
            salt: locked.header.salt,
            iterations: locked.header.iterations
        )
        let zipData = try CryptoEngine.decrypt(
            ciphertext: locked.ciphertext,
            nonce: locked.header.nonce,
            tag: locked.tag,
            key: key
        )

        let workDir = fm.temporaryDirectory.appendingPathComponent("folderlock-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let zipURL = workDir.appendingPathComponent("payload.zip")
        try zipData.write(to: zipURL)
        try runUnzip(source: zipURL, destinationParent: parent)

        guard fm.fileExists(atPath: restored.path) else {
            throw LockError.ioError("Unzip completed but expected folder not found at \(restored.path)")
        }
        try fm.removeItem(at: lockedURL)
        return restored
    }

    private static func runZip(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source.deletingLastPathComponent()
        process.arguments = ["-r", "-q", "-X", destination.path, source.lastPathComponent]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LockError.ioError("zip failed (\(process.terminationStatus)): \(err)")
        }
    }

    private static func runUnzip(source: URL, destinationParent: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", source.path, "-d", destinationParent.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LockError.ioError("unzip failed (\(process.terminationStatus)): \(err)")
        }
    }
}
