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

Run `swift test` and a local Xcode build before pushing. For UI changes, also run `scripts/check-accessibility <dedicated-simulator-UDID>` and complete the changed flow in the [accessibility checklist](ACCESSIBILITY.md). The shared Margin scheme includes the UI audit target.

Core tests cover API pagination and redirects, gateway header isolation, session cookies, OAuth PKCE, revision-checked patches, title presentation, and offline hierarchy serialization.

The app has run against a real workspace on the iOS 27.2 Duo simulator. Earlier signed device builds passed automatic provisioning and `codesign --verify --deep --strict`; physical-device installation remains unverified. Real-workspace and physical-device validation remain required before release.

Simulator builds must keep code signing enabled. Disabling signing removes the application-identifier entitlement and makes Keychain writes fail with OSStatus -34018. Debug builds support `--verify-keychain` to test a temporary write/read/delete without touching saved credentials.

Before release, inspect the icon at home-screen size and check headings, links, code, tables, quotes, and paired reading in every palette with Dynamic Type and VoiceOver.

## Implementation notes

- The Xcode project, scheme, target, source folder, and app entry point use Margin. The Swift package is MarginCore.
- The bundle ID is `us.cwill.margin` and the OAuth callback is `us.cwill.margin://oauth/callback`. Keychain service identifiers and storage paths retain their existing values. Existing Outline OAuth registrations must use the new callback URI.
- OAuth validates callback state, exchanges codes with an S256 PKCE verifier, and refreshes expiring tokens. No OAuth client secret is embedded in the app.
- Offline caches use file protection and are excluded from backups.
- Paired reading uses side-by-side panes in regular horizontal size classes, and a document/reference switcher in compact size classes or at accessibility text sizes. Both readers stay mounted across layout changes to preserve reading and editing state.

## iPhone Duo design checks

Follow Apple's [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/), [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/), and [Layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout).

Use size classes for navigation and pane layout, not screen dimensions, device names, or orientation. Geometry may divide the available content area between panes; the reading column's maximum width is a readability constraint, not a device breakpoint. Keep foreground content inside the system safe area, including asymmetric leading and trailing insets. Native navigation, toolbars, sheets, menus, and alerts supply adaptive placement and fold avoidance.

Before release, use Device Hub to check the following with the sample workspace and a real workspace. A successful build alone does not verify these interactions:

- Outer display in both orientations; inner display open, rotated, and partially folded. Verify sidebar navigation, reading, paired reading, search, Settings, and sign-in sheets.
- Split View on both left and right, plus reduced height with pinned picture-in-picture. Check that controls remain reachable and content clears the camera and system bars.
- Fold and unfold while scrolled in each reading pane and while editing an unsaved document. Preserve selection, scroll position, text, and cursor; retain the same actions in compact and regular layouts.
- Accessibility text sizes, VoiceOver, and keyboard presentation. Check the document/reference switcher, sidebar disclosure controls, editor fields, and formatting strip for clipping or unreachable actions.
- Inspect custom reference and editor controls near the fold. Unlike native toolbars, custom rows need explicit pose testing; adopt reserved-region handling if controls intersect the curved region.

See the [branding guide](BRANDING.md) for visual specifications and icon generation, and the [Outline API reference](https://www.getoutline.com/developers) for API documentation.

## Commits and release versions

Always use Conventional Commits (`<type>[optional scope][!]: <description>`). Use `feat` for features and `fix` for bug fixes; mark breaking changes with `!` or a `BREAKING CHANGE:` footer describing the incompatibility and migration.

Release versions follow Semantic Versioning (`MAJOR.MINOR.PATCH`): bump MAJOR for breaking changes, MINOR for backward-compatible features, and PATCH for backward-compatible bug fixes. Review all changes since the previous release and use the highest required bump. Documentation and maintenance commits do not automatically require a release.

When preparing a release, update `MARKETING_VERSION` in `Margin.xcodeproj/project.pbxproj` consistently across build configurations. Do not bump it for every commit. Keep the numeric platform build number (`CURRENT_PROJECT_VERSION`) separate: TestFlight builds of the same release version use increasing build numbers. SemVer prerelease labels such as `1.2.0-beta.1` belong in release labels; keep the Xcode marketing version numeric (`1.2.0`).

## Xcode Cloud

See [the Xcode Cloud setup guide](docs/xcode-cloud.md) for hosted pull-request validation and TestFlight workflows. The executable `ci_scripts/ci_post_clone.sh` hook runs MarginCore tests before source-cloning Cloud actions; the shared Margin scheme supplies UI and accessibility tests. Initial Apple account setup and GitHub repository authorization must be completed in Xcode before hosted builds can run.

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
