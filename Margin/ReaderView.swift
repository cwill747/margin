import SwiftUI
import MarkdownUI

struct DuoReader: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    let document: OutlineDocument?
    @Binding var companion: OutlineDocument?
    let onNavigate: (OutlineDocument) -> Void
    @State private var showReference = false
    var body: some View {
        GeometryReader { geometry in
            if let document {
                let wide = companion != nil && geometry.size.width >= 760
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
                        ReaderView(workspace: workspace, original: document, onPin: { self.companion = $0 }, onNavigate: onNavigate)
                            .frame(width: paneWidth)
                            .frame(width: mainVisible ? paneWidth : 0, alignment: .leading)
                            .clipped().allowsHitTesting(mainVisible).accessibilityHidden(!mainVisible)
                        Divider().frame(width: wide ? 1 : 0).clipped()
                        if let companion {
                            let referenceVisible = wide || showReference
                            VStack(spacing: 0) {
                                referenceHeader
                                ReaderView(workspace: workspace, original: companion, onPin: nil, onNavigate: { self.companion = $0 })
                            }
                            .frame(width: paneWidth)
                            .frame(width: referenceVisible ? paneWidth : 0, alignment: .leading)
                            .clipped().allowsHitTesting(referenceVisible).accessibilityHidden(!referenceVisible)
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "rectangle.split.2x1").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(.tint)
                    Text("Space for a second thought.").font(.system(.largeTitle, design: .serif)).multilineTextAlignment(.center)
                    Text("Choose a document to begin.\nKeep a reference beside it as you explore.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.background)
            }
        }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .onChange(of: document?.id) { _, _ in showReference = false }
    }
    private var referenceHeader: some View {
        HStack {
            Label("REFERENCE", systemImage: "pin.fill").font(.caption.weight(.semibold)).tracking(1)
            Spacer()
            Button("Close", systemImage: "xmark") { companion = nil; showReference = false }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.foregroundStyle(.secondary).padding(.horizontal, 16).frame(minHeight: 50).background(palette.surface)
    }
}

struct ReaderView: View {
    @Bindable var workspace: Workspace
    let original: OutlineDocument
    let onPin: ((OutlineDocument) -> Void)?
    let onNavigate: (OutlineDocument) -> Void
    @State private var loaded: OutlineDocument?
    @State private var loading = false
    @State private var error: String?
    @State private var offline = false
    @State private var syncingPage = false
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
                DocumentEditor(workspace: workspace, original: editing, onSaved: { updated in
                    if updated.id == original.id { loaded = updated }
                }, onClose: { editingDocument = nil })
                .id(editing.id)
                .background(palette.background)
            }
        }
        .background(palette.background)
        .task(id: original.id) { loaded = nil; await load() }
        .onChange(of: original.id) { _, _ in editingDocument = nil }
        .toolbar {
            if onPin != nil && editingDocument == nil {
                ToolbarItemGroup(placement: .primaryAction) { readerActions }
            }
        }
    }

    private var readingContent: some View {
        VStack(spacing: 0) {
            if onPin == nil {
                HStack { readerActions }.buttonStyle(ReaderActionStyle()).padding(.horizontal, 12).background(palette.surface)
            }
            if loading { ProgressView().controlSize(.small) }
            if offline { Label("Saved copy", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(workspace.collections.first { $0.id == document.collectionId }?.name.uppercased() ?? "DOCUMENT")
                        .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.tint)
                    Text(document.title).font(.system(.largeTitle, design: .serif, weight: .medium)).textSelection(.enabled)
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
                    else { Text("Document content is unavailable. Try refreshing.").foregroundStyle(.secondary) }
                }.padding(28).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
            }.refreshable { await load() }.id(original.id)
        }
    }

    @ViewBuilder private var readerActions: some View {
                if let onPin { Button("Keep beside", systemImage: "rectangle.split.2x1") { onPin(document) }.labelStyle(.iconOnly) }
                Button(isSaved ? "Sync page again" : "Sync page offline", systemImage: isSaved ? "checkmark.circle" : "arrow.down.circle") {
                    syncingPage = true
                    Task {
                        do { try await workspace.syncPage(document) }
                        catch { self.error = error.localizedDescription }
                        syncingPage = false
                    }
                }.labelStyle(.iconOnly).disabled(loading || syncingPage)
                    .contextMenu {
                        if isSaved {
                            Button("Remove offline copy", systemImage: "trash", role: .destructive) {
                                do { try workspace.removeOffline(document) } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                Button("Edit", systemImage: "square.and.pencil") { editingDocument = document }
                    .accessibilityLabel("Edit document")
                    .disabled(document.text == nil || loading || offline)
                if let url = documentURL {
                    ShareLink(item: url).labelStyle(.iconOnly)

                }
    }

    private func load() async {
        loading = true; error = nil; offline = false
        defer { loading = false }
        do {
            let fresh = try await workspace.load(original)
            try Task.checkCancellation()
            loaded = fresh
            if isSaved { try workspace.saveOffline(fresh) }
        } catch is CancellationError { } catch {
            guard !Task.isCancelled else { return }
            if let saved = workspace.saved.first(where: { $0.id == original.id }) {
                loaded = saved; offline = true
            }
            self.error = error.localizedDescription
        }
    }
}

private struct ReaderActionStyle: ButtonStyle {
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
    var body: some View {
        Markdown(text, baseURL: baseURL, imageBaseURL: baseURL)
            .markdownTheme(Theme.gitHub
                .text { ForegroundColor(palette.foreground); BackgroundColor(nil) }
                .link { ForegroundColor(palette.accent); UnderlineStyle(.single) })
            .markdownTextStyle { FontSize(fontSize * scale) }
            .textSelection(.enabled)
    }
}
