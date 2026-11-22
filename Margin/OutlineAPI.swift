import Foundation
import Security
import OSLog

struct OutlineDocument: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var text: String?
    var url: String?
    var collectionId: String?
    var updatedAt: String?
    var revision: Int?
    var parentDocumentId: String?
    var publishedAt: String?
}
struct OutlineCollection: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}
struct OutlineTreeNode: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var url: String?
    var children: [OutlineTreeNode]
    var nested: [OutlineTreeNode]? { children.isEmpty ? nil : children }
    func document(collectionID: String) -> OutlineDocument {
        OutlineDocument(id: id, title: title, url: url, collectionId: collectionID)
    }
}
struct SearchHit: Decodable { let document: OutlineDocument }
struct Envelope<T: Decodable>: Decodable {
    let data: T
    let pagination: Pagination?
    struct Pagination: Decodable { let nextPath: String? }
}
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct GatewaySignInRequired: LocalizedError {
    let workspaceURL: URL
    var errorDescription: String? {
        "Your workspace requires sign-in. Open Connection and sign-in in Workspace settings to reconnect."
    }
}

struct OutlineAPI {
    private struct Rejection: Decodable { let message: String }
    let baseURL: URL
    let token: String
    var configuration: URLSessionConfiguration = .ephemeral
    var gateway = GatewayConfiguration()
    var oauth: OAuthSession?
    var browserSession = false
    var networkPolicy: NetworkPolicy?

    static func workspaceURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.contains("://") ? value : "https://" + value),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw APIError(message: "Enter your workspace’s HTTPS address, without a document path.")
        }
        return url
    }

    func request<T: Decodable>(_ method: String, body: [String: Any] = [:]) async throws -> Envelope<T> {
        try networkPolicy?.check()
        var request = URLRequest(url: baseURL.appendingPathComponent("api/" + method))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let bearer = try await oauth?.accessToken() ?? token
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        try gateway.apply(to: &request, origin: baseURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Never forward credentials through a workspace redirect.
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try networkPolicy?.check()
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(message: "No response from your workspace.") }
        guard (200..<300).contains(response.statusCode) else {
            if (300..<400).contains(response.statusCode),
               let location = response.value(forHTTPHeaderField: "Location"),
               let destination = URL(string: location, relativeTo: baseURL)?.absoluteURL,
               destination.scheme == "https",
               let host = destination.host?.lowercased(),
               host.hasSuffix(".cloudflareaccess.com"),
               destination.path.hasPrefix("/cdn-cgi/access/login") {
                // Present the workspace origin for sign-in, never a server-supplied
                // redirect URL containing state or the API authorization header.
                if gateway.usesServiceToken {
                    var message = "Cloudflare Access redirected the service token request to browser sign-in. Check that this workspace has a Service Auth policy for this token."
                    if let ray = response.value(forHTTPHeaderField: "cf-ray"),
                       ray.range(of: #"^[0-9a-fA-F]{16,32}(-[A-Za-z]{3})?$"#, options: .regularExpression) != nil {
                        message += " Cloudflare Ray ID: " + ray
                    }
                    throw APIError(message: message)
                }
                throw GatewaySignInRequired(workspaceURL: baseURL)
            }
            switch response.statusCode {
            case 401:
                if browserSession {
                    let log = Logger(subsystem: "us.cwill.margin", category: "SignIn")
                    // Only log recognized authentication messages. A gateway can return arbitrary content.
                    let message = try? JSONDecoder().decode(Rejection.self, from: data).message
                    let reason: String
                    switch message {
                    case "Authentication required", "Missing token": reason = "missing token"
                    case "Expired token": reason = "expired token"
                    case "Invalid token": reason = "invalid token"
                    case "Unable to decode token": reason = "malformed token"
                    case "Token has already been used": reason = "already used token"
                    default: reason = "unclassified"
                    }
                    log.notice("Browser sign-in HTTP 401: server reason=\(reason, privacy: .public)")
                    let sent = request.value(forHTTPHeaderField: "Cookie")?.components(separatedBy: "; ") ?? []
                    for name in ["CF_Authorization", "CF_Binding"] {
                        let saved = gateway.cookies.filter { $0.name == name }
                        let lifetime = saved.map { cookie in
                            cookie.expires.map { String(Int($0.timeIntervalSinceNow)) } ?? "session"
                        }.joined(separator: ",")
                        let attached = sent.contains { $0.hasPrefix(name + "=") }
                        log.notice("Browser sign-in HTTP 401: bearer present=\(!bearer.isEmpty), \(name, privacy: .public) attached=\(attached), saved=\(saved.count), seconds to expiry=\(lifetime, privacy: .public)")
                    }
                }
                throw APIError(message: oauth == nil && !browserSession ? "Your API key was not accepted. Check it in workspace settings." : "Your sign-in expired or was not accepted. Sign in to Outline again in Workspace settings.")
            case 403: throw APIError(message: "Your account does not have permission for this action.")
            case 409: throw APIError(message: "This document changed elsewhere. Your draft is safe; reopen the current document before trying again.")
            case 429: throw APIError(message: "Outline is receiving too many requests. Try again shortly.")
            default: throw APIError(message: "Outline returned HTTP \(response.statusCode). Please try again.")
            }
        }
        return try JSONDecoder().decode(Envelope<T>.self, from: data)
    }

    func list<T: Decodable>(_ method: String, body: [String: Any] = [:]) async throws -> [T] {
        var items: [T] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            var params = body
            params["limit"] = 100
            params["offset"] = offset
            let response: Envelope<[T]> = try await request(method, body: params)
            items += response.data
            if response.data.isEmpty || response.pagination?.nextPath == nil { break }
            offset += response.data.count
        }
        return items
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum CredentialStore {
    static let service = "us.cwill.duoutline"
    static func verifyAccess() throws {
        let account = "storage-check-" + UUID().uuidString
        defer { delete(account: account) }
        let value = UUID().uuidString
        try save(value, account: account)
        guard read(account: account) == value else { throw APIError(message: "Secure sign-in storage is unavailable. Please restart the app.") }
    }
    static func save(_ value: String, account: String = "workspace") throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw APIError(message: "Could not securely save your sign-in details.") }
        } else if status != errSecSuccess { throw APIError(message: "Could not securely save your sign-in details.") }
    }
    static func read(account: String = "workspace") -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

// Keep untouched blocks in Outline's structured document instead of replacing
// the whole document with a Markdown round-trip for every small text edit.
enum DocumentChange {
    static func body(original: OutlineDocument, title: String, text: String, revision: Int?, publish: Bool, collection: String?) throws -> [String: Any] {
        guard let revision else { throw APIError(message: "Reopen this document online before editing so its revision can be checked.") }
        var body: [String: Any] = ["id": original.id, "title": title, "lastRevision": revision]
        let old = original.text ?? ""
        if old != text {
            if old.isEmpty { body["text"] = text; body["editMode"] = "append" }
            else {
                let before = Array(old), after = Array(text)
                var start = 0
                while start < min(before.count, after.count) && before[start] == after[start] { start += 1 }
                var suffix = 0
                while suffix < min(before.count - start, after.count - start) && before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
                // Include context for insertions and disambiguate repeated text.
                if start == before.count - suffix {
                    if start > 0 { start -= 1 } else { suffix = max(0, suffix - 1) }
                }
                var needle = String(before[start..<(before.count - suffix)])
                while old.components(separatedBy: needle).count > 2 && (start > 0 || suffix > 0) {
                    if start > 0 { start -= 1 }
                    if suffix > 0 { suffix -= 1 }
                    needle = String(before[start..<(before.count - suffix)])
                }
                body["editMode"] = "patch"
                body["findText"] = needle
                body["text"] = String(after[start..<(after.count - suffix)])
            }
        }
        if publish { body["publish"] = true; if let collection { body["collectionId"] = collection } }
        return body
    }
}

// Remove only an exact leading title duplicate from the reading presentation.
// The stored document and editor input remain unchanged.
enum DocumentReading {
    static func body(_ text: String, title: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return text }
        let line = lines[first].trimmingCharacters(in: .whitespacesAndNewlines)
        var end = first
        let heading: String
        if line.hasPrefix("# ") {
            heading = String(line.dropFirst(2)).replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        } else if first + 1 < lines.count,
                  lines[first + 1].trimmingCharacters(in: .whitespaces).range(of: #"^=+$"#, options: .regularExpression) != nil {
            heading = line; end += 1
        } else { return text }
        guard heading == title.trimmingCharacters(in: .whitespacesAndNewlines) else { return text }
        lines.removeSubrange(0...end)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { lines.removeFirst() }
        return lines.joined(separator: "\n")
    }
}

enum OfflineMode: String, Codable, CaseIterable, Identifiable {
    case manual, opened, everything
    var id: String { rawValue }
    var title: String {
        switch self { case .manual: "Manual"; case .opened: "Pages I open"; case .everything: "Everything" }
    }
}
struct OutlineProfile: Codable {
    var name: String
    var avatarUrl: String?
}
struct OutlineIdentity: Decodable { var user: OutlineProfile }
struct LibrarySnapshot: Codable {
    var collections: [OutlineCollection]
    var documents: [OutlineDocument]
    var trees: [String: [OutlineTreeNode]]
    var draftIDs: Set<String>
}

// Shared by API value copies so pagination also observes the offline switch.
final class NetworkPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var offline = false
    func setOffline(_ value: Bool) { lock.lock(); defer { lock.unlock() }; offline = value }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if offline { throw APIError(message: "Work offline is enabled.") }
    }
}

struct PendingChange: Codable {
    var original: OutlineDocument?
    var document: OutlineDocument
    var publish: Bool

    func requestBody() throws -> [String: Any] {
        if let original {
            return try DocumentChange.body(original: original, title: document.title, text: document.text ?? "",
                                           revision: original.revision, publish: publish, collection: document.collectionId)
        }
        var body: [String: Any] = ["title": document.title, "text": document.text ?? "", "publish": publish]
        if let collection = document.collectionId { body["collectionId"] = collection }
        return body
    }
}

struct SyncQueue: Codable {
    var resolvedIDs: [String: String] = [:]
    var changes: [PendingChange] = []
    var downloads: [OutlineDocument] = []
    mutating func enqueue(_ change: PendingChange) {
        if let index = changes.firstIndex(where: { $0.document.id == change.document.id }) {
            changes[index].document = change.document
            changes[index].publish = changes[index].publish || change.publish
        } else { changes.append(change) }
    }
}
