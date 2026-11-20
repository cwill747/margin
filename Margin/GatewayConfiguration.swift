import Foundation

struct GatewayHeader: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var value = ""
}

struct GatewayCookie: Codable, Equatable {
    let name: String
    let value: String
    let host: String
    let expires: Date?
}

struct GatewayConfiguration: Codable, Equatable {
    var headers: [GatewayHeader] = []
    var cookies: [GatewayCookie] = []

    func validatedHeaders() throws -> [String: String] {
        var result: [String: String] = [:]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
        let reserved: Set<String> = ["authorization", "cookie", "host", "content-type", "content-length", "connection", "transfer-encoding", "proxy-authorization", "origin", "referer"]
        for header in headers where !header.name.isEmpty || !header.value.isEmpty {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
                  !reserved.contains(name.lowercased()),
                  !header.value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !result.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw APIError(message: "Use unique HTTP header names and single-line values. Authorization, Cookie, and transport headers are managed by Margin.")
            }
            result[name] = header.value
        }
        return result
    }

    func apply(to request: inout URLRequest, origin: URL) throws {
        guard let url = request.url, Self.sameOrigin(url, origin) else {
            throw APIError(message: "Gateway credentials may only be sent to your workspace.")
        }
        for (name, value) in try validatedHeaders() { request.setValue(value, forHTTPHeaderField: name) }
        let cookie = cookies.filter {
            $0.host == origin.host?.lowercased() && ($0.expires == nil || $0.expires! > Date()) &&
            ["CF_Authorization", "CF_Binding"].contains($0.name) &&
            !$0.value.contains(";") && !$0.value.contains("\r") && !$0.value.contains("\n")
        }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
    }

    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme == "https" && b.scheme == "https" && a.host?.lowercased() == b.host?.lowercased() && (a.port ?? 443) == (b.port ?? 443)
    }
    static func account(_ url: URL) -> String { "gateway:\(url.host!.lowercased()):\(url.port ?? 443)" }
    func save(for url: URL) throws {
        _ = try validatedHeaders()
        try CredentialStore.save(String(decoding: JSONEncoder().encode(self), as: UTF8.self), account: Self.account(url))
    }
    static func load(for url: URL) -> Self {
        guard let text = CredentialStore.read(account: account(url)), let value = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)) else { return .init() }
        return value
    }
}


enum OutlineBrowserSession {
    static func token(from cookies: [HTTPCookie], origin: URL, now: Date = Date()) throws -> String {
        let candidates = cookies.filter {
            $0.name == "accessToken" && $0.isSecure && $0.path == "/" &&
            $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == origin.host?.lowercased() &&
            ($0.expiresDate == nil || $0.expiresDate! > now) && !$0.value.isEmpty
        }
        guard candidates.count == 1, let token = candidates.first?.value else {
            throw APIError(message: "Finish signing in to Outline first, then tap Connect. You need to reach your signed-in Outline workspace.")
        }
        return token
    }
}
