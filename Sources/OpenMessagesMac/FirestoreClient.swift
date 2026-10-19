import Foundation

/// Key parameters the phone publishes at `users/{uid}.otpSync`.
struct RemoteKeyInfo: Equatable {
    let salt: Data
    let iterations: Int
    let check: OtpCrypto.Sealed
}

/// One encrypted record from `users/{uid}/otps`.
struct RemoteOtp {
    /// Full document resource name, used to delete it.
    let name: String
    let sealed: OtpCrypto.Sealed
    /// Raw RFC 3339 value, reused as the query cursor so no precision is lost.
    let createdAt: String
    let expiresAt: Date?
}

/// The few Firestore REST calls OTP sync needs.
struct FirestoreClient {
    let config: FirebaseConfig

    private var documentsURL: String {
        "https://firestore.googleapis.com/v1/projects/\(config.projectID)/databases/(default)/documents"
    }

    /// Nil when the account has never set up a sync key.
    func keyInfo(uid: String, idToken: String) async throws -> RemoteKeyInfo? {
        let request = makeRequest("\(documentsURL)/users/\(uid)", idToken: idToken)
        let json: [String: Any]
        do {
            json = try await HTTP.json(request)
        } catch let error as HTTP.APIError where error.status == 404 {
            return nil
        }
        guard let meta = (json["fields"] as? [String: Any])?["otpSync"].flatMap(Self.map),
              let saltString = meta["salt"].flatMap(Self.string), let salt = Data(base64Encoded: saltString),
              let iterations = meta["iterations"].flatMap(Self.int),
              let check = meta["check"].flatMap(Self.map),
              let iv = check["iv"].flatMap(Self.string), let ct = check["ct"].flatMap(Self.string)
        else { return nil }
        return RemoteKeyInfo(salt: salt, iterations: iterations, check: .init(iv: iv, ct: ct))
    }

    /// Newest records first. With `since`, only records created at or after that cursor.
    func otps(uid: String, idToken: String, since: String?, limit: Int = 50) async throws -> [RemoteOtp] {
        var query: [String: Any] = [
            "from": [["collectionId": "otps"]],
            "orderBy": [["field": ["fieldPath": "createdAt"], "direction": "DESCENDING"]],
            "limit": limit,
        ]
        if let since {
            query["where"] = [
                "fieldFilter": [
                    "field": ["fieldPath": "createdAt"],
                    "op": "GREATER_THAN_OR_EQUAL",
                    "value": ["timestampValue": since],
                ],
            ]
        }
        var request = makeRequest("\(documentsURL)/users/\(uid):runQuery", idToken: idToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": query])
        let rows = try await HTTP.jsonAny(request) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String,
                  let fields = doc["fields"] as? [String: Any],
                  let iv = fields["iv"].flatMap(Self.string), let ct = fields["ct"].flatMap(Self.string),
                  let createdAt = fields["createdAt"].flatMap(Self.timestamp)
            else { return nil }
            return RemoteOtp(
                name: name,
                sealed: .init(iv: iv, ct: ct),
                createdAt: createdAt,
                expiresAt: fields["expiresAt"].flatMap(Self.timestamp).flatMap(Self.parseDate)
            )
        }
    }

    func delete(name: String, idToken: String) async throws {
        var request = makeRequest("https://firestore.googleapis.com/v1/\(name)", idToken: idToken)
        request.httpMethod = "DELETE"
        _ = try await HTTP.jsonAny(request)
    }

    private func makeRequest(_ url: String, idToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Firestore value decoding

    private static func map(_ value: Any) -> [String: Any]? {
        ((value as? [String: Any])?["mapValue"] as? [String: Any])?["fields"] as? [String: Any]
    }

    private static func string(_ value: Any) -> String? {
        (value as? [String: Any])?["stringValue"] as? String
    }

    private static func int(_ value: Any) -> Int? {
        guard let raw = (value as? [String: Any])?["integerValue"] else { return nil }
        return (raw as? String).flatMap(Int.init) ?? (raw as? Int)
    }

    private static func timestamp(_ value: Any) -> String? {
        (value as? [String: Any])?["timestampValue"] as? String
    }

    /// Parses RFC 3339 with any number of fractional digits (Firestore sends up to nanoseconds).
    static func parseDate(_ string: String) -> Date? {
        var base = string
        var fraction = 0.0
        if let dot = string.firstIndex(of: "."), let zone = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            fraction = Double("0" + string[dot..<zone]) ?? 0
            base = String(string[..<dot] + string[zone...])
        }
        return ISO8601DateFormatter().date(from: base).map { $0.addingTimeInterval(fraction) }
    }
}
