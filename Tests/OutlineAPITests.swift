import XCTest
@testable import MarginCore

final class OutlineAPITests: XCTestCase {
    func testOfflinePolicyBlocksRequestsAndCanResume() async throws {
        let policy = NetworkPolicy()
        policy.setOffline(true)
        var api = OutlineAPI(baseURL: URL(string: "https://unused.invalid")!, token: "")
        api.networkPolicy = policy
        do {
            let _: Envelope<OutlineDocument> = try await api.request("documents.info")
            XCTFail("Offline requests must be blocked")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Work offline is enabled.")
        }
        policy.setOffline(false)
        XCTAssertNoThrow(try policy.check())
    }

    func testQueuedEditsPreserveOriginalRevisionAcrossRelaunch() throws {
        let original = OutlineDocument(id: "page", title: "Before", text: "Original", revision: 7)
        var edited = original; edited.text = "First edit"
        var queue = SyncQueue()
        queue.enqueue(PendingChange(original: original, document: edited, publish: false))
        edited.title = "After"; edited.text = "Second edit"
        queue.enqueue(PendingChange(original: edited, document: edited, publish: true))
        let restored = try JSONDecoder().decode(SyncQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(restored.changes.count, 1)
        XCTAssertEqual(restored.changes[0].original?.text, "Original")
        let body = try restored.changes[0].requestBody()
        XCTAssertEqual(body["lastRevision"] as? Int, 7)
        XCTAssertEqual(body["title"] as? String, "After")
        XCTAssertEqual(body["publish"] as? Bool, true)
    }

    func testEditingQueuedCreationRemainsOneCreation() throws {
        var document = OutlineDocument(id: "local-page", title: "New", text: "First")
        var queue = SyncQueue()
        queue.enqueue(PendingChange(original: nil, document: document, publish: true))
        document.text = "Edited"
        queue.enqueue(PendingChange(original: document, document: document, publish: false))
        XCTAssertEqual(queue.changes.count, 1)
        XCTAssertNil(queue.changes[0].original)
        let body = try queue.changes[0].requestBody()
        XCTAssertNil(body["lastRevision"])
        XCTAssertEqual(body["text"] as? String, "Edited")
        XCTAssertEqual(body["publish"] as? Bool, true)
    }

    func testNormalizesWorkspaceAddress() throws {
        XCTAssertEqual(try OutlineAPI.workspaceURL(" wiki.example.com \n").absoluteString, "https://wiki.example.com")
        XCTAssertEqual(try OutlineAPI.workspaceURL("https://wiki.example.com/").host, "wiki.example.com")
    }
    func testRejectsInsecureOrAmbiguousWorkspaceAddresses() {
        for address in ["http://wiki.example.com", "https://user:password@wiki.example.com", "https://wiki.example.com/doc/secret", "https://wiki.example.com?token=secret", "https://wiki.example.com#doc", ""] {
            XCTAssertThrowsError(try OutlineAPI.workspaceURL(address), address)
        }
    }
    func testDecodesDocumentRevisionAndNullableFields() throws {
        let data = Data(##"{"data":{"id":"a","title":"Document","text":"# Hi","url":"/doc/document-a","collectionId":null,"revision":42},"pagination":null}"##.utf8)
        let result = try JSONDecoder().decode(Envelope<OutlineDocument>.self, from: data)
        XCTAssertEqual(result.data.revision, 42)
        XCTAssertEqual(result.data.text, "# Hi")
        XCTAssertNil(result.data.collectionId)
    }
    func testDecodesSearchEnvelopeAndPagination() throws {
        let data = Data(#"{"data":[{"ranking":0.9,"document":{"id":"a","title":"Match"}}],"pagination":{"limit":100,"offset":0,"nextPath":"/api/documents.search?offset=100"}}"#.utf8)
        let result = try JSONDecoder().decode(Envelope<[SearchHit]>.self, from: data)
        XCTAssertEqual(result.data.first?.document.title, "Match")
        XCTAssertNotNil(result.pagination?.nextPath)
    }
    func testRedirectDelegateRefusesCredentialForwarding() {
        let redirect = NoRedirect()
        let source = URL(string: "https://wiki.example.com/api/documents.list")!
        let destination = URLRequest(url: URL(string: "https://different.example.com")!)
        let response = HTTPURLResponse(url: source, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        redirect.urlSession(session, task: session.dataTask(with: source), willPerformHTTPRedirection: response, newRequest: destination) { request in
            XCTAssertNil(request)
        }
    }
}

private final class StubProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, String))!
    static var headers: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers.merging(["Content-Type": "application/json"]) { _, new in new })!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension OutlineAPITests {
    func testGatewayRedirectRequiresSignInAtWorkspaceOrigin() async {
        StubProtocol.headers = ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login/wiki.example.com?state=private"]
        defer { StubProtocol.headers = [:] }
        StubProtocol.respond = { _ in (302, "") }
        do {
            let _: Envelope<OutlineDocument> = try await stubClient().request("documents.info")
            XCTFail("Expected gateway sign-in")
        } catch let error as GatewaySignInRequired {
            XCTAssertEqual(error.workspaceURL.absoluteString, "https://wiki.example.com")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testServiceTokenRedirectDoesNotRequestBrowserSignIn() async {
        var client = stubClient()
        client.gateway.headers = [.init(name: "cf-access-client-id", value: " client\n")]
        XCTAssertThrowsError(try client.gateway.validatedHeaders())
        client.gateway.headers.append(.init(name: "CF-Access-Client-Secret", value: "secret\r\n"))
        client.gateway.cookies = [.init(name: "CF_Authorization", value: "old", host: "wiki.example.com", expires: nil)]
        StubProtocol.headers = ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login/wiki.example.com", "CF-Ray": "0123456789abcdef-IAD"]
        defer { StubProtocol.headers = [:] }
        StubProtocol.respond = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "client")
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "secret")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (302, "")
        }
        do {
            let _: Envelope<OutlineDocument> = try await client.request("documents.info")
            XCTFail("Expected service token error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("0123456789abcdef-IAD"))
            XCTAssertTrue(error is APIError)
            XCTAssertTrue(error.localizedDescription.contains("redirected the service token request"))
        }
    }

    func testUntrustedRedirectIsNotTreatedAsGateway() async {
        StubProtocol.headers = ["Location": "https://team.cloudflareaccess.com.hostile.example/cdn-cgi/access/login"]
        defer { StubProtocol.headers = [:] }
        StubProtocol.respond = { _ in (302, "") }
        do {
            let _: Envelope<OutlineDocument> = try await stubClient().request("documents.info")
            XCTFail("Expected redirect rejection")
        } catch {
            XCTAssertFalse(error is GatewaySignInRequired)
            XCTAssertTrue(error.localizedDescription.contains("HTTP 302"))
        }
    }

    private func stubClient() -> OutlineAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return OutlineAPI(baseURL: URL(string: "https://wiki.example.com")!, token: "test-token", configuration: config)
    }
    func testPaginationStaysOnWorkspaceOrigin() async throws {
        var count = 0
        StubProtocol.respond = { request in
            count += 1
            XCTAssertEqual(request.url?.absoluteString, "https://wiki.example.com/api/documents.list")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            if count == 1 {
                return (200, #"{"data":[{"id":"a","title":"First"}],"pagination":{"nextPath":"https://hostile.example.com/api/documents.list?offset=1"}}"#)
            }
            XCTAssertEqual(count, 2)
            return (200, #"{"data":[{"id":"b","title":"Second"}],"pagination":{"nextPath":null}}"#)
        }
        let documents: [OutlineDocument] = try await stubClient().list("documents.list")
        XCTAssertEqual(documents.map(\.id), ["a", "b"])
    }
    func testAuthenticationFailureIsActionable() async {
        StubProtocol.respond = { _ in (401, #"{"ok":false,"error":"authentication_required"}"#) }
        do {
            let _: Envelope<OutlineDocument> = try await stubClient().request("documents.info", body: ["id": "a"])
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API key was not accepted"))
        }
    }
}

extension OutlineAPITests {
    func testGatewayHeadersAreAppliedAlongsideOutlineBearer() async throws {
        StubProtocol.respond = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "client-id")
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "test-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (200, #"{"data":{"id":"a","title":"Document"}}"#)
        }
        var api = stubClient()
        api.gateway.headers = [.init(name: "CF-Access-Client-Id", value: "client-id"), .init(name: "CF-Access-Client-Secret", value: "test-secret")]
        let _: Envelope<OutlineDocument> = try await api.request("documents.info")
    }
    func testGatewayRejectsCredentialOverridesAndHeaderInjection() {
        for name in ["Authorization", "Cookie", "Host", "Content-Length", "X-Test\r\nInjected", ""] {
            let gateway = GatewayConfiguration(headers: [.init(name: name, value: "test")])
            XCTAssertThrowsError(try gateway.validatedHeaders(), name)
        }
        XCTAssertThrowsError(try GatewayConfiguration(headers: [.init(name: "X-Test", value: "bad\r\nvalue")]).validatedHeaders())
        XCTAssertThrowsError(try GatewayConfiguration(headers: [.init(name: "X-Test", value: "a"), .init(name: "x-test", value: "b")]).validatedHeaders())
    }
    func testGatewayCredentialsNeverLeaveExactOrigin() throws {
        let origin = URL(string: "https://wiki.example.com")!
        let gateway = GatewayConfiguration(headers: [.init(name: "CF-Access-Client-Id", value: "client-id"), .init(name: "CF-Access-Client-Secret", value: "test-secret")])
        for url in ["http://wiki.example.com", "https://wiki.example.com:444", "https://idp.example.com", "https://wiki.example.com.hostile.example"] {
            var request = URLRequest(url: URL(string: url)!)
            XCTAssertThrowsError(try gateway.apply(to: &request, origin: origin))
            XCTAssertNil(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"))
        }
    }
    func testGatewayCookiesFilterExpiryAndDomainAndRetainBinding() throws {
        let origin = URL(string: "https://wiki.example.com")!
        let gateway = GatewayConfiguration(cookies: [
            .init(name: "CF_Authorization", value: "valid", host: "wiki.example.com", expires: .distantFuture),
            .init(name: "CF_Binding", value: "binding", host: "wiki.example.com", expires: .distantFuture),
            .init(name: "CF_Authorization", value: "expired", host: "wiki.example.com", expires: .distantPast),
            .init(name: "CF_Authorization", value: "foreign", host: "team.cloudflareaccess.com", expires: nil),
            .init(name: "accessToken", value: "other-session", host: "wiki.example.com", expires: nil)
        ])
        var request = URLRequest(url: origin.appendingPathComponent("api/documents.list"))
        try gateway.apply(to: &request, origin: origin)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "CF_Authorization=valid; CF_Binding=binding")
    }
    func testOAuthUsesPKCEAndRejectsUnmatchedCallbacks() throws {
        let attempt = try OAuthAttempt()
        let url = attempt.authorizationURL(origin: URL(string: "https://wiki.example.com")!, clientID: "public-client")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge" })?.value?.count, 43)
        XCTAssertFalse(items.contains(where: { $0.name == "client_secret" || $0.name == "code_verifier" }))
        XCTAssertEqual(try attempt.code(from: URL(string: "\(OAuthAttempt.callback)?state=\(attempt.state)&code=ok")!), "ok")
        for callback in ["\(OAuthAttempt.callback)?state=wrong&code=ok", "us.cwill.margin://other/callback?state=\(attempt.state)&code=ok", "\(OAuthAttempt.callback)?state=\(attempt.state)&code=a&code=b", "\(OAuthAttempt.callback)?state=\(attempt.state)&error=access_denied"] {
            XCTAssertThrowsError(try attempt.code(from: URL(string: callback)!))
        }
        XCTAssertNotEqual(try OAuthAttempt().state, attempt.state)
    }
}

extension OutlineAPITests {
    func testOAuthExchangeUsesFormEncodingAndGatewayHeadersWithoutBearer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.respond = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://wiki.example.com/oauth/token")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "test-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            XCTAssertTrue(String(data: body, encoding: .utf8)!.contains("code=a%2Bb%26c"))
            return (200, #"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"token_type":"Bearer"}"#)
        }
        let credentials = try await OAuthSession.exchange(origin: URL(string: "https://wiki.example.com")!, gateway: .init(headers: [.init(name: "CF-Access-Client-Id", value: "client-id"), .init(name: "CF-Access-Client-Secret", value: "test-secret")]), clientID: "public", fields: ["grant_type": "authorization_code", "code": "a+b&c", "code_verifier": "verifier"], configuration: config)
        XCTAssertEqual(credentials.refreshToken, "refresh")
        XCTAssertEqual(credentials.clientID, "public")
        XCTAssertGreaterThan(credentials.expiresAt.timeIntervalSinceNow, 3500)
    }
}

extension OutlineAPITests {
    func testOutlineBrowserSessionRequiresExactWorkspaceSession() throws {
        let origin = URL(string: "https://wiki.example.com")!
        func cookie(_ name: String, host: String = "wiki.example.com", secure: Bool = true, expiry: Date = .distantFuture) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "test-session", .domain: host, .path: "/", .expires: expiry]
            if secure { properties[.secure] = "TRUE" }
            return HTTPCookie(properties: properties)!
        }
        XCTAssertEqual(try OutlineBrowserSession.token(from: [cookie("accessToken")], origin: origin), "test-session")
        for cookies in [[cookie("CF_Authorization")], [cookie("accessToken", host: "idp.example.com")], [cookie("accessToken", secure: false)], [cookie("accessToken", expiry: .distantPast)]] {
            XCTAssertThrowsError(try OutlineBrowserSession.token(from: cookies, origin: origin))
        }
    }
}

extension OutlineAPITests {
    func testCollectionTreePreservesNestedOrderAndDocumentIdentity() throws {
        let data = Data(#"{"data":[{"id":"parent","title":"Parent","url":"/doc/parent-a","children":[{"id":"second","title":"Second","children":[]},{"id":"first","title":"First","children":[]}]}]}"#.utf8)
        let result = try JSONDecoder().decode(Envelope<[OutlineTreeNode]>.self, from: data)
        XCTAssertEqual(result.data.first?.children.map(\.id), ["second", "first"])
        XCTAssertNil(result.data.first?.children.first?.nested)
        XCTAssertEqual(result.data.first?.document(collectionID: "collection").collectionId, "collection")
        XCTAssertEqual(result.data.first?.document(collectionID: "collection").id, "parent")
    }
}

extension OutlineAPITests {
    func testDocumentEditPreservesUnchangedBlocksAndChecksRevision() throws {
        let original = OutlineDocument(id: "document", title: "Before", text: "First paragraph\n\nKeep this embed\n\nLast paragraph", revision: 7)
        let body = try DocumentChange.body(original: original, title: "After", text: "First edited paragraph\n\nKeep this embed\n\nLast paragraph", revision: 7, publish: false, collection: nil)
        XCTAssertEqual(body["lastRevision"] as? Int, 7)
        XCTAssertEqual(body["editMode"] as? String, "patch")
        let needle = try XCTUnwrap(body["findText"] as? String)
        XCTAssertFalse(needle.contains("Keep this embed"))
        XCTAssertEqual(original.text!.replacingOccurrences(of: needle, with: body["text"] as! String), "First edited paragraph\n\nKeep this embed\n\nLast paragraph")
        XCTAssertThrowsError(try DocumentChange.body(original: original, title: "After", text: "edit", revision: nil, publish: false, collection: nil))
    }
    func testPatchDisambiguatesRepeatedTextAndUnicode() throws {
        for (old, new) in [("hello hello", "hello goodbye"), ("👋 café", "👋 café!"), ("abc", ""), ("same", "prefix same"), ("abcabc", "abcXabc")] {
            let doc = OutlineDocument(id: "a", title: "A", text: old)
            let body = try DocumentChange.body(original: doc, title: "A", text: new, revision: 1, publish: false, collection: nil)
            let needle = try XCTUnwrap(body["findText"] as? String)
            XCTAssertEqual(old.components(separatedBy: needle).count, 2)
            XCTAssertEqual(old.replacingOccurrences(of: needle, with: body["text"] as! String), new)
        }
    }
    func testReadingHidesOnlyMatchingLeadingTitle() {
        XCTAssertEqual(DocumentReading.body("# Title\n\nBody", title: "Title"), "Body")
        XCTAssertEqual(DocumentReading.body("\nTitle\n=====\n\nBody", title: "Title"), "Body")
        for text in ["# Other\n\nBody", "## Title\nBody", "Body\n\n# Title", "```\n# Title\n```"] {
            XCTAssertEqual(DocumentReading.body(text, title: "Title"), text)
        }
    }
    func testOfflineSnapshotRetainsHierarchyAndDocumentContent() throws {
        let document = OutlineDocument(id: "child", title: "Child", text: "Offline text", collectionId: "collection", revision: 4, parentDocumentId: "parent")
        let snapshot = LibrarySnapshot(collections: [.init(id: "collection", name: "Knowledge")], documents: [document], trees: ["collection": [.init(id: "parent", title: "Parent", children: [.init(id: "child", title: "Child", children: [])])]], draftIDs: ["draft"])
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.documents.first, document)
        XCTAssertEqual(restored.trees["collection"]?.first?.children.first?.id, "child")
        XCTAssertEqual(restored.draftIDs, ["draft"])
        let identity = try JSONDecoder().decode(Envelope<OutlineIdentity>.self, from: Data(#"{"data":{"user":{"name":"Reader","avatarUrl":null}}}"#.utf8))
        XCTAssertEqual(identity.data.user.name, "Reader")
        XCTAssertNil(identity.data.user.avatarUrl)
    }
}
