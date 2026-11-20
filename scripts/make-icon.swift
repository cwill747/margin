import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Margin: paired pages with one quiet margin. iOS supplies the corner mask.
let context = CGContext(data: nil, width: 1024, height: 1024,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func fill(_ hex: UInt32, rect: CGRect, radius: CGFloat = 0) {
    context.setFillColor(CGColor(red: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1))
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
fill(0x17352F, rect: CGRect(x: 0, y: 0, width: 1024, height: 1024))
fill(0xA7CDBB, rect: CGRect(x: 196, y: 244, width: 288, height: 536), radius: 32)
fill(0xFAF8F2, rect: CGRect(x: 540, y: 244, width: 288, height: 536), radius: 32)
fill(0x29665E, rect: CGRect(x: 592, y: 348, width: 20, height: 328), radius: 10)
let url = URL(fileURLWithPath: "Margin/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Could not write app icon")
