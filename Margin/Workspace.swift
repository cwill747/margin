import SwiftUI

struct LocalDraft: Codable, Equatable {
    var title = ""
    var text = ""
    var collection: String?
}

@MainActor @Observable final class Workspace {
    var api: OutlineAPI?
    var collections: [OutlineCollection] = []
    var documents: [OutlineDocument] = []
    var trees: [String: [OutlineTreeNode]] = [:]
    var draftIDs: Set<String> = []
    var saved: [OutlineDocument] = []
    var error: String?
    var busy = false
    var demo = false
    var draft = LocalDraft()
    var expandedSections: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "expandedSidebarSections") ?? []) {
        didSet { UserDefaults.standard.set(Array(expandedSections), forKey: "expandedSidebarSections") }
    }
    var offlineMode = OfflineMode(rawValue: UserDefaults.standard.string(forKey: "offlineMode") ?? "") ?? .manual {
        didSet { UserDefaults.standard.set(offlineMode.rawValue, forKey: "offlineMode") }
    }
    var syncing = false
    var syncCompleted = 0
    var syncTotal = 0
    var syncError: String?
    var profile: OutlineProfile?
    var avatar: UIImage?
    private var libraryURL: URL { URL.applicationSupportDirectory.appendingPathComponent("library.json") }
    private var avatarURL: URL { URL.applicationSupportDirectory.appendingPathComponent("avatar.data") }
    private var profileURL: URL { URL.applicationSupportDirectory.appendingPathComponent("profile.json") }
    var name: String { demo ? "Sample workspace" : api?.baseURL.host ?? "Your workspace" }
    private var generation = UUID()
    private var cacheURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("saved-documents.json")
    }
    private var draftURL: URL { URL.applicationSupportDirectory.appendingPathComponent("draft.json") }

    init() {
        if let host = UserDefaults.standard.string(forKey: "workspace"),
           let url = try? OutlineAPI.workspaceURL(host) {
            let gateway = GatewayConfiguration.load(for: url)
            let oauth = OAuthSession.load(origin: url, gateway: gateway)
            if let token = CredentialStore.read() { api = OutlineAPI(baseURL: url, token: token, gateway: gateway, browserSession: UserDefaults.standard.bool(forKey: "browserSession")) }
            else if let oauth { api = OutlineAPI(baseURL: url, token: "", gateway: gateway, oauth: oauth) }
            if let data = try? Data(contentsOf: cacheURL) { saved = (try? JSONDecoder().decode([OutlineDocument].self, from: data)) ?? [] }
            if let data = try? Data(contentsOf: libraryURL), let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
                collections = snapshot.collections; documents = snapshot.documents; trees = snapshot.trees; draftIDs = snapshot.draftIDs
            }
            if let data = try? Data(contentsOf: profileURL) { profile = try? JSONDecoder().decode(OutlineProfile.self, from: data) }
            if let data = try? Data(contentsOf: avatarURL) { avatar = UIImage(data: data) }
            if let data = try? Data(contentsOf: draftURL) { draft = (try? JSONDecoder().decode(LocalDraft.self, from: data)) ?? LocalDraft() }
        }
    }
    func connect(host: String, token: String, gateway: GatewayConfiguration = .init(), browserSession: Bool = false) async throws {
        let url = try OutlineAPI.workspaceURL(host)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw APIError(message: "Enter an Outline API key from Settings → API & Apps.") }
        let client = OutlineAPI(baseURL: url, token: token, gateway: gateway, browserSession: browserSession)
        let collections: [OutlineCollection] = try await client.list("collections.list")
        try gateway.save(for: url)
        try CredentialStore.save(token)
        UserDefaults.standard.set(browserSession, forKey: "browserSession")
        UserDefaults.standard.set(url.absoluteString, forKey: "workspace")
        expandedSections = []
        generation = UUID()
        self.api = client
        self.collections = collections
        demo = false
        await refresh()
    }
    func connectSSO(host: String, clientID: String, gateway: GatewayConfiguration, browser: BrowserSignIn) async throws {
        let origin = try OutlineAPI.workspaceURL(host)
        _ = try gateway.validatedHeaders()
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw APIError(message: "Enter the public OAuth client ID registered in your Outline workspace.") }
        let current = generation
        let attempt = try OAuthAttempt()
        let callback = try await browser.authorize(url: attempt.authorizationURL(origin: origin, clientID: id))
        let code = try attempt.code(from: callback)
        let credentials = try await OAuthSession.exchange(origin: origin, gateway: gateway, clientID: id, fields: ["grant_type": "authorization_code", "code": code, "redirect_uri": OAuthAttempt.callback, "code_verifier": attempt.verifier])
        let oauth = OAuthSession(origin: origin, gateway: gateway, credentials: credentials)
        let client = OutlineAPI(baseURL: origin, token: "", gateway: gateway, oauth: oauth)
        let collections: [OutlineCollection] = try await client.list("collections.list")
        guard generation == current else { throw CancellationError() }
        try await oauth.persist()
        try gateway.save(for: origin)
        // Remove the legacy API key only after successful SSO verification.
        CredentialStore.delete(account: "workspace")
        UserDefaults.standard.set(origin.absoluteString, forKey: "workspace")
        expandedSections = []
        UserDefaults.standard.set(id, forKey: "oauthClientID")
        generation = UUID(); api = client; self.collections = collections; demo = false
        await refresh()
    }
    func updateGateway(_ gateway: GatewayConfiguration) async throws {
        guard var client = api else { return }
        try gateway.save(for: client.baseURL)
        client.gateway = gateway
        await client.oauth?.updateGateway(gateway)
        api = client
    }
    func refresh() async {
        guard let api else { return }
        let current = generation
        busy = true
        defer { if generation == current { busy = false } }
        do {
            async let collections: [OutlineCollection] = api.list("collections.list")
            async let documents: [OutlineDocument] = api.list("documents.list", body: ["sort": "updatedAt", "direction": "DESC"])
            async let drafts: [OutlineDocument] = api.list("documents.drafts")
            let result = try await (collections, documents, drafts)
            guard generation == current else { return }
            var trees: [String: [OutlineTreeNode]] = [:]
            for collection in result.0 {
                let tree: Envelope<[OutlineTreeNode]> = try await api.request("collections.documents", body: ["id": collection.id])
                trees[collection.id] = tree.data
            }
            guard generation == current else { return }
            self.trees = trees
            self.draftIDs = Set(result.2.map(\.id))
            self.collections = result.0
            let publishedIDs = Set(result.1.map(\.id))
            self.documents = result.2.filter { !publishedIDs.contains($0.id) } + result.1
            try writePrivate(JSONEncoder().encode(LibrarySnapshot(collections: self.collections, documents: self.documents, trees: trees, draftIDs: self.draftIDs)), to: libraryURL)
            await refreshProfile()
            await syncOffline()

        } catch { if generation == current { self.error = error.localizedDescription } }
    }
    func search(_ query: String) async throws -> [OutlineDocument] {
        guard let api else { return documents.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.text ?? "").localizedCaseInsensitiveContains(query) } }
        let hits: [SearchHit] = try await api.list("documents.search", body: ["query": query])
        return hits.map(\.document)
    }
    func load(_ document: OutlineDocument) async throws -> OutlineDocument {
        guard let api else { return document }
        let current = generation
        let response: Envelope<OutlineDocument> = try await api.request("documents.info", body: ["id": document.id])
        guard generation == current else { throw CancellationError() }
        if offlineMode != .manual || saved.contains(where: { $0.id == document.id }) {
            do { try saveOffline(response.data) } catch { syncError = error.localizedDescription }
        }
        return response.data
    }
    func create(title: String, text: String, collection: String?, publish: Bool = false) async throws -> OutlineDocument {
        let current = generation
        let document: OutlineDocument
        if let api {
            var body: [String: Any] = ["title": title, "text": text, "publish": publish]
            if let collection { body["collectionId"] = collection }
            let response: Envelope<OutlineDocument> = try await api.request("documents.create", body: body)
            document = response.data
        } else {
            document = OutlineDocument(id: UUID().uuidString, title: title, text: text, collectionId: collection)
        }
        guard generation == current else { throw CancellationError() }
        documents.insert(document, at: 0)
        if !publish { draftIDs.insert(document.id) }
        if api != nil { await refresh() }
        return document
    }
    func update(_ original: OutlineDocument, title: String, text: String, revision: Int?, publish: Bool, collection: String?) async throws -> OutlineDocument {
        let current = generation
        var updated = original
        if let api {
            let body = try DocumentChange.body(original: original, title: title, text: text, revision: revision, publish: publish, collection: collection)
            let result: Envelope<OutlineDocument> = try await api.request("documents.update", body: body)
            updated = result.data
        } else {
            updated.title = title; updated.text = text; updated.revision = (revision ?? 0) + 1
            if publish { updated.publishedAt = ISO8601DateFormatter().string(from: Date()); updated.collectionId = collection }
        }
        guard generation == current else { throw CancellationError() }
        if let index = documents.firstIndex(where: { $0.id == updated.id }) { documents[index] = updated }
        if saved.contains(where: { $0.id == updated.id }) { try? saveOffline(updated) }
        if api != nil { await refresh() }
        return updated
    }
    func syncPage(_ document: OutlineDocument) async throws {
        let fresh = try await load(document)
        guard fresh.text != nil else { throw APIError(message: "Document content is unavailable.") }
        try saveOffline(fresh)
    }
    func syncOffline() async {
        guard !syncing, let api else { return }
        let current = generation
        let targets = offlineMode == .everything ? documents : saved
        guard !targets.isEmpty else { return }
        syncing = true; syncCompleted = 0; syncTotal = targets.count; syncError = nil
        defer { if current == generation { syncing = false } }
        var failures = 0
        for document in targets {
            guard current == generation, !Task.isCancelled else { return }
            do {
                let response: Envelope<OutlineDocument> = try await api.request("documents.info", body: ["id": document.id])
                guard current == generation else { return }
                guard response.data.text != nil else { throw APIError(message: "Missing page content") }
                try saveOffline(response.data)
            } catch is CancellationError { return
            } catch {
                if let networkError = error as? URLError {
                    syncError = "Sync paused: " + networkError.localizedDescription + " Saved copies remain available."
                    return
                }
                failures += 1
                if let responseError = error as? APIError, responseError.message.contains("permission") {
                    try? removeOffline(document)
                }
            }
            syncCompleted += 1
        }
        if failures > 0 { syncError = "Could not sync \(failures) of \(syncTotal) pages. Previous copies are still available; try again when connected." }
    }
    private func writePrivate(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var url = url; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try url.setResourceValues(flags)
    }
    private func refreshProfile() async {
        guard let api else { return }
        let current = generation
        do {
            let result: Envelope<OutlineIdentity> = try await api.request("auth.info")
            guard current == generation else { return }
            let oldURL = profile?.avatarUrl
            profile = result.data.user
            try writePrivate(JSONEncoder().encode(result.data.user), to: profileURL)
            if oldURL != profile?.avatarUrl { avatar = nil; try? FileManager.default.removeItem(at: avatarURL) }
            guard let path = profile?.avatarUrl, let url = URL(string: path, relativeTo: api.baseURL)?.absoluteURL, url.scheme == "https" else { return }
            let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            var destination = url
            for _ in 0..<5 {
                guard destination.scheme == "https" else { return }
                var request = URLRequest(url: destination); request.timeoutInterval = 20
                // Signed storage redirects get a fresh request without workspace credentials.
                if GatewayConfiguration.sameOrigin(destination, api.baseURL) {
                    try api.gateway.apply(to: &request, origin: api.baseURL)
                    let token = try await api.oauth?.accessToken() ?? api.token
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await session.data(for: request)
                guard current == generation, let response = response as? HTTPURLResponse else { return }
                if (300..<400).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"),
                   let next = URL(string: location, relativeTo: destination)?.absoluteURL {
                    destination = next; continue
                }
                guard response.statusCode == 200, let image = UIImage(data: data) else { return }
                avatar = image; try writePrivate(data, to: avatarURL)
                return
            }
        } catch { /* Profile failures must not prevent reading or offline sync. */ }
    }
    func saveOffline(_ document: OutlineDocument) throws {
        var updated = saved.filter { $0.id != document.id }
        updated.insert(document, at: 0)
        try persist(updated)
        saved = updated
    }
    func removeOffline(_ document: OutlineDocument) throws {
        let updated = saved.filter { $0.id != document.id }
        try persist(updated)
        saved = updated
    }
    private func persist(_ documents: [OutlineDocument]) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(documents).write(to: cacheURL, options: [.atomic, .completeFileProtection])
        var url = cacheURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func signOut() async {
        generation = UUID()
        await api?.oauth?.invalidate()
        api = nil; demo = false; collections = []; documents = []; trees = [:]; draftIDs = []; saved = []; error = nil; busy = false
        CredentialStore.delete()
        UserDefaults.standard.removeObject(forKey: "workspace")
        expandedSections = []; offlineMode = .manual; syncing = false; syncError = nil; profile = nil; avatar = nil
        for url in [libraryURL, avatarURL, profileURL] { try? FileManager.default.removeItem(at: url) }
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.removeItem(at: draftURL)
        draft = LocalDraft()
    }
    func storeDraft(_ value: LocalDraft) throws {
        draft = value
        guard !demo else { return }
        try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: draftURL, options: [.atomic, .completeFileProtection])
        var url = draftURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func showDemo() {
        demo = true
        collections = [.init(id: "getting-started", name: "Getting started"), .init(id: "ideas", name: "Ideas & research")]
        documents = [
            .init(id: "welcome", title: "A little more room to think", text: "# Welcome to Margin\n\nYour knowledge, comfortably within reach. Browse your collections, find an answer, and keep a reference beside what you’re reading.\n\n## Make space for two\n\nOpen a document, then choose **Keep beside**. Your reference stays in place as you browse another page. On a smaller screen, switch between the two without losing your place.\n\n## Take it with you\n\nSave a document for reading when you’re away from a connection. Saved copies stay on this device.\n\n> This is a sample workspace. Connect your Outline workspace to see your own documents.", collectionId: "getting-started"),
            .init(id: "field-notes", title: "Field notes", text: "Good ideas rarely arrive at a desk.\n\n## A small ritual\n\n- Keep a question close.\n- Collect the surprising details.\n- Leave room for a second thought.\n\n## Connect the dots\n\nKeep this page beside another document to compare your notes.", collectionId: "ideas"),
            .init(id: "reading", title: "A quieter reading space", text: "A comfortable measure. Type that follows your preferred size. A reference exactly where you need it.\n\n## Built around your screen\n\nUse the sidebar on iPad mini to move through your workspace. On iPhone, navigation stays one tap away.\n\n**Tip:** Use the share button to send a document link, or open the original in Outline for rich editing.", collectionId: "getting-started")
        ]
        trees = [
            "getting-started": [.init(id: "welcome", title: documents[0].title, children: [.init(id: "reading", title: documents[2].title, children: [])])],
            "ideas": [.init(id: "field-notes", title: documents[1].title, children: [])]
        ]
    }
}
