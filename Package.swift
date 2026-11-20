// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarginCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarginCore", targets: ["MarginCore"])],
    targets: [
        .target(name: "MarginCore", path: "Margin", exclude: ["Appearance.swift", "MarginApp.swift", "ReaderView.swift", "Workspace.swift", "ComposeView.swift", "SignInViews.swift", "DocumentEditor.swift", "Assets.xcassets", "Acknowledgements.txt"], sources: ["OutlineAPI.swift", "GatewayConfiguration.swift", "OAuthSession.swift"]),
        .testTarget(name: "MarginCoreTests", dependencies: ["MarginCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
