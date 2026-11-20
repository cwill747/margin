import Foundation
import CryptoKit
import Security

struct OAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    let clientID: String
}

struct OAuthAttempt {
    static let callback = "us.cwill.margin://oauth/callback"
    let verifier: String
    let state: String
    init() throws {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw APIError(message: "Could not start secure sign-in. Try again.")
            }
            return Data(bytes).base64URL
        }
        verifier = try random(); state = try random()
    }
    func authorizationURL(origin: URL, clientID: String) -> URL {
        var parts = URLComponents(url: origin.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = ["client_id": clientID, "redirect_uri": Self.callback, "response_type": "code", "state": state,
                            "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL, "code_challenge_method": "S256", "scope": "read write"].map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }
    func code(from url: URL) throws -> String {
        guard url.scheme == "us.cwill.margin", url.host == "oauth", url.path == "/callback",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else {
            throw APIError(message: "The sign-in response did not match this request. Start sign-in again.")
        }
        guard !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw APIError(message: "Sign-in was not authorized. Try again when ready.")
        }
        return code
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

actor OAuthSession {
    let origin: URL
    var gateway: GatewayConfiguration
    private var credentials: OAuthCredentials
    private var refresh: Task<OAuthCredentials, Error>?
    private var invalidated = false
    init(origin: URL, gateway: GatewayConfiguration, credentials: OAuthCredentials) {
        self.origin = origin; self.gateway = gateway; self.credentials = credentials
    }
    static func account(_ origin: URL) -> String { "oauth:\(origin.host!.lowercased()):\(origin.port ?? 443)" }
    static func load(origin: URL, gateway: GatewayConfiguration) -> OAuthSession? {
        guard let text = CredentialStore.read(account: account(origin)),
              let credentials = try? JSONDecoder().decode(OAuthCredentials.self, from: Data(text.utf8)) else { return nil }
        return OAuthSession(origin: origin, gateway: gateway, credentials: credentials)
    }
    func updateGateway(_ value: GatewayConfiguration) { gateway = value }
    func persist() throws { try Self.save(credentials, origin: origin) }
    private static func save(_ credentials: OAuthCredentials, origin: URL) throws {
        try CredentialStore.save(String(decoding: JSONEncoder().encode(credentials), as: UTF8.self), account: account(origin))
    }
    func invalidate() { invalidated = true; refresh?.cancel(); refresh = nil }
    func accessToken() async throws -> String {
        guard !invalidated else { throw CancellationError() }
        if credentials.expiresAt > Date().addingTimeInterval(60) { return credentials.accessToken }
        if let refresh {
            let result = try await refresh.value
            guard !invalidated else { throw CancellationError() }
            return result.accessToken
        }
        guard let refreshToken = credentials.refreshToken else { throw APIError(message: "Your sign-in expired. Reconnect with SSO in Workspace settings.") }
        let origin = origin, gateway = gateway, clientID = credentials.clientID
        let task = Task {
            let result = try await Self.exchange(origin: origin, gateway: gateway, clientID: clientID, fields: ["grant_type": "refresh_token", "refresh_token": refreshToken])
            return result
        }
        refresh = task
        defer { refresh = nil }
        let updated = try await task.value
        guard !invalidated else { throw CancellationError() }
        try Self.save(updated, origin: origin)
        credentials = updated
        return credentials.accessToken
    }
    static func exchange(origin: URL, gateway: GatewayConfiguration, clientID: String, fields: [String: String], configuration: URLSessionConfiguration = .ephemeral) async throws -> OAuthCredentials {
        var request = URLRequest(url: origin.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        try gateway.apply(to: &request, origin: origin)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.merging(["client_id": clientID]) { _, b in b }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "Could not exchange the SSO authorization. Check your connection settings and that your Outline OAuth client is public with PKCE enabled, then sign in again.")
        }
        struct Response: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double; let token_type: String }
        let token = try JSONDecoder().decode(Response.self, from: data)
        guard !token.access_token.isEmpty, token.token_type.lowercased() == "bearer", token.expires_in > 0 else { throw APIError(message: "Outline returned an invalid sign-in response.") }
        return OAuthCredentials(accessToken: token.access_token, refreshToken: token.refresh_token, expiresAt: Date().addingTimeInterval(token.expires_in), clientID: clientID)
    }
}
