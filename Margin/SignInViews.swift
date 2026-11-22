import SwiftUI
import WebKit
import AuthenticationServices

@MainActor final class BrowserSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor!
    }
    func authorize(url: URL) async throws -> URL {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { throw APIError(message: "Open Margin before starting sign-in.") }
        anchor = window
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("us.cwill.margin")) { [weak self] url, error in
                self?.session = nil
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? APIError(message: "Sign-in was cancelled.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: APIError(message: "Could not open the sign-in browser."))
            }
        }
    }
    func cancel() { session?.cancel(); session = nil }
}

struct GatewayFields: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Binding var configuration: GatewayConfiguration
    var body: some View {
        ForEach($configuration.headers) { $header in
            VStack(alignment: .leading) {
                HStack {
                    TextField("Header name", text: $header.name).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Remove header", systemImage: "minus.circle") { configuration.headers.removeAll { $0.id == header.id } }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                SecureField("Header value", text: $header.value).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        Button("Add header", systemImage: "plus") { configuration.headers.append(.init()) }
        Button("Add access-service headers") {
            for name in ["CF-Access-Client-Id", "CF-Access-Client-Secret"] where !configuration.headers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                configuration.headers.append(.init(name: name))
            }
        }
        Text("Headers are stored in Keychain and sent only to this workspace’s native API and OAuth token requests. Browser sign-in uses your workspace’s normal login.").font(.footnote).foregroundStyle(palette.secondary)
    }
}

struct GatewayLoginView: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    let origin: URL
    var outlineCompletion: ((String, [GatewayCookie]) async throws -> Void)? = nil
    let completion: ([GatewayCookie]) -> Void
    @State private var verifying = false
    @Environment(\.dismiss) private var dismiss
    @State private var model = GatewayWebModel()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(model.address.isEmpty ? origin.host! : model.address).font(.caption).lineLimit(nil).padding(8)
                Text(outlineCompletion == nil ? "Your workspace uses Cloudflare Access. Complete its verification, then tap Continue." : "Sign in below, then tap Connect to open your workspace.").font(.footnote).foregroundStyle(palette.secondary).padding(.horizontal)
                if let error = model.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(palette.foreground).padding() }
                GatewayWebView(origin: origin, model: model)
            }.appSurface().announceAccessibilityChanges(model.error).navigationTitle(outlineCompletion == nil ? "Verify Cloudflare Access" : "Sign in to Outline").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(verifying ? "Connecting…" : (outlineCompletion == nil ? "Continue" : "Connect")) {
                            verifying = true
                            Task {
                                defer { verifying = false }
                                let cookies = await model.store.httpCookieStore.allCookies()
                                let accepted = cookies.filter {
                                    $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == origin.host?.lowercased() &&
                                    ["CF_Authorization", "CF_Binding"].contains($0.name) && $0.isSecure &&
                                    ($0.expiresDate == nil || $0.expiresDate! > Date()) && $0.path == "/"
                                }.map { GatewayCookie(name: $0.name, value: $0.value, host: origin.host!.lowercased(), expires: $0.expiresDate) }
                                if let outlineCompletion {
                                    do {
                                        let token = try OutlineBrowserSession.token(from: cookies, origin: origin)
                                        try await outlineCompletion(token, accepted)
                                        dismiss()
                                    } catch { model.error = error.localizedDescription }
                                    return
                                }
                                guard accepted.contains(where: { $0.name == "CF_Authorization" }) else {
                                    model.error = "Complete your workspace’s access sign-in first. If your sign-in method requires a system browser, configure access headers in advanced settings."
                                    return
                                }
                                completion(accepted); dismiss()
                            }
                        }.disabled(verifying)
                    }
                }
        }
    }
}

@MainActor @Observable final class GatewayWebModel {
    var address = ""
    var error: String?
    let store = WKWebsiteDataStore.nonPersistent()
}

private struct GatewayWebView: UIViewRepresentable {
    let origin: URL
    let model: GatewayWebModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = model.store
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        // No API keys or custom headers enter the embedded sign-in browser.
        web.load(URLRequest(url: origin))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: GatewayWebModel
        init(model: GatewayWebModel) { self.model = model }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.request.url?.scheme == "https" else { decisionHandler(.cancel); return }
            model.address = navigationAction.request.url?.host ?? ""
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { model.error = "The sign-in page could not load. Check your connection and try again." }
        }
    }
}

struct ConnectionSettingsView: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    @State private var gateway = GatewayConfiguration()
    @State private var showGateway = false
    @State private var showOutline = false
    @State private var clientID = UserDefaults.standard.string(forKey: "oauthClientID") ?? ""
    @State private var browser = BrowserSignIn()
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
                Group {
            Section("Advanced connection settings") {
                GatewayFields(configuration: $gateway)
                if !gateway.usesServiceToken {
                    Button("Verify Cloudflare Access") { showGateway = true }
                }
                if !gateway.cookies.isEmpty {
                    Button("Clear access session", role: .destructive) { gateway.cookies = [] }
                }
                Button("Save connection settings") {
                    run {
                        try await workspace.updateGateway(gateway)
                        await workspace.refresh()
                        message = "Connection settings saved."
                    }
                }
            }
            Section {
                Button("Sign in to Outline") { showOutline = true }
            }
            Section("Advanced: OAuth SSO") {
                TextField("Public OAuth client ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Redirect URI: \(OAuthAttempt.callback)").font(.caption).textSelection(.enabled)
                Button("Reconnect with SSO") {
                    guard let host = workspace.api?.baseURL.absoluteString else { return }
                    run { try await workspace.connectSSO(host: host, clientID: clientID, gateway: gateway, browser: browser); message = "Signed in." }
                }.disabled(clientID.isEmpty)
            }
            if busy { ProgressView("Connecting…") }
            if let message { Text(message).font(.callout) }
        
                }.listRowBackground(palette.surface)
            }.appSurface().navigationTitle("Connection").disabled(busy)
            .task { if let origin = workspace.api?.baseURL { gateway = GatewayConfiguration.load(for: origin) } }
            .sheet(isPresented: $showGateway) {
                if let origin = workspace.api?.baseURL {
                    GatewayLoginView(origin: origin) { cookies in
                        run {
                            guard var settings = workspace.api?.gateway else { return }
                            settings.cookies = cookies
                            try await workspace.updateGateway(settings)
                            gateway.cookies = cookies
                            message = "Sign-in session refreshed."
                        }
                    }
                }
            }
            .sheet(isPresented: $showOutline) {
                if let origin = workspace.api?.baseURL {
                    GatewayLoginView(origin: origin, outlineCompletion: { token, cookies in
                        var settings = gateway; settings.cookies = cookies
                        try await workspace.connect(host: origin.absoluteString, token: token, gateway: settings, browserSession: true)
                        gateway = settings
                    }, completion: { _ in })
                }
            }
            .onDisappear { browser.cancel() }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true; message = nil
        Task {
            do { try await operation() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
