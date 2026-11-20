import SwiftUI

struct AppearanceSettings: View {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    @AppStorage("readingFontSize") private var fontSize = 18.0
    var body: some View {
        Section {
            Picker("Color theme", selection: $palette) {
                ForEach(ReadingPalette.allCases) { Text($0.title).tag($0) }
            }
            Stepper(value: $fontSize, in: 14...30, step: 2) {
                LabeledContent("Text size", value: "\(Int(fontSize)) pt")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Space for a second thought.").font(.system(.title2, design: .serif))
                MarkdownBody(text: "Your knowledge, comfortably within reach. Keep a [reference](https://example.com) beside what you’re reading.", fontSize: fontSize, baseURL: nil)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.foreground).background(palette.background, in: RoundedRectangle(cornerRadius: 12))
            .environment(\.colorScheme, palette.scheme ?? colorScheme)
            .environment(\.openURL, OpenURLAction { _ in .handled })
            .accessibilityElement(children: .combine)
        } header: {
            Label("Appearance", systemImage: "textformat.size")
        } footer: {
            Text("Color themes apply throughout Margin. System follows your device appearance. Text size applies to document reading and also follows your device’s accessibility size.").font(.footnote).accessibilityIdentifier("appearance-help")
        }
    }
    @Environment(\.colorScheme) private var colorScheme
}

/// Shared surfaces for every app-owned screen. Keep the stored key stable.
struct AppSurface: ViewModifier {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .all)
            .foregroundStyle(palette.foreground)
            .tint(palette.accent)
            .backgroundStyle(palette.background)
            .scrollContentBackground(palette == .system ? .automatic : .hidden)
            .background(palette.background.ignoresSafeArea())
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(palette == .system ? .automatic : .visible, for: .navigationBar)
    }
}

extension View {
    func appSurface() -> some View { modifier(AppSurface()) }
}

extension View {
    func announceAccessibilityChanges(_ message: String?) -> some View {
        onChange(of: message) { _, value in
            if let value, !value.isEmpty { AccessibilityNotification.Announcement(value).post() }
        }
    }
}
