# Developing Margin

Margin is a native SwiftUI app for iPhone and iPad mini. Web views are reserved for sign-in; Xcode resolves the pinned MarkdownUI package for native Markdown rendering.

## Build locally

Open `Margin.xcodeproj` in Xcode 27.1 or newer, with the iOS 27.1 or newer SDK for full-screen Duo support. Select the iPhone Duo or iPad mini simulator and run the Margin scheme. The deployment target is iOS 27. Use **Explore a sample workspace** to try the interface without credentials.

Apple SDKs and signing use the installed Xcode toolchain.

```sh
swift test
xcodebuild -project Margin.xcodeproj -scheme Margin \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Margin.xcodeproj -scheme Margin \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

The project uses development team `5XZ5XQ2F3F` and bundle ID `us.cwill.margin`. An Apple development certificate, working Xcode account, and provisioning profile are required for a device build. Configure your own development team when building under another Apple account.

## Verification

Run `swift test` and a local Xcode build before pushing.

Core tests cover API pagination and redirects, gateway header isolation, session cookies, OAuth PKCE, revision-checked patches, title presentation, and offline hierarchy serialization.

The app has run against a real workspace on the iOS 27.2 Duo simulator. Earlier signed device builds passed automatic provisioning and `codesign --verify --deep --strict`; physical-device installation remains unverified. Real-workspace and physical-device validation remain required before release.

Simulator builds must keep code signing enabled. Disabling signing removes the application-identifier entitlement and makes Keychain writes fail with OSStatus -34018. Debug builds support `--verify-keychain` to test a temporary write/read/delete without touching saved credentials.

Before release, inspect the icon at home-screen size and check headings, links, code, tables, quotes, and paired reading in every palette with Dynamic Type and VoiceOver.

## Implementation notes

- The Xcode project, scheme, target, source folder, and app entry point use Margin. The Swift package is MarginCore.
- The bundle ID is `us.cwill.margin` and the OAuth callback is `us.cwill.margin://oauth/callback`. Keychain service identifiers and storage paths retain their existing values. Existing Outline OAuth registrations must use the new callback URI.
- OAuth validates callback state, exchanges codes with an S256 PKCE verifier, and refreshes expiring tokens. No OAuth client secret is embedded in the app.
- Offline caches use file protection and are excluded from backups.
- Paired reading uses side-by-side panes when the detail area is at least 760 points wide, and a document/reference switcher below that width.

See the [branding guide](BRANDING.md) for visual specifications and icon generation, and the [Outline API reference](https://www.getoutline.com/developers) for API documentation.
