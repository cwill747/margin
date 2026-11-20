import XCTest
import SwiftUI

// Compile the app's actual palette source into this target, so color changes
// cannot drift from a duplicate list of RGB constants in the tests.
@MainActor
final class PaletteContrastTests: XCTestCase {
    func testTextAndLinksMeetContrastInEveryAppearance() throws {
        for palette in ReadingPalette.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection {
                        $0.userInterfaceStyle = style
                        $0.accessibilityContrast = contrast
                    }
                    for foreground in [palette.foreground, palette.secondary, palette.accent] {
                        for background in [palette.background, palette.surface] {
                            let a = try luminance(foreground, traits: traits)
                            let b = try luminance(background, traits: traits)
                            let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                "\(palette) style=\(style.rawValue) contrast=\(contrast.rawValue): \(ratio):1")
                        }
                    }
                }
            }
        }
    }

    private func luminance(_ color: Color, traits: UITraitCollection) throws -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(a, 1, "Contrast checks require opaque palette colors")
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
