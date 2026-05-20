import Foundation

public enum LockError: Error, LocalizedError {
    case itemNotFound(String)
    case alreadyExists(String)
    case wrongType(String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let p): return "Item not found: \(p)"
        case .alreadyExists(let p): return "Destination already exists: \(p)"
        case .wrongType(let m): return m
        case .ioError(let m): return m
        }
    }
}

public enum FileLocker {
    /// Encrypts a file in place. Returns the URL of the resulting `.locked` file.
    public static func lock(fileURL: URL, password: String) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
            throw LockError.itemNotFound(fileURL.path)
        }
        guard !isDir.boolValue else {
            throw LockError.wrongType("Use FolderLocker for directories")
        }

        let outURL = fileURL.appendingPathExtension("locked")
        guard !fm.fileExists(atPath: outURL.path) else {
            throw LockError.alreadyExists(outURL.lastPathComponent)
        }

        let plaintext = try Data(contentsOf: fileURL)
        let salt = CryptoEngine.randomSalt()
        let iterations = LockedFileHeader.defaultIterations
        let key = try CryptoEngine.deriveKey(password: password, salt: salt, iterations: iterations)
        let box = try CryptoEngine.encrypt(data: plaintext, key: key)

        let header = LockedFileHeader(
            isDirectory: false,
            iterations: iterations,
            salt: salt,
            nonce: Data(box.nonce),
            originalName: fileURL.lastPathComponent
        )
        let locked = LockedFile(header: header, ciphertext: box.ciphertext, tag: box.tag)
        try locked.serialize().write(to: outURL, options: [.atomic])
        try fm.removeItem(at: fileURL)
        return outURL
    }

    /// Decrypts a `.locked` file in place. Returns the URL of the restored file.
    public static func unlock(lockedURL: URL, password: String) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: lockedURL.path) else {
            throw LockError.itemNotFound(lockedURL.path)
        }
        let data = try Data(contentsOf: lockedURL)
        let locked = try LockedFile.deserialize(data)
        guard !locked.header.isDirectory else {
            throw LockError.wrongType("This locked item is a folder. Use FolderLocker.")
        }

        let restored = lockedURL.deletingLastPathComponent().appendingPathComponent(locked.header.originalName)
        guard !fm.fileExists(atPath: restored.path) else {
            throw LockError.alreadyExists(locked.header.originalName)
        }

        let key = try CryptoEngine.deriveKey(
            password: password,
            salt: locked.header.salt,
            iterations: locked.header.iterations
        )
        let plaintext = try CryptoEngine.decrypt(
            ciphertext: locked.ciphertext,
            nonce: locked.header.nonce,
            tag: locked.tag,
            key: key
        )
        try plaintext.write(to: restored, options: [.atomic])
        try fm.removeItem(at: lockedURL)
        return restored
    }
}
