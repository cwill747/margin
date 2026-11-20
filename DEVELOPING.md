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

## TestFlight CLI and agent skill

Use the installed Xcode toolchain; no Fastlane or additional package installation is needed. Create the App Store Connect app record for `us.cwill.margin` first, and use an Apple Developer account with permission to upload builds and manage the required signing assets. Sign into Xcode Settings → Accounts, or export all three API-key variables:

```sh
export ASC_KEY_PATH="$HOME/.private_keys/AuthKey_YOUR_KEY_ID.p8"
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
```

Keep the private key outside the repository. These variables use an App Store Connect **team API key**; individual keys without an issuer ID are not supported by this wrapper.

```sh
swift test
# Choose an unused build number greater than the last upload for this version.
scripts/testflight archive 2
scripts/testflight upload build/testflight/2/Margin.xcarchive
```

`archive` performs a signed Release device archive with automatic provisioning. It overrides the build number only for that build, preserves the project's marketing version, and refuses to overwrite an existing build directory. Archives and logs live under ignored `build/testflight/`. A failed archive leaves its logs for diagnosis; inspect it before removing the directory or selecting a new build number.

`upload` uploads the specified archive directly with Xcode's `app-store-connect` distribution method. Automatic build-number management is disabled so the uploaded number matches the archive. Each attempt retains its export options and upload log beside the archive. On an ambiguous failure, check App Store Connect before retrying. Apple must process the build; export compliance, tester groups, and any external Beta App Review remain in App Store Connect. Uploading does not publish an App Store release. See [Apple's upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

The shared skill lives in `.agents/skills/testflight/SKILL.md`, a project skill location supported by [Codex](https://developers.openai.com/codex/skills) and [Pi](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md). Start a new Codex session to discover it and invoke `$testflight`; in Pi, run `/reload` and invoke `/skill:testflight`. Both use the same CLI and instructions.
