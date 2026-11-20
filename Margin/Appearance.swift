import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

enum ReadingPalette: String, CaseIterable, Identifiable {
    case system, paper, sepia, night
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .night: .dark; default: .light }
    }
    var background: Color {
        switch self {
        case .system: Color(uiColor: .systemBackground)
        case .paper: Color(rgb: 0xFAF8F2)
        case .sepia: Color(rgb: 0xEFE2C6)
        case .night: Color(rgb: 0x172321)
        }
    }
    var foreground: Color {
        switch self {
        case .system: .primary
        case .paper: Color(rgb: 0x253C37)
        case .sepia: Color(rgb: 0x493B2C)
        case .night: Color(rgb: 0xE5EAE2)
        }
    }
    var accent: Color {
        if self == .system {
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 167/255, green: 205/255, blue: 187/255, alpha: 1)
                    : UIColor(red: 41/255, green: 102/255, blue: 94/255, alpha: 1)
            })
        }
        return self == .night ? Color(rgb: 0xA7CDBB) : Color(rgb: 0x29665E)
    }
}

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
            Text("Color themes apply throughout Margin. System follows your device appearance. Text size applies to document reading and also follows your device’s accessibility size.")
        }
    }
    @Environment(\.colorScheme) private var colorScheme
}

/// Shared surfaces for every app-owned screen. Keep the stored key stable.
struct AppSurface: ViewModifier {
    @AppStorage("readingPalette") private var palette: ReadingPalette = .system
    func body(content: Content) -> some View {
        content
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

extension ReadingPalette {
    var surface: Color {
        switch self {
        case .system: Color(uiColor: .secondarySystemGroupedBackground)
        case .paper: Color(rgb: 0xF1EEE5)
        case .sepia: Color(rgb: 0xE6D6B6)
        case .night: Color(rgb: 0x22332F)
        }
    }
}
