import SwiftUI
import MarkdownUI

struct DuoReader: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    let document: OutlineDocument?
    @Binding var companion: OutlineDocument?
    let onNavigate: (OutlineDocument) -> Void
    @State private var showReference = false
    var body: some View {
        GeometryReader { geometry in
            if let document {
                let wide = companion != nil && sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
                let paneWidth = max(0, wide ? (geometry.size.width - 1) / 2 : geometry.size.width)
                let mainVisible = wide || companion == nil || !showReference
                VStack(spacing: 0) {
                    if companion != nil && !wide {
                        Picker("Reading pane", selection: $showReference) {
                            Text("Document").tag(false)
                            Text("Reference").tag(true)
                        }.pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)
                    }
                    // Keep both readers alive as the available width changes.
                    // Folding or switching panes must not recreate their scroll views.
                    HStack(spacing: 0) {
                        ReaderView(workspace: workspace, original: document, isVisible: mainVisible, onPin: { self.companion = $0 }, onNavigate: onNavigate)
                            .frame(width: paneWidth)
                            .frame(width: mainVisible ? paneWidth : 0, alignment: .leading)
                            .clipped().allowsHitTesting(mainVisible).accessibilityHidden(!mainVisible)
                        Divider().frame(width: wide ? 1 : 0).clipped()
                        if let companion {
                            let referenceVisible = wide || showReference
                            VStack(spacing: 0) {
                                referenceHeader
                                ReaderView(workspace: workspace, original: companion, isVisible: referenceVisible, onPin: nil, onNavigate: { self.companion = $0 })
                            }
                            .frame(width: paneWidth)
                            .frame(width: referenceVisible ? paneWidth : 0, alignment: .leading)
                            .clipped().allowsHitTesting(referenceVisible).accessibilityHidden(!referenceVisible)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "rectangle.split.2x1").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(.tint).accessibilityHidden(true)
                        Text("Space for a second thought.").font(.system(.largeTitle, design: .serif)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text("Choose a document to begin. Keep a reference beside it as you explore.").foregroundStyle(palette.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.padding(32).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.background(palette.background)
            }
        }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .onChange(of: document?.id) { _, _ in showReference = false }
    }
    private var referenceHeader: some View {
        HStack {
            Label("REFERENCE", systemImage: "pin.fill").font(.caption.weight(.semibold)).tracking(1)
            Spacer()
            Button("Close reference", systemImage: "xmark") { companion = nil; showReference = false }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.foregroundStyle(palette.secondary).padding(.horizontal, 16).frame(minHeight: 50).background(palette.surface)
    }
}

struct ReaderView: View {
    private struct LoadID: Equatable {
        let document: String
        let session: UUID
    }
    @Bindable var workspace: Workspace
    let original: OutlineDocument
    let isVisible: Bool
    let onPin: ((OutlineDocument) -> Void)?
    let onNavigate: (OutlineDocument) -> Void
    @State private var loaded: OutlineDocument?
    @State private var activeLoad: UUID?
    private var loading: Bool { activeLoad != nil }
    @State private var error: String?
    @State private var offline = false
    @State private var syncingPage = false
    @AccessibilityFocusState private var titleFocused: Bool
    // Editing is an explicit, document-scoped session. Selecting a document
    // always opens the reader, including after saving an edit.
    @State private var editingDocument: OutlineDocument?
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @AppStorage("readingFontSize") private var fontSize = 18.0
    var document: OutlineDocument { loaded?.id == original.id ? loaded! : original }
    var isSaved: Bool { workspace.saved.contains { $0.id == document.id } }
    var documentURL: URL? {
        guard let base = workspace.api?.baseURL, let path = document.url,
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host == base.host else { return nil }
        return url
    }
    var body: some View {
        ZStack {
            readingContent
                .foregroundStyle(palette.foreground)
                .background(palette.background)
                .tint(palette.accent)
                .environment(\.colorScheme, palette.scheme ?? colorScheme)
                .opacity(editingDocument == nil ? 1 : 0)
                .allowsHitTesting(editingDocument == nil)
                .accessibilityHidden(editingDocument != nil)
            if let editing = editingDocument {
                DocumentEditor(workspace: workspace, original: editing, isVisible: isVisible, onSaved: { updated in
                    if updated.id == original.id { loaded = updated }
                }, onClose: { editingDocument = nil; titleFocused = true })
                .id(editing.id)
                .background(palette.background)
            }
        }
        .background(palette.background)
        .task(id: LoadID(document: original.id, session: workspace.readerSessionID)) {
            if loaded?.id != original.id { loaded = nil }
            await load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ["editor", "preview"].contains(ProcessInfo.processInfo.environment["MARGIN_TEST_SCREEN"] ?? "") { editingDocument = document }
            #endif
        }
        .onChange(of: isVisible) { _, visible in titleFocused = visible }
        .announceAccessibilityChanges(isVisible ? error : nil)
        .onChange(of: original.id, initial: true) { _, _ in
            editingDocument = nil
            titleFocused = isVisible && onPin != nil
        }
        .toolbar {
            if onPin != nil && editingDocument == nil && isVisible {
                ToolbarItemGroup(placement: .primaryAction) { readerActions }
            }
        }
    }

    private var readingContent: some View {
        VStack(spacing: 0) {
            if onPin == nil {
                HStack { readerActions }.buttonStyle(ReaderActionStyle()).padding(.horizontal, 12).background(palette.surface)
            }
            if loading { ProgressView("Loading document").controlSize(.small) }
            if offline { Label("Saved copy", systemImage: "wifi.slash").font(.caption).foregroundStyle(palette.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(workspace.collections.first { $0.id == document.collectionId }?.name.uppercased() ?? "DOCUMENT")
                        .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.tint)
                    Text(document.title).font(.system(.largeTitle, design: .serif, weight: .medium)).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                        .accessibilityIdentifier("document-heading")
                    if let error {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(error, systemImage: "exclamationmark.circle").font(.callout)
                            Button("Try again") { Task { await load() } }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let text = document.text {
                        MarkdownBody(text: DocumentReading.body(text, title: document.title), fontSize: fontSize, baseURL: workspace.api?.baseURL)
                            .environment(\.openURL, OpenURLAction { url in
                                let resolved = URL(string: url.relativeString, relativeTo: workspace.api?.baseURL)?.absoluteURL
                                guard let resolved, ["https", "http"].contains(resolved.scheme ?? "") else { return .discarded }
                                if let api = workspace.api, GatewayConfiguration.sameOrigin(resolved, api.baseURL) {
                                    Task {
                                        do {
                                            let response: Envelope<OutlineDocument> = try await api.request("documents.info", body: ["id": resolved.lastPathComponent])
                                            onNavigate(response.data)
                                        } catch { self.error = error.localizedDescription }
                                    }
                                } else { openURL(resolved) }
                                return .handled
                            })
                    } else if loading { ProgressView("Opening document…") }
                    else { Text("Document content is unavailable. Try refreshing.").foregroundStyle(palette.secondary) }
                }.padding(28).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
            }.refreshable { await load() }.id(original.id)
        }
    }

    @ViewBuilder private var readerActions: some View {
                if let onPin { Button("Keep beside", systemImage: "rectangle.split.2x1") { onPin(document) }.labelStyle(.iconOnly) }
                Button(workspace.workOffline ? "Queue page download" : (isSaved ? "Sync page again" : "Sync page offline"), systemImage: isSaved ? "checkmark.circle" : "arrow.down.circle") {
                    syncingPage = true
                    Task {
                        do { try await workspace.syncPage(document); AccessibilityNotification.Announcement(workspace.workOffline ? "Page download queued" : "Page saved for offline reading").post() }
                        catch { self.error = error.localizedDescription }
                        syncingPage = false
                    }
                }.labelStyle(.iconOnly).disabled(loading || syncingPage)
                    .accessibilityActions {
                        if isSaved {
                            Button("Remove offline copy") {
                                do { try workspace.removeOffline(document) } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                    .contextMenu {
                        if isSaved {
                            Button("Remove offline copy", systemImage: "trash", role: .destructive) {
                                do { try workspace.removeOffline(document) } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                Button("Edit", systemImage: "square.and.pencil") { editingDocument = document }
                    .accessibilityLabel("Edit document")
                    .disabled(document.text == nil || loading)
                if let url = documentURL {
                    ShareLink(item: url).labelStyle(.iconOnly)

                }
    }

    private func load() async {
        let session = workspace.readerSessionID
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        activeLoad = requestID
        error = nil; offline = false
        defer { if activeLoad == requestID { activeLoad = nil } }
        do {
            let fresh = try await workspace.load(original)
            try Task.checkCancellation()
            guard activeLoad == requestID, workspace.readerSessionID == session else { return }
            loaded = fresh; offline = workspace.workOffline
            if isSaved { try workspace.saveOffline(fresh) }
        } catch is CancellationError { } catch {
            guard !Task.isCancelled, activeLoad == requestID, workspace.readerSessionID == session else { return }
            if let saved = workspace.saved.first(where: { $0.id == original.id }) {
                loaded = saved; offline = true
            }
            self.error = error.localizedDescription
        }
    }
}

struct ReaderActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct MarkdownBody: View {
    let text: String
    let fontSize: Double
    let baseURL: URL?
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @ScaledMetric private var scale = 1.0
    @Environment(\.legibilityWeight) private var legibilityWeight
    private func accessibleHeading(_ label: MarkdownUI.BlockConfiguration.Label, size: Double) -> some View {
        label.markdownTextStyle { FontWeight(.semibold); FontSize(.em(size)); ForegroundColor(palette.foreground) }
            .accessibilityAddTraits(.isHeader)
            .markdownMargin(top: 24, bottom: 16)
    }
    var body: some View {
        Markdown(text, baseURL: baseURL, imageBaseURL: baseURL)
            .markdownTheme(Theme.gitHub
                .text { ForegroundColor(palette.foreground); BackgroundColor(nil) }
                .link { ForegroundColor(palette.accent); UnderlineStyle(.single) }
                .code { FontFamilyVariant(.monospaced); BackgroundColor(palette.surface) }
                .heading1 { accessibleHeading($0.label, size: 2) }
                .heading2 { accessibleHeading($0.label, size: 1.5) }
                .heading3 { accessibleHeading($0.label, size: 1.25) }
                .heading4 { accessibleHeading($0.label, size: 1) }
                .heading5 { accessibleHeading($0.label, size: 1) }
                .heading6 { accessibleHeading($0.label, size: 1) }
                .blockquote { configuration in
                    configuration.label.padding(.leading, 16)
                        .overlay(alignment: .leading) { Rectangle().fill(palette.accent).frame(width: 3).accessibilityHidden(true) }
                        .markdownTextStyle { ForegroundColor(palette.foreground) }
                }
                .codeBlock { configuration in
                    ScrollView(.horizontal) {
                        configuration.label.markdownTextStyle { FontFamilyVariant(.monospaced) }.padding(16)
                    }.background(palette.surface).markdownMargin(top: 0, bottom: 16)
                }
                .table { configuration in
                    ScrollView(.horizontal) {
                        configuration.label
                            .markdownTableBorderStyle(.init(color: palette.secondary))
                            .markdownTableBackgroundStyle(.alternatingRows(palette.background, palette.surface))
                    }.markdownMargin(top: 0, bottom: 16)
                }
                .taskListMarker { configuration in
                    Image(systemName: configuration.isCompleted ? "checkmark.square" : "square")
                        .foregroundStyle(palette.foreground)
                        .accessibilityLabel(configuration.isCompleted ? "Completed" : "Not completed")
                })
            .markdownTextStyle {
                FontSize(fontSize * scale)
                if legibilityWeight == .bold { FontWeight(.semibold) }
            }
            .textSelection(.enabled)
    }
}
