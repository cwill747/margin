import SwiftUI

extension Color {
    init(rgb: UInt32, highContrast: UInt32? = nil) {
        self.init(uiColor: UIColor { traits in
            let value = traits.accessibilityContrast == .high ? (highContrast ?? rgb) : rgb
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
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
        case .paper: Color(rgb: 0x253C37, highContrast: 0x000000)
        case .sepia: Color(rgb: 0x493B2C, highContrast: 0x000000)
        case .night: Color(rgb: 0xE5EAE2, highContrast: 0xFFFFFF)
        }
    }
    var accent: Color {
        if self == .system {
            return Color(uiColor: UIColor { traits in
                if traits.accessibilityContrast == .high { return traits.userInterfaceStyle == .dark ? .white : UIColor(red: 18/255, green: 61/255, blue: 53/255, alpha: 1) }
                return traits.userInterfaceStyle == .dark
                    ? UIColor(red: 167/255, green: 205/255, blue: 187/255, alpha: 1)
                    : UIColor(red: 41/255, green: 102/255, blue: 94/255, alpha: 1)
            })
        }
        return self == .night ? Color(rgb: 0xA7CDBB, highContrast: 0xFFFFFF) : Color(rgb: 0x29665E, highContrast: 0x123D35)
    }
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

// Custom palettes use their foreground for secondary text instead of system gray,
// which is designed for system surfaces and can lose contrast on sepia/paper.
extension ReadingPalette {
    var secondary: Color { self == .system ? .primary : foreground }
}
