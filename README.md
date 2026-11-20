# Margin

An independent native Outline companion for iPhone and iPad mini, built with SwiftUI. The workspace has a searchable collection browser, paired document reading, local saved copies, native draft creation, and native document editing. Web views are reserved for sign-in.

Brand direction and visual specifications: [Branding guide](BRANDING.md).

Settings → Appearance offers System, Paper, Sepia, and Night app-wide color themes and a 14–30 pt reading size with a live preview. Theme preferences persist across all app screens; reading size applies to both document panes.

## Run locally

Open `Margin.xcodeproj` in Xcode 27.1 or newer, with the iOS 27.1 or newer SDK for full-screen Duo support. Select the iPhone Duo or iPad mini simulator and run the Margin scheme. The deployment target is iOS 27. Use **Explore a sample workspace** to try the interface without credentials.

```sh
swift test
xcodebuild -project Margin.xcodeproj -scheme Margin \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Margin.xcodeproj -scheme Margin \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

Apple SDKs and signing use the installed Xcode toolchain. Xcode resolves the pinned MarkdownUI package for native Markdown rendering. The project uses the same development team as TP-7 VoiceSync (`5XZ5XQ2F3F`) and bundle ID `us.cwill.duoutline`. An Apple development certificate, working Xcode account, and provisioning profile are required for a device build.

## Connect

Enter your Outline workspace’s HTTPS origin and choose **Sign in to Outline**. Complete Cloudflare (if present) and Outline’s own SSO in the same window, then tap **Connect**. Margin captures only the exact workspace’s secure Outline session and gateway cookies, verifies access through the native API, and stores credentials in Keychain. No API key or OAuth client registration is needed for this flow. Expired or revoked sessions require signing in again. Passkeys/security keys remain limited in the embedded browser; use an authenticator code where your identity provider offers one.

API keys and advanced OAuth remain available.

For advanced system-browser OAuth SSO under Workspace connection settings, register an OAuth application in your Outline instance with client type **public**, PKCE support, and redirect URI `us.cwill.duoutline://oauth/callback`. Enter its client ID in Margin. Sign-in opens Apple’s system authentication browser, where you use the workspace’s existing identity provider. The app validates callback state, exchanges the code with an S256 PKCE verifier, and refreshes expiring tokens. No OAuth client secret is embedded in the app. Older Outline releases that do not support public clients need an upgrade or the API-key connection option.

For API keys, create a personal key in Outline’s **Settings → API & Apps**. Reading requires collection/document read access; draft creation also requires document write access.

Advanced connection settings support custom headers and refreshing the workspace sign-in session. Headers are kept in Keychain and restricted to the exact workspace HTTPS origin. The default sign-in flow does not require users to know about their gateway.

## Reading and offline use

Documents open read-only. Editing, new-document creation, and Settings use the main document pane rather than modal sheets. Collection sections start collapsed after a fresh login and preserve expansion state across app launches. Duo uses native adaptive toolbars; the profile button opens Settings.

Settings offers three offline modes: Manual (per-page Sync), Pages I open (save on opening), and Everything (sync all accessible pages). Existing saved pages update during workspace refresh while the app is open. Sync now retries updates; failures retain previous cached copies. The hierarchy and profile are cached so saved content remains reachable after restart. Caches use file protection and are excluded from backups. Disconnect clears the document, hierarchy, and profile caches. Images and attachments are not downloaded for offline use.

## Current limitations

- Native reading supports GitHub-flavored Markdown. Outline-specific rich blocks and protected attachments do not yet have full native fidelity.
- The current native editing surface is Markdown with formatting controls. The requested Outline-style visual editor and comments remain unfinished. Unsent drafts are saved locally for recovery.
- Advanced system-browser OAuth requires a registered public client. The primary web-session sign-in does not. Session sign-in and native reading have been verified against a real workspace.
- Paired reading uses side-by-side panes when the detail area is at least 760 points wide, and a document/reference switcher below that width.
- Real-workspace and physical device validation remain required before release.

## Validation

Core tests cover API pagination and redirects, gateway header isolation, session cookies, OAuth PKCE, revision-checked patches, title presentation, and offline hierarchy serialization. Run `swift test` and a local Xcode build before pushing.

The app has run against a real workspace on the iOS 27.2 Duo simulator. Earlier signed device builds passed automatic provisioning and `codesign --verify --deep --strict`; physical-device installation remains unverified.

Simulator builds must keep code signing enabled. Disabling signing removes the application-identifier entitlement and makes Keychain writes fail with OSStatus -34018. Debug builds support `--verify-keychain` to test a temporary write/read/delete without touching saved credentials.

API reference: https://www.getoutline.com/developers
