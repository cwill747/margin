import SwiftUI

struct LocalDraft: Codable, Equatable {
    var title = ""
    var text = ""
    var collection: String?
}

@MainActor @Observable final class Workspace {
    private let networkPolicy = NetworkPolicy()
    private(set) var api: OutlineAPI?
    var workOffline = UserDefaults.standard.bool(forKey: "workOffline") {
        didSet {
            networkPolicy.setOffline(workOffline)
            UserDefaults.standard.set(workOffline, forKey: "workOffline")
            if !workOffline { Task { await refresh() } }
        }
    }
    private(set) var queue = SyncQueue()
    private var flushing = false
    var pendingCount: Int { queue.changes.count + queue.downloads.count }
    private var queueURL: URL { URL.applicationSupportDirectory.appendingPathComponent("sync-queue.json") }

    var collections: [OutlineCollection] = []
    var documents: [OutlineDocument] = []
    var trees: [String: [OutlineTreeNode]] = [:]
    private var libraryVersion = 0
    private var refreshPending = false
    private var reconciledAt: Date?
    private var publishedWatermark: String?
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
    private(set) var readerSessionID = UUID()
    private var generation = UUID()
    private var cacheURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("saved-documents.json")
    }
    private var draftURL: URL { URL.applicationSupportDirectory.appendingPathComponent("draft.json") }

    init() {
        networkPolicy.setOffline(workOffline)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            workOffline = false
            if ProcessInfo.processInfo.environment["MARGIN_TEST_SCREEN"] != "connect" {
                showDemo()
                expandedSections = ["getting-started", "ideas"]
                if ProcessInfo.processInfo.environment["MARGIN_TEST_SCREEN"] != "linked-library" {
                    documents[0].text = "## A useful heading\n\nRead a [reference](https://example.com).\n\n> A readable quotation.\n\n- [x] Completed item\n- [ ] Next item\n\n```swift\nlet answer = 42\n```\n\n| Topic | Notes |\n| --- | --- |\n| Access | Everyone |"
                }
            }
            return
        }
        #endif
        if let host = UserDefaults.standard.string(forKey: "workspace"),
           let url = try? OutlineAPI.workspaceURL(host) {
            let gateway = GatewayConfiguration.load(for: url)
            let oauth = OAuthSession.load(origin: url, gateway: gateway)
            if let token = CredentialStore.read() { api = OutlineAPI(baseURL: url, token: token, gateway: gateway, browserSession: UserDefaults.standard.bool(forKey: "browserSession"), networkPolicy: networkPolicy) }
            else if let oauth { api = OutlineAPI(baseURL: url, token: "", gateway: gateway, oauth: oauth, networkPolicy: networkPolicy) }
            if let data = try? Data(contentsOf: cacheURL) { saved = (try? JSONDecoder().decode([OutlineDocument].self, from: data)) ?? [] }
            if let data = try? Data(contentsOf: libraryURL), let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
                collections = snapshot.collections; documents = snapshot.documents; trees = snapshot.trees; draftIDs = snapshot.draftIDs
                reconciledAt = snapshot.reconciledAt; publishedWatermark = snapshot.publishedWatermark
            }
            if let data = try? Data(contentsOf: profileURL) { profile = try? JSONDecoder().decode(OutlineProfile.self, from: data) }
            if let data = try? Data(contentsOf: avatarURL) { avatar = UIImage(data: data) }
            if let data = try? Data(contentsOf: queueURL) {
                do { queue = try JSONDecoder().decode(SyncQueue.self, from: data); overlayPending() }
                catch { self.error = "Could not read queued changes: " + error.localizedDescription }
            }
            if let data = try? Data(contentsOf: draftURL) { draft = (try? JSONDecoder().decode(LocalDraft.self, from: data)) ?? LocalDraft() }
        }
    }
    func connect(host: String, token: String, gateway: GatewayConfiguration = .init(), browserSession: Bool = false) async throws {
        let url = try OutlineAPI.workspaceURL(host)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw APIError(message: "Enter an Outline API key from Settings → API & Apps.") }
        var client = OutlineAPI(baseURL: url, token: token, gateway: gateway, browserSession: browserSession)
        let collections: [OutlineCollection] = try await client.list("collections.list")
        try gateway.save(for: url)
        try CredentialStore.save(token)
        UserDefaults.standard.set(browserSession, forKey: "browserSession")
        UserDefaults.standard.set(url.absoluteString, forKey: "workspace")
        expandedSections = []
        generation = UUID()
        client.networkPolicy = networkPolicy
        self.api = client
        readerSessionID = UUID()
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
        var client = OutlineAPI(baseURL: origin, token: "", gateway: gateway, oauth: oauth)
        let collections: [OutlineCollection] = try await client.list("collections.list")
        guard generation == current else { throw CancellationError() }
        try await oauth.persist()
        try gateway.save(for: origin)
        // Remove the legacy API key only after successful SSO verification.
        CredentialStore.delete(account: "workspace")
        UserDefaults.standard.set(origin.absoluteString, forKey: "workspace")
        expandedSections = []
        UserDefaults.standard.set(id, forKey: "oauthClientID")
        client.networkPolicy = networkPolicy
        readerSessionID = UUID()
        generation = UUID(); api = client; self.collections = collections; demo = false
        await refresh()
    }
    func updateGateway(_ gateway: GatewayConfiguration) async throws {
        guard var client = api else { return }
        try gateway.save(for: client.baseURL)
        client.gateway = gateway
        await client.oauth?.updateGateway(gateway)
        api = client
        readerSessionID = UUID()
    }
    func refresh() async {
        guard !workOffline, !busy, let api else { return }
        let current = generation
        busy = true; error = nil; syncError = nil
        defer {
            if generation == current {
                busy = false
                if refreshPending {
                    refreshPending = false
                    Task { await refresh() }
                }
            }
        }
        do {
            try await flushQueue()
            guard !workOffline, generation == current else { return }
            let version = libraryVersion
            let full = reconciledAt.map { Date().timeIntervalSince($0) >= 86400 } ?? true
            let watermark = full ? nil : publishedWatermark
            async let collections: [OutlineCollection] = api.list("collections.list")
            async let published: [OutlineDocument] = api.list("documents.list", body: ["sort": "updatedAt", "direction": "DESC"]) { page in
                guard let watermark, let oldest = page.last?.updatedAt else { return false }
                return oldest < watermark
            }
            async let drafts: [OutlineDocument] = api.list("documents.drafts")
            let result = try await (collections, published, drafts)
            guard generation == current, !workOffline else { return }
            let collectionIDs = Set(result.0.map(\.id))
            let previous = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let publishedIDs = Set(result.1.map(\.id))
            let newDraftIDs = Set(result.2.map(\.id))
            var changedCollections = Set<String>()
            for doc in result.1 + result.2 {
                let old = previous[doc.id]
                if old?.title != doc.title || old?.parentDocumentId != doc.parentDocumentId ||
                    old?.collectionId != doc.collectionId || draftIDs.contains(doc.id) != newDraftIDs.contains(doc.id) {
                    if let id = old?.collectionId { changedCollections.insert(id) }
                    if let id = doc.collectionId { changedCollections.insert(id) }
                }
            }
            var nextTrees = trees.filter { collectionIDs.contains($0.key) }
            for collection in result.0 where full || nextTrees[collection.id] == nil || changedCollections.contains(collection.id) {
                let tree: Envelope<[OutlineTreeNode]> = try await api.request("collections.documents", body: ["id": collection.id])
                nextTrees[collection.id] = tree.data
            }
            guard generation == current, !workOffline else { return }
            guard libraryVersion == version else { refreshPending = true; return }
            let retained = watermark == nil ? [] : documents.filter {
                !draftIDs.contains($0.id) && !newDraftIDs.contains($0.id) && !publishedIDs.contains($0.id) &&
                    ($0.collectionId.map(collectionIDs.contains) ?? true)
            }
            documents = result.2.filter { !publishedIDs.contains($0.id) } + result.1 + retained
            trees = nextTrees; draftIDs = newDraftIDs; self.collections = result.0
            publishedWatermark = result.1.first?.updatedAt
            if full { reconciledAt = Date() }
            try persistLibrary()
            if full || profile == nil { await refreshProfile() }
            await syncOffline()

        } catch { if generation == current, !workOffline { self.error = error.localizedDescription; syncError = error.localizedDescription } }
    }
    private func persistLibrary() throws {
        let snapshot = LibrarySnapshot(collections: collections, documents: documents, trees: trees,
                                      draftIDs: draftIDs, reconciledAt: reconciledAt, publishedWatermark: publishedWatermark)
        try writePrivate(JSONEncoder().encode(snapshot), to: libraryURL)
    }

    private func recordWrite(_ document: OutlineDocument, previous: OutlineDocument?) {
        libraryVersion += 1
        documents.removeAll { $0.id == document.id }
        documents.insert(document, at: 0)
        if document.publishedAt == nil { draftIDs.insert(document.id) } else { draftIDs.remove(document.id) }
        if document.publishedAt != nil && (previous?.publishedAt == nil || previous?.title != document.title ||
            previous?.parentDocumentId != document.parentDocumentId || previous?.collectionId != document.collectionId) {
            if let id = document.collectionId { trees.removeValue(forKey: id) }
            if let id = previous?.collectionId { trees.removeValue(forKey: id) }
            if !flushing {
                if busy { refreshPending = true } else { Task { await refresh() } }
            }
        }
        if offlineMode == .everything && document.text != nil {
            do { try saveOffline(document) } catch { syncError = error.localizedDescription }
        }
        do { try persistLibrary() } catch { syncError = error.localizedDescription }
    }
    func search(_ query: String) async throws -> [OutlineDocument] {
        guard !workOffline, let api else { return documents.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.text ?? "").localizedCaseInsensitiveContains(query) } }
        let hits: [SearchHit] = try await api.list("documents.search", body: ["query": query])
        return hits.map(\.document)
    }
    func load(_ document: OutlineDocument) async throws -> OutlineDocument {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            switch ProcessInfo.processInfo.environment["MARGIN_TEST_SCREEN"] {
            case "error": throw APIError(message: "This page could not be loaded. Try again.")
            case "loading": try await Task.sleep(for: .seconds(30))
            default: break
            }
        }
        #endif
        if let id = queue.resolvedIDs[document.id],
           let resolved = documents.first(where: { $0.id == id }) ?? saved.first(where: { $0.id == id }) {
            return try await load(resolved)
        }
        if let pending = queue.changes.first(where: { $0.document.id == document.id }) { return pending.document }
        if workOffline {
            guard let cached = saved.first(where: { $0.id == document.id }) ?? documents.first(where: { $0.id == document.id && $0.text != nil }) else {
                throw APIError(message: "This page is not available offline. Queue its download or turn off Work offline.")
            }
            return cached
        }
        guard let api else { return document }
        let current = generation
        let response: Envelope<OutlineDocument> = try await api.request("documents.info", body: ["id": document.id])
        guard generation == current, !workOffline else { throw CancellationError() }
        if offlineMode != .manual || saved.contains(where: { $0.id == document.id }) {
            do { try saveOffline(response.data) } catch { syncError = error.localizedDescription }
        }
        return response.data
    }
    func create(title: String, text: String, collection: String?, publish: Bool = false) async throws -> OutlineDocument {
        if workOffline && api != nil {
            let document = OutlineDocument(id: "local-" + UUID().uuidString, title: title, text: text, collectionId: collection,
                                           publishedAt: publish ? ISO8601DateFormatter().string(from: Date()) : nil)
            try enqueue(PendingChange(original: nil, document: document, publish: publish))
            return document
        }
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
        if api != nil { recordWrite(document, previous: nil) }
        else { documents.insert(document, at: 0); if !publish { draftIDs.insert(document.id) } }
        return document
    }
    func update(_ original: OutlineDocument, title: String, text: String, revision: Int?, publish: Bool, collection: String?) async throws -> OutlineDocument {
        guard !flushing else { throw APIError(message: "Queued changes are syncing. Try saving again when sync finishes.") }
        if api != nil && (workOffline || queue.changes.contains(where: { $0.document.id == original.id })) {
            var updated = original
            updated.title = title; updated.text = text
            if publish { updated.publishedAt = ISO8601DateFormatter().string(from: Date()); updated.collectionId = collection }
            var base = original; base.revision = revision
            if !queue.changes.contains(where: { $0.document.id == original.id }) {
                _ = try DocumentChange.body(original: base, title: title, text: text, revision: revision, publish: publish, collection: collection)
            }
            try enqueue(PendingChange(original: base, document: updated, publish: publish))
            if !workOffline { Task { await refresh() } }
            return updated
        }
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
        if api != nil { recordWrite(updated, previous: original) }
        else if let index = documents.firstIndex(where: { $0.id == updated.id }) { documents[index] = updated }
        if offlineMode != .everything && saved.contains(where: { $0.id == updated.id }) { try? saveOffline(updated) }
        if publish { draftIDs.remove(updated.id) }
        return updated
    }
    func deletePage(_ document: OutlineDocument) async throws -> Set<String> {
        var removed: Set<String> = [document.id]
        func prune(_ nodes: [OutlineTreeNode], deletingParent: Bool = false) -> [OutlineTreeNode] {
            nodes.compactMap { node in
                let deleting = deletingParent || node.id == document.id
                var updated = node
                updated.children = prune(node.children, deletingParent: deleting)
                if deleting { removed.insert(node.id); return nil }
                return updated
            }
        }
        if let api {
            guard !workOffline else { throw APIError(message: "Connect to your workspace to delete this page.") }
            if pendingCount > 0 {
                for nodes in trees.values { _ = prune(nodes) }
            }
            guard !flushing, !queue.changes.contains(where: { removed.contains($0.document.id) }),
                  !queue.downloads.contains(where: { removed.contains($0.id) }) else {
                throw APIError(message: "Finish syncing pending changes before deleting this page.")
            }
            let current = generation
            try await api.deletePage(id: document.id)
            guard current == generation else { throw CancellationError() }
        }
        trees = trees.mapValues { prune($0) }
        libraryVersion += 1
        documents.removeAll { removed.contains($0.id) }
        saved.removeAll { removed.contains($0.id) }
        draftIDs.subtract(removed)
        if api != nil {
            reconciledAt = nil
            do {
                try persistLibrary()
                try persist(saved)
            } catch { syncError = error.localizedDescription }
            if busy { refreshPending = true } else { Task { await refresh() } }
        }
        return removed
    }

    func syncPage(_ document: OutlineDocument) async throws {
        if workOffline {
            var next = queue
            if !next.downloads.contains(where: { $0.id == document.id }) { next.downloads.append(document) }
            try storeQueue(next)
            return
        }
        let fresh = try await load(document)
        guard fresh.text != nil else { throw APIError(message: "Document content is unavailable.") }
        try saveOffline(fresh)
    }
    func syncOffline() async {
        guard !workOffline, !syncing, queue.changes.isEmpty, let api else { return }
        let current = generation
        let cached = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let targets = (offlineMode == .everything ? documents : saved).filter { target in
            guard let remote = listed[target.id] else { return true }
            return cached[target.id]?.hasCurrentContent(for: remote) != true
        }
        guard !targets.isEmpty else { return }
        syncing = true; syncCompleted = 0; syncTotal = targets.count; syncError = nil
        defer { if current == generation { syncing = false } }
        var failures = 0
        for document in targets {
            guard !workOffline, current == generation, !Task.isCancelled else { return }
            do {
                let response: Envelope<OutlineDocument> = try await api.request("documents.info", body: ["id": document.id])
                guard current == generation, !workOffline, queue.changes.isEmpty else { return }
                guard response.data.text != nil else { throw APIError(message: "Missing page content") }
                if saved.first(where: { $0.id == document.id }) == cached[document.id] {
                    try saveOffline(response.data)
                }
            } catch is CancellationError { return
            } catch {
                guard !workOffline else { return }
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
    private func storeQueue(_ next: SyncQueue) throws {
        try writePrivate(JSONEncoder().encode(next), to: queueURL)
        queue = next
    }
    private func enqueue(_ change: PendingChange) throws {
        var next = queue; next.enqueue(change)
        try storeQueue(next)
        overlayPending()
    }
    private func overlayPending() {
        for change in queue.changes {
            let document = change.document
            documents.removeAll { $0.id == document.id }; documents.insert(document, at: 0)
            saved.removeAll { $0.id == document.id }; saved.insert(document, at: 0)
            if document.publishedAt == nil { draftIDs.insert(document.id) } else { draftIDs.remove(document.id) }
        }
    }
    private func flushQueue() async throws {
        guard !workOffline, let api else { return }
        flushing = true
        defer { flushing = false }
        let current = generation
        while !workOffline, let change = queue.changes.first {
            let response: Envelope<OutlineDocument> = try await api.request(change.original == nil ? "documents.create" : "documents.update", body: change.requestBody())
            guard current == generation else { return }
            // Persist the server copy before acknowledging the queued write.
            try saveOffline(response.data)
            var next = queue; next.changes.removeFirst()
            if response.data.id != change.document.id { next.resolvedIDs[change.document.id] = response.data.id }
            next.downloads = next.downloads.map { $0.id == change.document.id ? response.data : $0 }
            try storeQueue(next)
            documents.removeAll { $0.id == change.document.id }
            draftIDs.remove(change.document.id)
            recordWrite(response.data, previous: change.original)
            if response.data.id != change.document.id {
                saved.removeAll { $0.id == change.document.id }
                try persist(saved)
            }
        }
        while !workOffline, let document = queue.downloads.first {
            let response: Envelope<OutlineDocument> = try await api.request("documents.info", body: ["id": document.id])
            guard current == generation else { return }
            try saveOffline(response.data)
            var next = queue; next.downloads.removeFirst(); try storeQueue(next)
        }
    }
    private func writePrivate(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var url = url; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try url.setResourceValues(flags)
    }
    private func refreshProfile() async {
        guard !workOffline, let api else { return }
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
                guard !workOffline, destination.scheme == "https" else { return }
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
        guard !queue.changes.contains(where: { $0.document.id == document.id }) else { throw APIError(message: "Sync pending changes before removing this copy.") }
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
        guard pendingCount == 0 else { error = "Sync queued changes before disconnecting."; return }
        generation = UUID()
        await api?.oauth?.invalidate()
        refreshPending = false; reconciledAt = nil; publishedWatermark = nil
        api = nil; demo = false; collections = []; documents = []; trees = [:]; draftIDs = []; saved = []; error = nil; busy = false
        CredentialStore.delete()
        UserDefaults.standard.removeObject(forKey: "workspace")
        expandedSections = []; offlineMode = .manual; syncing = false; syncError = nil; profile = nil; avatar = nil
        workOffline = false; queue = SyncQueue()
        for url in [libraryURL, avatarURL, profileURL, queueURL] { try? FileManager.default.removeItem(at: url) }
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
            .init(id: "welcome", title: "A little more room to think", text: "# Welcome to Margin\n\nYour knowledge, comfortably within reach. Browse your collections, find an answer, and keep a reference beside what you’re reading.\n\n[Read the closing note](https://margin.example/doc/closing-note)\n\n## Make space for two\n\nOpen a document, then choose **Keep beside**. Your reference stays in place as you browse another page. On a smaller screen, switch between the two without losing your place.\n\n## Take it with you\n\nSave a document for reading when you’re away from a connection. Saved copies stay on this device.\n\n> This is a sample workspace. Connect your Outline workspace to see your own documents.", collectionId: "getting-started"),
            .init(id: "field-notes", title: "Field notes", text: "Good ideas rarely arrive at a desk.\n\n## A small ritual\n\n- Keep a question close.\n- Collect the surprising details.\n- Leave room for a second thought.\n\n## Connect the dots\n\nKeep this page beside another document to compare your notes.", collectionId: "ideas"),
            .init(id: "reading", title: "A quieter reading space", text: "A comfortable measure. Type that follows your preferred size. A reference exactly where you need it.\n\n## Built around your screen\n\nUse the sidebar on iPad mini to move through your workspace. On iPhone, navigation stays one tap away.\n\n**Tip:** Use the share button to send a document link, or open the original in Outline for rich editing.", collectionId: "getting-started")
        ]
        trees = [
            "getting-started": [.init(id: "welcome", title: documents[0].title, children: [.init(id: "reading", title: documents[2].title, children: [])])],
            "ideas": [.init(id: "field-notes", title: documents[1].title, children: [])]
        ]
        func journalPage(_ id: String, _ title: String, _ text: String, parent: String,
                         children: [OutlineTreeNode] = []) -> OutlineTreeNode {
            documents.append(.init(id: id, title: title, text: text, collectionId: "ideas", parentDocumentId: parent))
            return .init(id: id, title: title, children: children)
        }

        var entries: [OutlineTreeNode] = []
        for week in 1...30 {
            let id = "week-\(week)"
            var sessions: [OutlineTreeNode] = []
            if week <= 3 {
                for setting in ["Library", "Café", "Train"] {
                    let sessionID = "\(id)-\(setting.lowercased())"
                    let notesID = "\(sessionID)-notes"
                    let quote = journalPage("\(notesID)-quote", "Reader quote",
                                            "“I wanted to keep my place while checking the reference.”", parent: notesID)
                    let notes = journalPage(notesID, "Interview notes",
                                            "The reader kept a second page open during the session.", parent: sessionID, children: [quote])
                    let followUp = journalPage("\(sessionID)-follow-up", "Follow-up questions",
                                               "How did you find your place when you returned?", parent: sessionID)
                    sessions.append(journalPage(sessionID, "\(setting) session", "Reading study at the \(setting.lowercased()).",
                                                parent: id, children: [notes, followUp]))
                }
            }
            entries.append(journalPage(id, "Week \(week) observations", "## Research journal\n\nNotes from week \(week) of the reading study.",
                                       parent: "field-notes", children: sessions))
        }
        let closing = OutlineDocument(id: "closing-note", title: "Closing note",
                                      text: "[Return to the welcome page](https://margin.example/doc/welcome)", collectionId: "ideas",
                                      parentDocumentId: "field-notes")
        documents.append(closing)
        entries.append(.init(id: closing.id, title: closing.title, children: []))
        trees["ideas"]?[0].children = entries
    }
}
