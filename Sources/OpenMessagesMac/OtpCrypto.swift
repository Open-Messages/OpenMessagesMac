import CommonCrypto
import CryptoKit
import Foundation

/// Mirror of the phone's OtpCrypto; the format is specified in OpenMessages/docs/otp-sync.md.
enum OtpCrypto {
    static let version = 1
    static let checkPlaintext = "openmessages-otp-sync-check"

    struct Sealed: Equatable {
        let iv: String
        let ct: String
    }

    static func otpAAD(uid: String) -> Data { Data("openmessages/otp/v\(version)/\(uid)".utf8) }
    static func checkAAD(uid: String) -> Data { Data("openmessages/check/v\(version)/\(uid)".utf8) }

    /// The phone trims the passphrase before deriving, so we do too.
    static func normalize(_ passphrase: String) -> String {
        passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBufferPointer { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    derived.count
                )
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return SymmetricKey(data: derived)
    }

    /// AES-256-GCM; `ct` is ciphertext followed by the 16-byte tag, as Java produces it.
    static func decrypt(_ sealed: Sealed, key: SymmetricKey, aad: Data) throws -> Data {
        guard let iv = Data(base64Encoded: sealed.iv), let combined = Data(base64Encoded: sealed.ct),
              combined.count >= 16
        else { throw CryptoError.malformed }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: combined.dropLast(16),
            tag: combined.suffix(16)
        )
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    static func encrypt(_ plaintext: Data, key: SymmetricKey, aad: Data, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> Sealed {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        return Sealed(iv: Data(box.nonce).base64EncodedString(), ct: (box.ciphertext + box.tag).base64EncodedString())
    }

    /// True if `key` opens the account's key-check record.
    static func verify(key: SymmetricKey, check: Sealed, uid: String) -> Bool {
        guard let plain = try? decrypt(check, key: key, aad: checkAAD(uid: uid)) else { return false }
        return String(decoding: plain, as: UTF8.self) == checkPlaintext
    }

    enum CryptoError: Error {
        case malformed
    }
}

/// Decrypted contents of one synced code.
struct OtpPayload: Decodable {
    let code: String
    let sender: String
    let body: String
    let receivedAt: Int64
}
