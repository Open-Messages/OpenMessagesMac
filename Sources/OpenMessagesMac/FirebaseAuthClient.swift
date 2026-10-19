import Foundation

/// A Firebase Auth session, persisted in the keychain so the app stays signed in.
struct AuthSession: Codable {
    var uid: String
    var email: String?
    var idToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Firebase Auth over its REST API (Identity Toolkit + Secure Token).
struct FirebaseAuthClient {
    let config: FirebaseConfig

    func signIn(googleIDToken: String) async throws -> AuthSession {
        var request = makeRequest("https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "postBody": "id_token=\(googleIDToken)&providerId=google.com",
            "requestUri": "http://localhost",
            "returnSecureToken": true,
            "returnIdpCredential": true,
        ])
        let json = try await HTTP.json(request)
        guard let uid = json["localId"] as? String, let idToken = json["idToken"] as? String,
              let refreshToken = json["refreshToken"] as? String
        else { throw HTTP.APIError(status: 200, body: json) }
        return AuthSession(
            uid: uid,
            email: json["email"] as? String,
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(Double(json["expiresIn"] as? String ?? "3600") ?? 3600)
        )
    }

    /// Returns `session` with a fresh ID token if the current one expires within five minutes.
    func refreshed(_ session: AuthSession) async throws -> AuthSession {
        guard session.expiresAt.timeIntervalSinceNow < 300 else { return session }
        var request = makeRequest("https://securetoken.googleapis.com/v1/token")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleOAuth.formEncode(["grant_type": "refresh_token", "refresh_token": session.refreshToken])
        let json = try await HTTP.json(request)
        guard let idToken = json["id_token"] as? String, let refreshToken = json["refresh_token"] as? String else {
            throw HTTP.APIError(status: 200, body: json)
        }
        var next = session
        next.idToken = idToken
        next.refreshToken = refreshToken
        next.expiresAt = Date().addingTimeInterval(Double(json["expires_in"] as? String ?? "3600") ?? 3600)
        return next
    }

    private func makeRequest(_ url: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(url)?key=\(config.apiKey)")!)
        request.httpMethod = "POST"
        // Firebase-created Apple API keys may be restricted to the app's bundle ID.
        request.setValue(config.bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        return request
    }
}
