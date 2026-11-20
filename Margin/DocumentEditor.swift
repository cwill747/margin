import SwiftUI

struct DocumentEditor: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    let original: OutlineDocument
    let isVisible: Bool
    let onSaved: (OutlineDocument) -> Void
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var text = ""
    @State private var revision: Int?
    @State private var collection: String?
    @State private var publish = false
    @State private var preview = false
    @State private var saving = false
    @State private var ready = false
    @State private var error: String?
    @State private var confirmClose = false
    @State private var editor = EditorCommands()
    @State private var showLink = false
    @State private var link = "https://"
    init(workspace: Workspace, original: OutlineDocument, isVisible: Bool,
         onSaved: @escaping (OutlineDocument) -> Void, onClose: @escaping () -> Void) {
        self.workspace = workspace; self.original = original; self.isVisible = isVisible
        self.onSaved = onSaved; self.onClose = onClose
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.environment["MARGIN_TEST_SCREEN"] == "preview" {
            _preview = State(initialValue: true)
        }
        #endif
    }
    private var recoveryURL: URL { URL.applicationSupportDirectory.appendingPathComponent("edit-\(original.id).json") }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView { editorHeader }.frame(maxHeight: 200).scrollEdgeEffectHidden()
                } else { editorHeader }
                if preview {
                    ScrollView { MarkdownBody(text: text, fontSize: 18, baseURL: workspace.api?.baseURL).padding() }.scrollEdgeEffectHidden()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            format("Bold", "bold", "**", "**").keyboardShortcut("b", modifiers: .command)
                            format("Italic", "italic", "_", "_").keyboardShortcut("i", modifiers: .command)
                            format("Strikethrough", "strikethrough", "~~", "~~")
                            format("Heading", "textformat.size", "## ", "")
                            format("Bullet list", "list.bullet", "- ", "")
                            format("Numbered list", "list.number", "1. ", "")
                            format("Checklist", "checklist", "- [ ] ", "")
                            format("Quote", "text.quote", "> ", "")
                            format("Code", "chevron.left.forwardslash.chevron.right", "`", "`")
                            Button("Link", systemImage: "link") { showLink = true }.labelStyle(.iconOnly)
                            Button("Table", systemImage: "tablecells") { editor.insert("\n| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n") }.labelStyle(.iconOnly)
                            Button("Divider", systemImage: "minus") { editor.insert("\n\n---\n\n") }.labelStyle(.iconOnly)
                            Button("Undo", systemImage: "arrow.uturn.backward") { editor.view?.undoManager?.undo() }.labelStyle(.iconOnly)
                            Button("Redo", systemImage: "arrow.uturn.forward") { editor.view?.undoManager?.redo() }.labelStyle(.iconOnly)
                        }.buttonStyle(ReaderActionStyle()).controlSize(.regular).padding(.horizontal).padding(.vertical, 8)
                    }
                    NativeDocumentText(text: $text, commands: editor).padding(.horizontal, 12)
                }
            }
            .appSurface()
            .toolbar {
                if isVisible {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Read", systemImage: "chevron.left") {
                            if hasChanges { confirmClose = true } else { onClose() }
                        }.disabled(saving)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(preview ? "Write" : "Preview", systemImage: preview ? "pencil" : "eye") { editor.view?.resignFirstResponder(); preview.toggle() }.disabled(saving)
                    }
                    ToolbarItem(placement: .topBarPinnedTrailing) {
                        Button(saving ? "Saving…" : "Save", systemImage: "checkmark") { save() }
                            .disabled(saving || !ready || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            .disabled(saving)
            .confirmationDialog("Keep your changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Keep on this device") { onClose() }
                Button("Discard changes", role: .destructive) { do { if FileManager.default.fileExists(atPath: recoveryURL.path) { try FileManager.default.removeItem(at: recoveryURL) }; onClose() } catch { self.error = error.localizedDescription } }
                Button("Continue editing", role: .cancel) { }
            }
            .alert("Insert link", isPresented: $showLink) {
                TextField("https://…", text: $link).textInputAutocapitalization(.never)
                Button("Insert") {
                    guard let url = URL(string: link), ["https", "http"].contains(url.scheme ?? "") else { error = "Enter an HTTP or HTTPS link."; return }
                    editor.wrap("[", "](\(url.absoluteString))")
                }
                Button("Cancel", role: .cancel) { }
            }
            .task {
                guard !ready else { return }
                title = original.title; text = original.text ?? ""; revision = original.revision; collection = original.collectionId
                if let data = try? Data(contentsOf: recoveryURL), let draft = try? JSONDecoder().decode(EditRecovery.self, from: data) {
                    title = draft.title; text = draft.text; revision = draft.revision; collection = draft.collection; publish = draft.publish
                }
                ready = true; titleFocused = true
            }
            .announceAccessibilityChanges(error)
            .onChange(of: EditRecovery(title: title, text: text, revision: revision, collection: collection, publish: publish)) { _, value in
                guard ready else { return }
                do {
                    try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(value).write(to: recoveryURL, options: [.atomic, .completeFileProtection])
                    var url = recoveryURL; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try url.setResourceValues(flags)
                } catch { self.error = "Could not save local recovery: \(error.localizedDescription)" }
            }
        }
    }
    private var editorHeader: some View {
        VStack(spacing: 0) {
            TextField("Document title", text: $title, axis: .vertical).font(.system(.title2, design: .serif)).fixedSize(horizontal: false, vertical: true).padding().accessibilityLabel("Document title").accessibilityFocused($titleFocused)
            if original.publishedAt == nil {
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
                    Picker("Collection", selection: $collection) {
                        Text("Private draft").tag(String?.none)
                        ForEach(workspace.collections) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("Publish", isOn: $publish).disabled(collection == nil)
                }.padding(.horizontal)
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(palette.foreground).font(.callout).padding().textSelection(.enabled) }
        }
    }
    private var hasChanges: Bool {
        title != original.title || text != (original.text ?? "") || publish || collection != original.collectionId
    }
    private func format(_ title: String, _ icon: String, _ prefix: String, _ suffix: String) -> some View {
        Button(title, systemImage: icon) { editor.wrap(prefix, suffix) }.labelStyle(.iconOnly)
    }
    private func save() {
        saving = true; error = nil
        Task {
            do {
                let updated = try await workspace.update(original, title: title, text: text, revision: revision, publish: publish, collection: collection)
                // A cache-cleanup failure must never make a successful save look retryable.
                try? FileManager.default.removeItem(at: recoveryURL)
                onSaved(updated); onClose(); AccessibilityNotification.Announcement("Document saved").post()
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

struct EditRecovery: Codable, Equatable {
    var title: String
    var text: String
    var revision: Int?
    var collection: String?
    var publish: Bool
}

@MainActor @Observable final class EditorCommands {
    weak var view: UITextView?
    func insert(_ value: String) { wrap(value, "", replacing: true) }
    func wrap(_ prefix: String, _ suffix: String, replacing: Bool = false) {
        guard let view else { return }
        view.becomeFirstResponder()
        let range = view.selectedRange
        let selected = (view.text as NSString).substring(with: range)
        guard let start = view.position(from: view.beginningOfDocument, offset: range.location),
              let end = view.position(from: start, offset: range.length), let target = view.textRange(from: start, to: end) else { return }
        view.replace(target, withText: prefix + (replacing ? "" : selected) + suffix)
        view.selectedRange = NSRange(location: range.location + prefix.utf16.count, length: replacing ? 0 : range.length)
        view.delegate?.textViewDidChange?(view)
    }
}

struct NativeDocumentText: UIViewRepresentable {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Binding var text: String
    let commands: EditorCommands
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body); view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear; view.smartDashesType = .no; view.smartQuotesType = .no; view.smartInsertDeleteType = .no
        view.autocorrectionType = .no; view.accessibilityLabel = "Document content"; view.delegate = context.coordinator
        commands.view = view
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        view.textColor = UIColor(palette.foreground)
        view.tintColor = UIColor(palette.accent)
        context.coordinator.text = $text; commands.view = view
        if view.text != text { view.text = text }
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        view.resignFirstResponder()
        view.accessibilityElementsHidden = true
        view.delegate = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}
