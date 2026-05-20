import Foundation

public enum LockedFormatError: Error, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case truncated
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .invalidMagic: return "This file is not a FolderLock item."
        case .unsupportedVersion(let v): return "Unsupported FolderLock version: \(v)."
        case .truncated: return "FolderLock item is truncated or corrupted."
        case .invalidName: return "FolderLock item has an invalid original name."
        }
    }
}

public struct LockedFileHeader {
    public static let magic: [UInt8] = [0x4C, 0x4F, 0x43, 0x4B] // "LOCK"
    public static let version: UInt8 = 0x01
    public static let saltSize = 16
    public static let nonceSize = 12
    public static let tagSize = 16
    public static let defaultIterations: UInt32 = 200_000

    public let version: UInt8
    public let isDirectory: Bool
    public let iterations: UInt32
    public let salt: Data
    public let nonce: Data
    public let originalName: String

    public init(isDirectory: Bool, iterations: UInt32, salt: Data, nonce: Data, originalName: String) {
        self.version = LockedFileHeader.version
        self.isDirectory = isDirectory
        self.iterations = iterations
        self.salt = salt
        self.nonce = nonce
        self.originalName = originalName
    }
}

public struct LockedFile {
    public let header: LockedFileHeader
    public let ciphertext: Data
    public let tag: Data

    public init(header: LockedFileHeader, ciphertext: Data, tag: Data) {
        self.header = header
        self.ciphertext = ciphertext
        self.tag = tag
    }

    public func serialize() -> Data {
        var out = Data()
        out.append(contentsOf: LockedFileHeader.magic)
        out.append(header.version)
        out.append(header.isDirectory ? 1 : 0)
        out.append(0) // reserved
        out.append(0) // reserved
        out.appendUInt32BE(header.iterations)
        out.append(header.salt)
        out.append(header.nonce)
        let nameBytes = Data(header.originalName.utf8)
        precondition(nameBytes.count <= 0xFFFF, "original name too long")
        out.appendUInt16BE(UInt16(nameBytes.count))
        out.append(nameBytes)
        out.append(ciphertext)
        out.append(tag)
        return out
    }

    public static func deserialize(_ data: Data) throws -> LockedFile {
        var reader = ByteReader(data)
        let magic = try reader.readBytes(4)
        guard magic == LockedFileHeader.magic else { throw LockedFormatError.invalidMagic }
        let version = try reader.readUInt8()
        guard version == LockedFileHeader.version else { throw LockedFormatError.unsupportedVersion(version) }
        let isDirectoryByte = try reader.readUInt8()
        _ = try reader.readUInt8() // reserved
        _ = try reader.readUInt8() // reserved
        let iterations = try reader.readUInt32BE()
        let salt = try reader.readData(LockedFileHeader.saltSize)
        let nonce = try reader.readData(LockedFileHeader.nonceSize)
        let nameLen = Int(try reader.readUInt16BE())
        let nameData = try reader.readData(nameLen)
        guard let name = String(data: nameData, encoding: .utf8) else { throw LockedFormatError.invalidName }
        let remainingCount = reader.remaining
        guard remainingCount >= LockedFileHeader.tagSize else { throw LockedFormatError.truncated }
        let ciphertext = try reader.readData(remainingCount - LockedFileHeader.tagSize)
        let tag = try reader.readData(LockedFileHeader.tagSize)
        let header = LockedFileHeader(
            isDirectory: isDirectoryByte == 1,
            iterations: iterations,
            salt: salt,
            nonce: nonce,
            originalName: name
        )
        return LockedFile(header: header, ciphertext: ciphertext, tag: tag)
    }
}

private struct ByteReader {
    let data: Data
    var offset: Int = 0

    init(_ data: Data) { self.data = data }

    var remaining: Int { data.count - offset }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw LockedFormatError.truncated }
        let start = data.startIndex + offset
        let end = start + count
        let bytes = [UInt8](data[start..<end])
        offset += count
        return bytes
    }

    mutating func readData(_ count: Int) throws -> Data {
        let bytes = try readBytes(count)
        return Data(bytes)
    }

    mutating func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(1)
        return bytes[0]
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let bytes = try readBytes(2)
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let bytes = try readBytes(4)
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
