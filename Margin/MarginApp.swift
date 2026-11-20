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
    @State private var gatewayURL: URL?
    @State private var outlineURL: URL?
    @State private var browser = BrowserSignIn()
    @State private var connecting = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "book.pages.fill").font(.system(size: 48)).foregroundStyle(.tint).padding(.top, 48)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A little more room\nto think.").font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text("Your Outline workspace, made for the way you read, connect, and explore.").font(.title3).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("CONNECT YOUR WORKSPACE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        TextField("https://your-team.getoutline.com", text: $host).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Workspace address")
                        Divider()
                        Picker("Sign-in method", selection: $useSSO) {
                            Text("Sign in").tag(true)
                            Text("API key").tag(false)
                        }.pickerStyle(.segmented)
                        if useSSO {
                            Text("Sign in with your existing Outline account.").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            SecureField("Outline API key", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("Create a key in Outline’s Settings → API & Apps. Your key is stored in this device’s Keychain.").font(.footnote).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Advanced connection settings") {
                            VStack(alignment: .leading, spacing: 16) {
                                GatewayFields(configuration: $gateway)
                                Button("Refresh sign-in session") {
                                    do { gatewayURL = try OutlineAPI.workspaceURL(host) }
                                    catch { self.error = error.localizedDescription }
                                }
                                if !gateway.cookies.isEmpty { Text("Sign-in session ready").font(.footnote).foregroundStyle(.secondary) }
                            }.padding(.top)
                        }
                    }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                    Button {
                        error = nil
                        if useSSO {
                            do { try CredentialStore.verifyAccess(); outlineURL = try OutlineAPI.workspaceURL(host) }
                            catch { self.error = error.localizedDescription }
                            return
                        }
                        connecting = true
                        Task {
                            do {
                                try await workspace.connect(host: host, token: token, gateway: gateway)
                            }
                            catch { self.error = error.localizedDescription }
                            connecting = false
                        }
                    } label: {
                        HStack { Spacer(); if connecting { ProgressView() }; Text(connecting ? "Connecting…" : (useSSO ? "Sign in to Outline" : "Open workspace")).bold(); Image(systemName: "arrow.right"); Spacer() }.padding(8)
                    }.buttonStyle(.borderedProminent).disabled(connecting || host.isEmpty || (!useSSO && token.isEmpty))
                    Button("Explore a sample workspace") { workspace.showDemo() }.disabled(connecting).frame(maxWidth: .infinity)
                    Text("MARGIN · An independent Outline companion").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(28).frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }.background(palette.background)
        }
        .sheet(isPresented: Binding(get: { gatewayURL != nil }, set: { if !$0 { gatewayURL = nil } })) {
            if let gatewayURL { GatewayLoginView(origin: gatewayURL) { gateway.cookies = $0 } }
        }
        .sheet(isPresented: Binding(get: { outlineURL != nil }, set: { if !$0 { outlineURL = nil } })) {
            if let outlineURL {
                GatewayLoginView(origin: outlineURL, outlineCompletion: { token, cookies in
                    var settings = gateway; settings.cookies = cookies
                    try await workspace.connect(host: outlineURL.absoluteString, token: token, gateway: settings, browserSession: true)
                }, completion: { _ in })
            }
        }
        .onChange(of: host) { _, _ in gateway.cookies = [] }
        .onDisappear { browser.cancel() }
    }
}

struct LibraryView: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Environment(\.horizontalSizeClass) private var sizeClass
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
    @FocusState private var searchFocused: Bool
    @State private var results: [OutlineDocument] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var showSettings = false
    @State private var composing = false
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var visibility = NavigationSplitViewVisibility.all
    var visibleDocuments: [OutlineDocument] {
        let source = query.isEmpty ? (savedOnly ? workspace.saved : workspace.documents) : results
        return source.filter { collection == nil || $0.collectionId == collection }
    }
    private func sectionToggle(_ title: String, id: String) -> some View {
        Button {
            withAnimation {
                if workspace.expandedSections.contains(id) { workspace.expandedSections.remove(id) }
                else { workspace.expandedSections.insert(id) }
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: workspace.expandedSections.contains(id) ? "chevron.down" : "chevron.right")
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(workspace.expandedSections.contains(id) ? "Expanded" : "Collapsed")
            .accessibilityHint("Double-tap to expand or collapse this collection")
    }
    private func sidebarDocument(_ node: OutlineTreeNode, collectionID: String) -> OutlineDocument {
        workspace.documents.first(where: { $0.id == node.id }) ?? node.document(collectionID: collectionID)
    }
    private func collectionSection(_ collection: OutlineCollection) -> some View {
                        Section {
                            if workspace.expandedSections.contains(collection.id) {
                            if let nodes = workspace.trees[collection.id] {
                                ForEach(sidebarRows(nodes), id: \.node.id) { row in
                                    let document = sidebarDocument(row.node, collectionID: collection.id)
                                    HStack(spacing: 8) {
                                        if !row.node.children.isEmpty {
                                            Button {
                                                if !expandedNodes.insert(row.node.id).inserted { expandedNodes.remove(row.node.id) }
                                            } label: {
                                                Image(systemName: expandedNodes.contains(row.node.id) ? "chevron.down" : "chevron.right")
                                                    .frame(width: 44, height: 44)
                                            }.buttonStyle(.plain)
                                                .accessibilityLabel("Toggle children of " + row.node.title)
                                        }
                                        Button { openSidebarDocument(document) } label: {
                                            Label(row.node.title, systemImage: "doc.text").lineLimit(2)
                                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.leading, CGFloat(row.depth) * 16)
                                    .id("page-" + document.id)
                                    .listRowBackground(selected?.id == document.id ? palette.accent.opacity(0.15) : palette.surface)
                                    .contextMenu { Button("Keep beside", systemImage: "rectangle.split.2x1") { companion = document } }
                                }
                                if nodes.isEmpty { Text("No documents").foregroundStyle(.secondary) }
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
            sidebarScrollTarget = "page-" + selected.id
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
    private var sidebarContent: some View {
        ScrollViewReader { proxy in
            List {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your knowledge", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($searchFocused).submitLabel(.search)
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
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
                                Button { openSidebarDocument(document) } label: { Label(document.title, systemImage: "doc.badge.ellipsis") }.id("page-" + document.id)
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
                    if let searchError { Text(searchError).foregroundStyle(.red) }
                    ForEach(visibleDocuments) { document in
                        Button { openSidebarDocument(document) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc.text").foregroundStyle(.tint).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(document.title).font(.body.weight(.medium)).lineLimit(2)
                                    Text(workspace.collections.first { $0.id == document.collectionId }?.name ?? "Document").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                        }.id("page-" + document.id).contextMenu { Button("Keep beside", systemImage: "rectangle.split.2x1") { companion = document } }
                    }
                    if visibleDocuments.isEmpty && !searching && !workspace.busy {
                        ContentUnavailableView(savedOnly ? "Your reading shelf" : "No documents", systemImage: savedOnly ? "bookmark" : "magnifyingglass", description: Text(savedOnly ? "Save a document to read it here, even offline." : "Try another collection or search."))
                    }
                }
                }
            
                }.listRowBackground(palette.surface)
            }
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
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(sidebarScrollTarget, anchor: revealSearch ? .top : .center)
            }
            .refreshable { await workspace.refresh() }
            .toolbar {
                ToolbarItem(placement: sizeClass == .compact ? .topBarTrailing : .topBarLeading) {
                    avatarButton
                }.horizontalWhenAvailable()
                if sizeClass == .compact {
                    ToolbarItem(placement: .primaryAction) { searchButton }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New document", systemImage: "square.and.pencil") {
                            showSettings = false; composing = true; compactColumn = .detail
                        }
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
                    DuoReader(workspace: workspace, document: selected, companion: $companion, onNavigate: { selected = $0 })
                }
            }
            .appSurface()
            .toolbar {
                if !composing && !showSettings {
                    ToolbarItem(placement: .primaryAction) { searchButton }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New document", systemImage: "square.and.pencil") {
                            showSettings = false; composing = true; compactColumn = .detail
                        }.keyboardShortcut("n", modifiers: .command)
                    }
                }
            }
    }
    private var avatarButton: some View {
        Button { composing = false; showSettings = true; compactColumn = .detail } label: {
            if let avatar = workspace.avatar {
                Image(uiImage: avatar).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(Circle())
            } else { Image(systemName: "person.crop.circle").font(.title2) }
        }.accessibilityLabel("Settings for " + (workspace.profile?.name ?? workspace.name))
    }
}

private struct WorkspaceSettings: View {
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
                        if let avatar = workspace.avatar { Image(uiImage: avatar).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(Circle()) }
                        VStack(alignment: .leading) {
                            if let name = workspace.profile?.name { Text(name).font(.headline) }
                            Text(workspace.name).foregroundStyle(.secondary)
                        }
                    }
                }
                AppearanceSettings()
                Section {
                    Toggle("Work offline", isOn: $workspace.workOffline)
                    if workspace.pendingCount > 0 { Text("\(workspace.pendingCount) changes queued to sync") }
                    Picker("Sync offline", selection: $workspace.offlineMode) {
                        ForEach(OfflineMode.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { Task { await workspace.refresh() } }
                        .disabled(workspace.workOffline || workspace.syncing || workspace.busy)
                    if workspace.syncing { ProgressView("Syncing \(workspace.syncCompleted) of \(workspace.syncTotal)", value: Double(workspace.syncCompleted), total: Double(max(1, workspace.syncTotal))) }
                    Text("\(workspace.saved.count) pages available offline")
                    if let error = workspace.syncError { Text(error).foregroundStyle(.red) }
                } header: { Text("Offline") } footer: {
                    Text("Work offline pauses sync and queues changes on this device until you turn it off. Manual: sync individual pages using their download button. Pages I open: automatically save each page you read. Everything: sync all accessible pages. Saved pages update while the app is open and connected. Images and attachments still require a connection.")
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
