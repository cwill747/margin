import SwiftUI

@main struct MarginApp: App {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @State private var workspace = Workspace()
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-keychain") {
            do { try CredentialStore.verifyAccess(); print("MARGIN_KEYCHAIN_CHECK_PASSED") }
            catch { print("MARGIN_KEYCHAIN_CHECK_FAILED") }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if workspace.api != nil || workspace.demo { LibraryView(workspace: workspace) }
                else { ConnectView(workspace: workspace) }
            }
            .appSurface()
            .preferredColorScheme(palette.scheme)
        }
    }
}

struct ConnectView: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    @State private var host = ""
    @State private var token = ""
    @State private var useSSO = true
    @State private var gateway = GatewayConfiguration()
    @State private var resumeAPIKeyConnection = false
    @State private var gatewayURL: URL?
    @State private var outlineURL: URL?
    @State private var browser = BrowserSignIn()
    @State private var connecting = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "book.pages.fill").font(.system(size: 48)).foregroundStyle(.tint).padding(.top, 48).accessibilityLabel("Margin")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A little more room\nto think.").font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text("Your Outline workspace, made for the way you read, connect, and explore.").font(.title3).foregroundStyle(palette.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connect your workspace").font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        TextField("https://…", text: $host).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Workspace address")
                        Divider()
                        Picker("Sign-in method", selection: $useSSO) {
                            Text("Sign in").tag(true)
                            Text("API key").tag(false)
                        }.pickerStyle(.segmented)
                        if useSSO {
                            Text("Sign in with your existing Outline account.").font(.footnote).foregroundStyle(palette.secondary)
                        } else {
                            SecureField("Outline API key", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("Create a key in Outline’s Settings → API & Apps. Your key is stored in this device’s Keychain.").font(.footnote).foregroundStyle(palette.secondary)
                        }
                        DisclosureGroup("Advanced connection settings") {
                            VStack(alignment: .leading, spacing: 16) {
                                GatewayFields(configuration: $gateway)
                                if !gateway.usesServiceToken {
                                    Button("Verify Cloudflare Access") {
                                        do { resumeAPIKeyConnection = false; gatewayURL = try OutlineAPI.workspaceURL(host) }
                                        catch { self.error = error.localizedDescription }
                                    }
                                    if !gateway.cookies.isEmpty { Text("Cloudflare Access verified").font(.footnote).foregroundStyle(palette.secondary) }
                                }
                            }.padding(.top)
                        }
                    }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(palette.foreground).font(.callout) }
                    Button {
                        error = nil
                        if useSSO {
                            do { try CredentialStore.verifyAccess(); outlineURL = try OutlineAPI.workspaceURL(host) }
                            catch { self.error = error.localizedDescription }
                            return
                        }
                        connectWithKey()
                    } label: {
                        HStack { Spacer(); if connecting { ProgressView() }; Text(connecting ? "Connecting…" : (useSSO ? "Sign in to Outline" : "Open workspace")).bold(); Image(systemName: "arrow.right"); Spacer() }.padding(8)
                    }.buttonStyle(.borderedProminent).disabled(connecting || host.isEmpty || (!useSSO && token.isEmpty))
                    Button { workspace.showDemo() } label: {
                        Text("Explore a sample workspace").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.disabled(connecting)
                    Text("MARGIN · An independent Outline companion").font(.footnote).foregroundStyle(palette.secondary).frame(maxWidth: .infinity)
                }.padding(28).frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }.scrollEdgeEffectHidden().background(palette.background)
        }
        .sheet(isPresented: Binding(get: { gatewayURL != nil }, set: { if !$0 { gatewayURL = nil } })) {
            if let gatewayURL {
                GatewayLoginView(origin: gatewayURL) { cookies in
                    gateway.cookies = cookies
                    if resumeAPIKeyConnection { connectWithKey(afterVerification: true) }
                }
            }
        }
        .sheet(isPresented: Binding(get: { outlineURL != nil }, set: { if !$0 { outlineURL = nil } })) {
            if let outlineURL {
                GatewayLoginView(origin: outlineURL, outlineCompletion: { token, cookies in
                    var settings = gateway; settings.cookies = cookies
                    try await workspace.connect(host: outlineURL.absoluteString, token: token, gateway: settings, browserSession: true)
                }, completion: { _ in })
            }
        }
        .announceAccessibilityChanges(error)
        .onChange(of: host) { _, _ in gateway.cookies = [] }
        .onDisappear { browser.cancel() }
    }

    private func connectWithKey(afterVerification: Bool = false) {
        connecting = true
        error = nil
        Task {
            defer { connecting = false }
            do {
                try await workspace.connect(host: host, token: token, gateway: gateway)
            } catch let challenge as GatewaySignInRequired {
                if afterVerification {
                    error = "Cloudflare Access still requires verification. Check that you have access to this workspace and try again."
                } else {
                    resumeAPIKeyConnection = true
                    gatewayURL = challenge.workspaceURL
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

}

private struct SidebarSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let palette: ReadingPalette

    final class Coordinator: NSObject, UITextFieldDelegate {
        var field: SidebarSearchField
        init(_ field: SidebarSearchField) { self.field = field }
        @objc func changed(_ sender: UITextField) { field.text = sender.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { field.focused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { field.focused = false }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.accessibilityLabel = "Search your knowledge"
        field.returnKeyType = .search
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.adjustsFontForContentSizeCategory = true
        field.font = .preferredFont(forTextStyle: .subheadline)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.field = self
        if field.text != text { field.text = text }
        field.textColor = UIColor(palette.foreground)
        field.attributedPlaceholder = NSAttributedString(string: "Search", attributes: [.foregroundColor: UIColor(palette.secondary)])
        if focused && !field.isFirstResponder { field.becomeFirstResponder() }
        if !focused && field.isFirstResponder { field.resignFirstResponder() }
    }
}

private struct PageIcon: View {
    let document: OutlineDocument
    var fallback = "doc.text"

    private static let symbols = [
        "academicCap": "graduationcap", "beaker": "flask", "buildingBlocks": "square.3.layers.3d",
        "browser": "macwindow", "collection": "folder", "coins": "dollarsign.circle",
        "code": "chevron.left.forwardslash.chevron.right", "database": "externaldrive",
        "done": "checkmark.circle", "email": "envelope", "feedback": "bubble.left",
        "graph": "chart.bar", "hashtag": "number", "icecream": "birthday.cake",
        "image": "photo", "internet": "network", "library": "books.vertical",
        "lightning": "bolt", "letter": "envelope", "math": "function", "notepad": "note.text",
        "padlock": "lock", "palette": "paintpalette", "plane": "airplane",
        "promote": "megaphone", "question": "questionmark.circle", "server": "server.rack",
        "sun": "sun.max", "sport": "soccerball", "smiley": "face.smiling",
        "team": "person.3", "thumbsup": "hand.thumbsup", "truck": "box.truck",
        "tools": "wrench.and.screwdriver", "vehicle": "car", "warning": "exclamationmark.triangle"
    ]

    private var tint: Color? {
        guard let hex = document.color?.trimmingCharacters(in: CharacterSet(charactersIn: "#")),
              hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double(rgb >> 16) / 255, green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }

    var body: some View {
        Group {
            if let icon = document.icon, icon.count == 1,
               icon.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
                Text(icon)
            } else {
                let name = document.icon.map { Self.symbols[$0] ?? $0 } ?? fallback
                Image(systemName: UIImage(systemName: name) == nil ? fallback : name)
                    .foregroundStyle(tint ?? .accentColor)
            }
        }.accessibilityHidden(true)
    }
}

struct LibraryView: View {
    @AppStorage("compactSidebar") private var compactSidebar = false
    private var articleFont: Font { compactSidebar ? .footnote : .body }
    private var articleInsets: EdgeInsets? {
        compactSidebar ? EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8) : nil
    }
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var workspace: Workspace
    @State private var selected: OutlineDocument?
    @State private var companion: OutlineDocument?
    @State private var collection: String?
    @State private var savedOnly = false
    @State private var query = ""
    @State private var sidebarScrollRequest = 0
    @State private var sidebarScrollTarget = "sidebar-search"
    @State private var revealSearch = false
    @State private var expandedNodes: Set<String> = []
    @State private var searchFocused = false
    @AccessibilityFocusState private var searchAccessibilityFocused: Bool
    @State private var results: [OutlineDocument] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var showSettings = false
    @State private var composing = false
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var visibility = NavigationSplitViewVisibility.all
    init(workspace: Workspace) {
        self.workspace = workspace
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let screen = ProcessInfo.processInfo.environment["MARGIN_TEST_SCREEN"] ?? "library"
            if ["reader", "reference", "error", "loading", "offline", "editor", "preview"].contains(screen) {
                _selected = State(initialValue: workspace.documents.first)
                _compactColumn = State(initialValue: .detail)
                _visibility = State(initialValue: .detailOnly)
            }
            if screen == "reference" { _companion = State(initialValue: workspace.documents.last) }
            if screen == "settings" { _showSettings = State(initialValue: true); _compactColumn = State(initialValue: .detail) }
            if screen == "compose" { _composing = State(initialValue: true); _compactColumn = State(initialValue: .detail) }
            if screen == "empty" { _query = State(initialValue: "no-matching-document") }
            if screen == "search" { _query = State(initialValue: "Field") }
            if screen == "offline", let document = workspace.documents.first {
                workspace.saved = [document]; workspace.workOffline = true
            }
        }
        #endif
    }
    var visibleDocuments: [OutlineDocument] {
        let source = query.isEmpty ? (savedOnly ? workspace.saved : workspace.documents) : results
        return source.filter { collection == nil || $0.collectionId == collection }
    }
    private func sectionToggle(_ title: String, id: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                if workspace.expandedSections.contains(id) { workspace.expandedSections.remove(id) }
                else { workspace.expandedSections.insert(id) }
            }
        } label: {
            HStack {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("collection-title-" + id)
                Spacer()
                Image(systemName: workspace.expandedSections.contains(id) ? "chevron.down" : "chevron.right").font(.system(size: 17, weight: .semibold))
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(workspace.expandedSections.contains(id) ? "Expanded" : "Collapsed")
            .accessibilityHint("Expand or collapse this collection")
    }
    private func sidebarDocument(_ node: OutlineTreeNode, collectionID: String) -> OutlineDocument {
        var document = workspace.documents.first(where: { $0.id == node.id }) ?? node.document(collectionID: collectionID)
        document.icon = node.icon ?? document.icon
        document.color = node.color ?? document.color
        return document
    }
    private func collectionSection(_ collection: OutlineCollection) -> some View {
                        Section {
                            if workspace.expandedSections.contains(collection.id) {
                            if let nodes = workspace.trees[collection.id] {
                                ForEach(sidebarRows(nodes), id: \.node.id) { row in
                                    let document = sidebarDocument(row.node, collectionID: collection.id)
                                    HStack(spacing: compactSidebar ? 2 : 8) {
                                        if !row.node.children.isEmpty {
                                            Button {
                                                if !expandedNodes.insert(row.node.id).inserted { expandedNodes.remove(row.node.id) }
                                            } label: {
                                                Image(systemName: expandedNodes.contains(row.node.id) ? "chevron.down" : "chevron.right").font(.system(size: compactSidebar ? 13 : 17, weight: .semibold))
                                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                                            }.buttonStyle(.plain)
                                                .accessibilityLabel("Children of " + row.node.title)
                                                .accessibilityValue(expandedNodes.contains(row.node.id) ? "Expanded" : "Collapsed")
                                        } else {
                                            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                                        }
                                        Button { openSidebarDocument(document) } label: {
                                            HStack {
                                                Group {
                                                    if dynamicTypeSize.isAccessibilitySize { Text(row.node.title) }
                                                    else { Label { Text(row.node.title) } icon: { PageIcon(document: document) }.lineLimit(2) }
                                                }.fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 0)
                                                if selected?.id == document.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        .accessibilityAddTraits(selected?.id == document.id ? [.isSelected] : [])
                                        .accessibilityAction(named: "Keep beside") { companion = document }
                                    }
                                    .font(articleFont)
                                    .listRowInsets(articleInsets)
                                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? CGFloat(min(row.depth, 2)) * 8 : CGFloat(row.depth) * (compactSidebar ? 10 : 16))
                                    .id(document.id)
                                    .listRowBackground(selected?.id == document.id ? palette.accent.opacity(0.15) : palette.surface)
                                    .contextMenu { Button("Keep beside", systemImage: "rectangle.split.2x1") { companion = document } }
                                }
                                if nodes.isEmpty { Text("No documents").foregroundStyle(palette.secondary) }
                            } else if workspace.busy { ProgressView() }
                            }
                        } header: {
                            sectionToggle(collection.name, id: collection.id)
                        }
    }
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: companion) { _, value in
            if value != nil { visibility = .detailOnly }
        }
        .onChange(of: selected?.id) { _, _ in composing = false; showSettings = false }
        .task { await workspace.refresh() }
        .task(id: "\(savedOnly)-\(query)") {
            guard !query.isEmpty else { results = []; searching = false; searchError = nil; return }
            searching = true; searchError = nil
            do {
                try await Task.sleep(for: .milliseconds(300))
                let matches: [OutlineDocument]
                if savedOnly {
                    matches = workspace.saved.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.text ?? "").localizedCaseInsensitiveContains(query) }
                } else { matches = try await workspace.search(query) }
                try Task.checkCancellation()
                results = matches; searching = false
            } catch is CancellationError { } catch { if !Task.isCancelled { searchError = error.localizedDescription; searching = false } }
        }
        .announceAccessibilityChanges(searchError)
        .alert("Workspace", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }
    private func sidebarRows(_ nodes: [OutlineTreeNode], depth: Int = 0) -> [(node: OutlineTreeNode, depth: Int)] {
        nodes.flatMap { node in
            [(node: node, depth: depth)] + (expandedNodes.contains(node.id) ? sidebarRows(node.children, depth: depth + 1) : [])
        }
    }
    private func ancestorPath(to id: String, in nodes: [OutlineTreeNode]) -> [String]? {
        for node in nodes {
            if node.id == id { return [] }
            if let path = ancestorPath(to: id, in: node.children) { return [node.id] + path }
        }
        return nil
    }
    private func revealSidebarSelection() {
        if revealSearch || selected == nil {
            sidebarScrollTarget = "sidebar-search"
        } else if let selected {
            // Retain search results when they already contain the open page.
            if !query.isEmpty && !visibleDocuments.contains(where: { $0.id == selected.id }) { query = "" }
            if savedOnly && !workspace.saved.contains(where: { $0.id == selected.id }) { savedOnly = false }
            if query.isEmpty && !savedOnly {
                for (collectionID, nodes) in workspace.trees {
                    if let path = ancestorPath(to: selected.id, in: nodes) {
                        workspace.expandedSections.insert(collectionID)
                        expandedNodes.formUnion(path)
                        break
                    }
                }
                if workspace.draftIDs.contains(selected.id) { workspace.expandedSections.insert("drafts") }
            }
            sidebarScrollTarget = selected.id
        }
        sidebarScrollRequest += 1
    }
    private func openSidebarDocument(_ document: OutlineDocument) {
        searchFocused = false
        revealSearch = false
        composing = false
        showSettings = false
        selected = document
        compactColumn = .detail
        if sizeClass == .compact { visibility = .detailOnly }
    }
    private var searchButton: some View {
        Button("Search", systemImage: "magnifyingglass") {
            revealSearch = true
            visibility = .all
            compactColumn = .sidebar
            revealSidebarSelection()
        }.labelStyle(.iconOnly).accessibilityHint("Show search at the top of the sidebar")
    }
    private var newDocumentButton: some View {
        Button("New document", systemImage: "plus") {
            showSettings = false; composing = true; compactColumn = .detail
        }
        .labelStyle(.iconOnly)
        .keyboardShortcut("n", modifiers: .command)
    }
    private var sidebarContent: some View {
        ScrollViewReader { proxy in
            List {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary).accessibilityHidden(true)
                    SidebarSearchField(text: $query, focused: $searchFocused, palette: palette)
                        .accessibilityFocused($searchAccessibilityFocused)
                        .frame(minHeight: 44)
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(palette.surface)
                .id("sidebar-search")
                Group {
                if query.isEmpty && !savedOnly {
                    ForEach(workspace.collections) { collection in
                        collectionSection(collection)
                    }
                    if !workspace.draftIDs.isEmpty {
                        Section {
                            if workspace.expandedSections.contains("drafts") {
                            ForEach(workspace.documents.filter { workspace.draftIDs.contains($0.id) }) { document in
                                Button { openSidebarDocument(document) } label: {
                                    Label { Text(document.title) } icon: { PageIcon(document: document, fallback: "doc.badge.ellipsis") }
                                        .font(articleFont).frame(minHeight: 44)
                                }.listRowInsets(articleInsets).id(document.id)
                            }
                            }
                        } header: {
                            sectionToggle("Drafts", id: "drafts")
                        }
                    }
                } else {
                Section(query.isEmpty ? (savedOnly ? "Saved reading" : "Your documents") : "Search results") {
                    if workspace.busy && workspace.documents.isEmpty { ProgressView("Loading your workspace…") }
                    if searching { ProgressView("Searching workspace…") }
                    if let searchError { Label(searchError, systemImage: "exclamationmark.circle").foregroundStyle(palette.foreground) }
                    ForEach(visibleDocuments) { document in
                        Button { openSidebarDocument(document) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                PageIcon(document: document).font(articleFont).padding(.top, 3)
                                VStack(alignment: .leading, spacing: compactSidebar ? 1 : 5) {
                                    Text(document.title).font(articleFont.weight(.medium)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
                                    Text(workspace.collections.first { $0.id == document.collectionId }?.name ?? "Document").font(.caption).foregroundStyle(palette.secondary)
                                }
                            }.padding(.vertical, compactSidebar ? 0 : 5).frame(minHeight: 44)
                        }.listRowInsets(articleInsets).accessibilityAction(named: "Keep beside") { companion = document }
                        .accessibilityAddTraits(selected?.id == document.id ? [.isSelected] : [])
                        .id(document.id).contextMenu { Button("Keep beside", systemImage: "rectangle.split.2x1") { companion = document } }
                    }
                    if visibleDocuments.isEmpty && !searching && !workspace.busy {
                        VStack(spacing: 12) {
                            Image(systemName: savedOnly ? "bookmark" : "magnifyingglass").font(.title).accessibilityHidden(true)
                            Text(savedOnly ? "Your reading shelf" : "No documents").font(.headline)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("empty-title")
                            Text(savedOnly ? "Save a document to read it here, even offline." : "Try another collection or search.")
                                .font(.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("empty-help")
                        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 24)
                    }
                }
                }
            
                }.listRowBackground(palette.surface)
            }
            .transformEnvironment(\.defaultMinListRowHeight) { height in
                if compactSidebar { height = 44 }
            }
            .listSectionSpacing(compactSidebar ? .compact : .default)
            .appSurface()
            .navigationTitle("Margin")
            .scrollDismissesKeyboard(.interactively)
            .onAppear { revealSidebarSelection() }
            .onChange(of: visibility) { _, value in
                if value != .detailOnly { revealSidebarSelection() }
                else { revealSearch = false }
            }
            .onChange(of: compactColumn) { _, value in
                if value == .sidebar { revealSidebarSelection() }
                else { revealSearch = false }
            }
            .task(id: sidebarScrollRequest) {
                // Let expanded collection/ancestor rows enter the list before scrolling.
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(sidebarScrollTarget, anchor: revealSearch ? .top : .center)
                if revealSearch { searchAccessibilityFocused = true; searchFocused = true }
            }
            .refreshable { await workspace.refresh() }
            .onChange(of: composing) { _, isComposing in
                if isComposing { visibility = .detailOnly }
            }
            .toolbar {
                ToolbarItem(placement: sizeClass == .compact ? .topBarTrailing : .topBarLeading) {
                    avatarButton
                }.horizontalWhenAvailable()
                if sizeClass == .compact {
                    ToolbarItem(placement: .primaryAction) { searchButton }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        newDocumentButton
                    }
                }
            }
    }
    }
    private var detailContent: some View {
            Group {
                if showSettings {
                    WorkspaceSettings(workspace: workspace, onClose: { showSettings = false; if selected == nil { compactColumn = .sidebar } }, onOpen: { document in
                        openSidebarDocument(document)
                    })
                } else if composing {
                    ComposeView(workspace: workspace, onCreated: { document in
                        selected = document; savedOnly = false; collection = nil; query = ""
                    }, onClose: { composing = false; if selected == nil { compactColumn = .sidebar } })
                } else {
                    DuoReader(workspace: workspace, document: selected, onCreateDocument: {
                        showSettings = false; composing = true; compactColumn = .detail
                    }, companion: $companion, onNavigate: { destination in
                        revealSearch = false
                        selected = destination
                        revealSidebarSelection()
                    })
                }
            }
            .appSurface()
            .toolbar {
                if !composing && !showSettings {
                    ToolbarItem(placement: .primaryAction) { searchButton }
                }
            }
    }
    private var avatarButton: some View {
        Button { composing = false; showSettings = true; compactColumn = .detail } label: {
            if let avatar = workspace.avatar {
                Image(uiImage: avatar).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(Circle())
            } else { Image(systemName: "person.crop.circle").font(.title2) }
        }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("workspace-settings").accessibilityLabel("Settings for " + (workspace.profile?.name ?? workspace.name))
    }
}

private struct WorkspaceSettings: View {
    @AppStorage("compactSidebar") private var compactSidebar = false
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    let onClose: () -> Void
    let onOpen: (OutlineDocument) -> Void
    private enum Page { case connection, acknowledgements }
    @State private var page: Page?
    @State private var showOfflinePages = false
    var body: some View {
        Group {
            switch page {
            case .connection:
                ConnectionSettingsView(workspace: workspace)
                    .toolbar { settingsBackButton }
            case .acknowledgements:
                ScrollView { Text(acknowledgements).font(.footnote).textSelection(.enabled).padding() }
                    .appSurface()
                    .navigationTitle("Acknowledgements")
                    .toolbar { settingsBackButton }
            case nil:
                settingsContent
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    private var settingsBackButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Back to Settings", systemImage: "chevron.left") { page = nil }
        }
    }
    private var settingsContent: some View {
        VStack(spacing: 0) {
            Form {
                Group {
                Section("Workspace") {
                    HStack {
                        if let avatar = workspace.avatar { Image(uiImage: avatar).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(Circle()).accessibilityHidden(true) }
                        VStack(alignment: .leading) {
                            if let name = workspace.profile?.name { Text(name).font(.headline) }
                            Text(workspace.name).foregroundStyle(palette.secondary)
                        }
                    }
                }
                AppearanceSettings()
                Section("Sidebar") { Toggle("Compact article rows", isOn: $compactSidebar) }
                Section {
                    Toggle("Work offline", isOn: $workspace.workOffline)
                    if workspace.pendingCount > 0 { Text("\(workspace.pendingCount) changes queued to sync") }
                    Picker("Sync offline", selection: $workspace.offlineMode) {
                        ForEach(OfflineMode.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { Task { await workspace.refresh() } }
                        .disabled(workspace.workOffline || workspace.syncing || workspace.busy)
                    if workspace.syncing { ProgressView("Syncing \(workspace.syncCompleted) of \(workspace.syncTotal)", value: Double(workspace.syncCompleted), total: Double(max(1, workspace.syncTotal))) }
                    Text("\(workspace.saved.count) pages available offline").font(.body).accessibilityIdentifier("offline-count")
                    if let error = workspace.syncError { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(palette.foreground) }
                } header: { Label("Offline", systemImage: "arrow.down.circle").font(.headline).accessibilityIdentifier("offline-heading") } footer: {
                    Text("Work offline pauses sync and queues changes on this device until you turn it off. Manual: sync individual pages using their download button. Pages I open: automatically save each page you read. Everything: sync all accessible pages. Saved pages update while the app is open and connected. Images and attachments still require a connection.").font(.footnote).accessibilityIdentifier("offline-help")
                }
                if !workspace.saved.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showOfflinePages) {
                            ForEach(workspace.saved) { document in
                                Button(document.title) { onOpen(document) }
                            }
                        } label: {
                            LabeledContent("Available offline", value: "\(workspace.saved.count)")
                        }
                    }
                }
                if !workspace.demo {
                    Section { Button("Connection and sign-in") { page = .connection } }
                }
                Section {
                    Button("Open-source acknowledgements") { page = .acknowledgements }
                }
                Section {
                    Button(workspace.demo ? "Leave sample workspace" : "Disconnect and clear saved documents", role: .destructive) { Task { await workspace.signOut(); if workspace.api == nil { onClose() } } }
                }
            
                }.listRowBackground(palette.surface)
            }
            .appSurface()
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back", systemImage: "chevron.left", action: onClose) } }
            .announceAccessibilityChanges(workspace.syncError)
            .onChange(of: workspace.offlineMode) { _, _ in Task { await workspace.syncOffline() } }
        }
    }
    private var acknowledgements: String {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "See the source repository for library licenses." }
        return text
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder func horizontalWhenAvailable() -> some ToolbarContent {
        if #available(iOS 27.1, *) { self.axisBehavior(.horizontalOnly) }
        else { self }
    }
}
