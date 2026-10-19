import CryptoKit
import Foundation
import XCTest
@testable import OpenMessagesMac

/// Shared vector with the Android app's OtpCryptoTest. If this breaks, codes from the phone can't be read.
final class OtpCryptoTests: XCTestCase {
    let passphrase = "Grüße ABCD-EFGH"
    let salt = Data(0..<16)
    let uid = "testUid123"
    let plaintext = #"{"code":"482913","sender":"+15551234567","body":"Your code is 482913","receivedAt":1760870400000}"#

    func testDeriveKeyMatchesVector() {
        let key = OtpCrypto.deriveKey(passphrase: passphrase, salt: salt, iterations: 1000)
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }.base64EncodedString(), "pdKKPF59vu2JWYdNAdDt9J6+uHEZHQyEa4pvrfBbQL8=")
    }

    func testDecryptsVectorAndParsesPayload() throws {
        let key = OtpCrypto.deriveKey(passphrase: passphrase, salt: salt, iterations: 1000)
        let sealed = OtpCrypto.Sealed(
            iv: "AQEBAQEBAQEBAQEB",
            ct: "o3huhmbAJCdPX2n+7F4sAro/efe0GH3xTvcmRFe+Mb+ZfFEEzUXIVPuJzv6z098YWX1LfVeh6s35chcAcD+6ypDuYCRMLEDjk5TxZGCWCfuPt2awGfQf3NlkCj7uU0uYUorH9fQdzXanbetv0yDueW8="
        )
        let plain = try OtpCrypto.decrypt(sealed, key: key, aad: OtpCrypto.otpAAD(uid: uid))
        XCTAssertEqual(String(decoding: plain, as: UTF8.self), plaintext)
        let payload = try JSONDecoder().decode(OtpPayload.self, from: plain)
        XCTAssertEqual(payload.code, "482913")
        XCTAssertEqual(payload.receivedAt, 1_760_870_400_000)
    }

    func testWrongUidOrKeyFails() throws {
        let key = OtpCrypto.deriveKey(passphrase: passphrase, salt: salt, iterations: 1000)
        let check = try OtpCrypto.encrypt(Data(OtpCrypto.checkPlaintext.utf8), key: key, aad: OtpCrypto.checkAAD(uid: uid))
        XCTAssertTrue(OtpCrypto.verify(key: key, check: check, uid: uid))
        XCTAssertFalse(OtpCrypto.verify(key: key, check: check, uid: "someoneElse"))
        let wrong = OtpCrypto.deriveKey(passphrase: "wrong", salt: salt, iterations: 1000)
        XCTAssertFalse(OtpCrypto.verify(key: wrong, check: check, uid: uid))
    }

    func testParsesFirestoreTimestamps() {
        let date = FirestoreClient.parseDate("2026-10-19T10:00:00.123456Z")
        XCTAssertEqual(date?.timeIntervalSince1970 ?? 0, 1_792_404_000.123456, accuracy: 0.0001)
        XCTAssertNotNil(FirestoreClient.parseDate("2026-10-19T10:00:00Z"))
    }
}
