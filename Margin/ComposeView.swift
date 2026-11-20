import SwiftUI

struct ComposeView: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Bindable var workspace: Workspace
    let onCreated: (OutlineDocument) -> Void
    let onClose: () -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var collection: String?
    @State private var publish = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var restored = false
    @FocusState private var focusTitle: Bool
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Group {
                Section {
                    TextField("Title", text: $title, prompt: Text("Title").foregroundStyle(palette.secondary), axis: .vertical).font(.title2).focused($focusTitle).accessibilityLabel("Document title")
                    Picker("Collection", selection: $collection) {
                        Text("Private draft").tag(String?.none)
                        ForEach(workspace.collections) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    MarkdownEditor(text: $text).frame(minHeight: 260)
                } header: { Text("Markdown").font(.headline) }
                Section { Toggle("Publish to collection", isOn: $publish).disabled(collection == nil) }
                if let error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(palette.foreground) } }
            
                }.listRowBackground(palette.surface)
            }
            .appSurface()
            .navigationTitle("New document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if title.isEmpty && text.isEmpty { onClose() } else { confirmDiscard = true }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button(saving ? "Creating…" : (publish ? "Publish" : "Create draft"), systemImage: "checkmark") {
                        saving = true; error = nil
                        Task {
                            do {
                                let document = try await workspace.create(title: title, text: text, collection: collection, publish: publish)
                                do { try workspace.storeDraft(LocalDraft()) }
                                catch { workspace.error = "Document created, but the local draft could not be cleared: \(error.localizedDescription)" }
                                onCreated(document); onClose(); AccessibilityNotification.Announcement("Document created").post()
                            } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Discard this draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Keep draft for later") { onClose() }
                Button("Discard", role: .destructive) {
                    do { try workspace.storeDraft(LocalDraft()); onClose() }
                    catch { self.error = error.localizedDescription }
                }
                Button("Keep writing", role: .cancel) { }
            }
            .task {
                guard !restored else { return }
                title = workspace.draft.title; text = workspace.draft.text; collection = workspace.draft.collection
                restored = true; focusTitle = true
            }
            .announceAccessibilityChanges(error)
            .onChange(of: LocalDraft(title: title, text: text, collection: collection)) { _, draft in
                guard restored else { return }
                do { try workspace.storeDraft(draft) }
                catch { self.error = "Could not save this draft on your device: \(error.localizedDescription)" }
            }
        }
    }
}

// Markdown delimiters must survive typing unchanged; smart quotes and dashes
// can silently turn valid code, tables, and front matter into different text.
private struct MarkdownEditor: UIViewRepresentable {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @Binding var text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.autocorrectionType = .no
        view.accessibilityLabel = "Document text"
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        view.textColor = UIColor(palette.foreground)
        view.tintColor = UIColor(palette.accent)
        context.coordinator.text = $text
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
