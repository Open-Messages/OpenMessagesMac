import Foundation

enum HTTP {
    /// Performs `request` and returns the JSON body, turning Google API errors into readable messages.
    static func json(_ request: URLRequest) async throws -> [String: Any] {
        let any = try await jsonAny(request)
        return any as? [String: Any] ?? [:]
    }

    static func jsonAny(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = data.isEmpty ? [String: Any]() : try JSONSerialization.jsonObject(with: data)
        guard (200..<300).contains(status) else { throw APIError(status: status, body: body) }
        return body
    }

    struct APIError: LocalizedError {
        let status: Int
        let body: Any

        var message: String? {
            let error = (body as? [String: Any])?["error"]
            if let error = error as? [String: Any] { return error["message"] as? String }
            if let error = error as? String {
                return ((body as? [String: Any])?["error_description"] as? String).map { "\(error): \($0)" } ?? error
            }
            return nil
        }

        var errorDescription: String? { "Request failed (\(status)): \(message ?? "unknown error")" }
    }
}
