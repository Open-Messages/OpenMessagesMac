import AppKit
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// A decrypted code, ready to show.
struct OtpItem: Identifiable, Equatable {
    let id: String
    let code: String
    let sender: String
    let body: String
    let receivedAt: Date
    let expiresAt: Date?
}

/// The sync key as stored on this Mac, tied to the account and salt it was derived for.
private struct StoredKey: Codable {
    let uid: String
    let salt: Data
    let key: Data
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case missingConfig(String)
        case signedOut
        case loading
        /// Signed in, but the phone hasn't created a sync key yet.
        case noKeyOnAccount
        case needsKey
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var codes: [OtpItem] = []
    private(set) var email: String?
    private(set) var busy = false
    private(set) var lastSync: Date?
    var errorMessage: String?

    var autoCopy: Bool {
        didSet { UserDefaults.standard.set(autoCopy, forKey: "autoCopy") }
    }
    var notify: Bool {
        didSet {
            UserDefaults.standard.set(notify, forKey: "notify")
            if notify { requestNotificationPermission() }
        }
    }

    static let pollInterval: Duration = .seconds(5)
    /// Every this many polls, re-read the key parameters and do a full reload.
    private static let fullReloadEvery = 60

    private var config: FirebaseConfig?
    private var session: AuthSession?
    private var storedKey: StoredKey?
    private var keyInfo: RemoteKeyInfo?
    private var cursor: String?
    private var pollTask: Task<Void, Never>?

    init() {
        autoCopy = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true
        notify = UserDefaults.standard.object(forKey: "notify") as? Bool ?? true
        do {
            config = try FirebaseConfig.load()
        } catch {
            phase = .missingConfig(error.localizedDescription)
            return
        }
        session = Keychain.load(AuthSession.self, account: "session")
        storedKey = Keychain.load(StoredKey.self, account: "syncKey")
        email = session?.email
        if notify { requestNotificationPermission() }
        Task { await loadKeyState() }
    }

    // MARK: Account

    func signIn() {
        guard let config else { return }
        perform {
            let googleToken = try await GoogleOAuth(config: config).signIn()
            let session = try await FirebaseAuthClient(config: config).signIn(googleIDToken: googleToken)
            if self.storedKey?.uid != session.uid { self.forgetKey() }
            try self.saveSession(session)
            await self.loadKeyState()
        }
    }

    func signOut() {
        stopPolling()
        Keychain.delete(account: "session")
        forgetKey()
        session = nil
        email = nil
        codes = []
        phase = .signedOut
    }

    // MARK: Sync key

    func unlock(passphrase: String) {
        guard let session, let info = keyInfo else { return }
        let normalized = OtpCrypto.normalize(passphrase)
        perform {
            let key = await Task.detached(priority: .userInitiated) {
                OtpCrypto.deriveKey(passphrase: normalized, salt: info.salt, iterations: info.iterations)
            }.value
            guard OtpCrypto.verify(key: key, check: info.check, uid: session.uid) else {
                self.errorMessage = "That key doesn't match the one set on your phone."
                return
            }
            let stored = StoredKey(uid: session.uid, salt: info.salt, key: key.withUnsafeBytes { Data($0) })
            try Keychain.save(stored, account: "syncKey")
            self.storedKey = stored
            self.phase = .ready
            await self.reload()
            self.startPolling()
        }
    }

    func forgetKey() {
        stopPolling()
        Keychain.delete(account: "syncKey")
        storedKey = nil
        codes = []
        if session != nil, phase == .ready { phase = .needsKey }
    }

    // MARK: Codes

    func copy(_ item: OtpItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.code, forType: .string)
        // Asks clipboard managers not to record it.
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }

    func delete(_ item: OtpItem) {
        perform {
            let session = try await self.freshSession()
            try await FirestoreClient(config: self.config!).delete(name: item.id, idToken: session.idToken)
            self.codes.removeAll { $0.id == item.id }
        }
    }

    func deleteAll() {
        let items = codes
        perform {
            let session = try await self.freshSession()
            let firestore = FirestoreClient(config: self.config!)
            for item in items {
                try await firestore.delete(name: item.id, idToken: session.idToken)
                self.codes.removeAll { $0.id == item.id }
            }
        }
    }

    func refresh() {
        perform { await self.loadKeyState() }
    }

    // MARK: Internals

    /// Works out which phase we're in by checking the account's key on the server.
    private func loadKeyState() async {
        guard let config else { return }
        guard session != nil else {
            phase = .signedOut
            return
        }
        do {
            let session = try await freshSession()
            let info = try await FirestoreClient(config: config).keyInfo(uid: session.uid, idToken: session.idToken)
            keyInfo = info
            guard let info else {
                forgetKey()
                phase = .noKeyOnAccount
                return
            }
            if let stored = storedKey, stored.uid == session.uid, stored.salt == info.salt {
                phase = .ready
                await reload()
                startPolling()
            } else {
                // The key was changed on the phone (new salt) or never entered here.
                forgetKey()
                phase = .needsKey
            }
        } catch let error as HTTP.APIError where error.status == 400 || error.status == 401 {
            // Refresh token revoked or account deleted.
            signOut()
            errorMessage = error.localizedDescription
        } catch {
            if phase == .loading { phase = storedKey == nil ? .needsKey : .ready }
            errorMessage = error.localizedDescription
        }
    }

    /// Replaces the list with the newest records.
    private func reload() async {
        cursor = nil
        codes = []
        await fetch(notifyNew: false)
    }

    private func fetch(notifyNew: Bool) async {
        guard let config, let stored = storedKey else { return }
        do {
            let session = try await freshSession()
            let records = try await FirestoreClient(config: config).otps(uid: session.uid, idToken: session.idToken, since: cursor)
            let key = SymmetricKey(data: stored.key)
            let aad = OtpCrypto.otpAAD(uid: session.uid)
            let known = Set(codes.map(\.id))
            let fresh: [OtpItem] = records.compactMap { record in
                guard !known.contains(record.name),
                      let plain = try? OtpCrypto.decrypt(record.sealed, key: key, aad: aad),
                      let payload = try? JSONDecoder().decode(OtpPayload.self, from: plain)
                else { return nil }
                return OtpItem(
                    id: record.name,
                    code: payload.code,
                    sender: payload.sender,
                    body: payload.body,
                    receivedAt: Date(timeIntervalSince1970: Double(payload.receivedAt) / 1000),
                    expiresAt: record.expiresAt
                )
            }
            // Results are newest first and never older than the cursor, so the first one is the new cursor.
            if let newest = records.first?.createdAt { cursor = newest }
            let now = Date()
            codes = (fresh + codes)
                .filter { ($0.expiresAt ?? .distantFuture) > now }
                .sorted { $0.receivedAt > $1.receivedAt }
            lastSync = now
            if notifyNew, let latest = fresh.max(by: { $0.receivedAt < $1.receivedAt }) {
                announce(latest)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            var count = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                count += 1
                if count % Self.fullReloadEvery == 0 {
                    await self.loadKeyState()
                    return // loadKeyState restarts polling when the key is still valid.
                }
                await self.fetch(notifyNew: true)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func freshSession() async throws -> AuthSession {
        guard let config, let session else { throw HTTP.APIError(status: 401, body: ["error": "Not signed in"]) }
        let fresh = try await FirebaseAuthClient(config: config).refreshed(session)
        if fresh.idToken != session.idToken { try saveSession(fresh) }
        return fresh
    }

    private func saveSession(_ session: AuthSession) throws {
        try Keychain.save(session, account: "session")
        self.session = session
        email = session.email
    }

    private func announce(_ item: OtpItem) {
        if autoCopy { copy(item) }
        guard notify, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "OTP received from \(item.sender)"
        content.body = autoCopy ? "\(item.code) copied to clipboard" : "\(item.code)\n\(item.body)"
        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        // Notifications need a real app bundle; `swift run` has none.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do {
                try await work()
            } catch GoogleOAuth.OAuthError.cancelled {
                // The user closed the sign-in sheet.
            } catch let error as NSError where error.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && error.code == 1 {
                // ASWebAuthenticationSessionError.canceledLogin
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
