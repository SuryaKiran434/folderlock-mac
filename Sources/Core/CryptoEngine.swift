import Foundation
import CryptoKit
import CommonCrypto

public enum CryptoError: Error, LocalizedError {
    case emptyPassword
    case keyDerivationFailed
    case encryptionFailed
    case wrongPasswordOrCorrupted

    public var errorDescription: String? {
        switch self {
        case .emptyPassword: return "Password cannot be empty."
        case .keyDerivationFailed: return "Failed to derive encryption key."
        case .encryptionFailed: return "Encryption failed."
        case .wrongPasswordOrCorrupted: return "Wrong password, or the item is corrupted."
        }
    }
}

public enum CryptoEngine {
    public static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard !password.isEmpty else { throw CryptoError.emptyPassword }
        guard let passwordData = password.data(using: .utf8) else { throw CryptoError.keyDerivationFailed }

        var derivedKey = Data(count: 32)
        let status = derivedKey.withUnsafeMutableBytes { keyBuf -> Int32 in
            passwordData.withUnsafeBytes { pwBuf -> Int32 in
                salt.withUnsafeBytes { saltBuf -> Int32 in
                    guard let pwPtr = pwBuf.baseAddress?.assumingMemoryBound(to: Int8.self),
                          let saltPtr = saltBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let keyPtr = keyBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr, passwordData.count,
                        saltPtr, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        keyPtr, 32
                    )
                }
            }
        }
        guard status == 0 else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }

    public static func randomSalt() -> Data {
        randomBytes(count: LockedFileHeader.saltSize)
    }

    public static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }

    public static func encrypt(data: Data, key: SymmetricKey) throws -> AES.GCM.SealedBox {
        do {
            return try AES.GCM.seal(data, using: key)
        } catch {
            throw CryptoError.encryptionFailed
        }
    }

    public static func decrypt(ciphertext: Data, nonce: Data, tag: Data, key: SymmetricKey) throws -> Data {
        do {
            let aesNonce = try AES.GCM.Nonce(data: nonce)
            let box = try AES.GCM.SealedBox(nonce: aesNonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.wrongPasswordOrCorrupted
        }
    }
}
