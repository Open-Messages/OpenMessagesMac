import Foundation

/// Values from the Apple app's `GoogleService-Info.plist` in the Firebase console.
struct FirebaseConfig {
    let apiKey: String
    let projectID: String
    /// OAuth client of the Apple app; Google redirects back to its reversed form.
    let clientID: String
    let reversedClientID: String
    let bundleID: String

    static let fileName = "GoogleService-Info.plist"

    /// Where the app looks for the plist when it isn't bundled inside the .app.
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMessages", isDirectory: true)
    }

    static func load() throws -> FirebaseConfig {
        let candidates = [
            Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
            supportDirectory.appendingPathComponent(fileName),
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ConfigError.missing
        }
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ConfigError.invalid("not a dictionary")
        }
        func value(_ key: String) throws -> String {
            guard let v = plist[key] as? String, !v.isEmpty else { throw ConfigError.invalid("missing \(key)") }
            return v
        }
        return FirebaseConfig(
            apiKey: try value("API_KEY"),
            projectID: try value("PROJECT_ID"),
            clientID: try value("CLIENT_ID"),
            reversedClientID: try value("REVERSED_CLIENT_ID"),
            bundleID: (plist["BUNDLE_ID"] as? String) ?? Bundle.main.bundleIdentifier ?? ""
        )
    }
}

enum ConfigError: LocalizedError {
    case missing
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missing:
            return "\(FirebaseConfig.fileName) not found. Put it next to the app's Info.plist (scripts/build-app.sh does this) "
                + "or in \(FirebaseConfig.supportDirectory.path)."
        case .invalid(let why):
            return "\(FirebaseConfig.fileName) is invalid: \(why)."
        }
    }
}
