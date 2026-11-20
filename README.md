<p align="center">
  <img src="Margin/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Margin logo" width="160" height="160">
</p>

# Margin

**Space for a second thought.**

Margin is an independent Outline companion for iPhone and iPad mini. Browse your workspace, keep a reference beside what you’re reading, save pages for offline use, and create or edit documents.

Requires iOS 27 or newer. Margin is not an official Outline client.

## Get started

Open Margin and choose **Explore a sample workspace** to try it without credentials, or connect your own Outline workspace.

Enter your workspace’s HTTPS address and choose **Sign in to Outline**. Complete your workspace’s sign-in, including Cloudflare if present, then tap **Connect**. No API key or OAuth registration is needed. Credentials are stored in Keychain; expired or revoked sessions require signing in again.

Passkeys and security keys have limited support in the sign-in window. Use an authenticator code where your identity provider offers one.

## Read and write

- Search and browse collections and documents.
- Choose **Keep beside** to keep a reference close. Wider screens show both pages side by side; narrower screens let you switch between them.
- Open documents for reading, then edit them or create a new draft with Markdown formatting controls. Unsent drafts are saved locally for recovery.
- Open Settings from the profile button. Under **Appearance**, choose System, Paper, Sepia, or Night and adjust reading text from 14 to 30 pt. Your preferences apply to both document panes.

## Read offline

Settings offers three offline modes:

- **Manual:** save individual pages with Sync.
- **Pages I open:** save pages as you read them.
- **Everything:** sync all accessible pages.

Saved pages update during workspace refresh while Margin is open. **Sync now** retries updates, and failed updates keep the previous saved copy. Saved pages and the collection browser remain available after restarting the app.

Images and attachments are not downloaded for offline use. Disconnecting clears saved documents, collections, and profile information from the device.

## Other connection options

Workspace connection settings also support API keys, system-browser OAuth, and custom gateway headers.

For an API key, create a personal key in Outline’s **Settings → API & Apps**. Reading requires collection and document read access; creating and editing documents also requires document write access.

For system-browser OAuth, register an OAuth application in your Outline instance with client type **public**, PKCE support, and redirect URI `us.cwill.margin://oauth/callback`. Enter its client ID in Margin. Older Outline versions without public-client support require an upgrade or the API-key option.

Custom headers are stored in Keychain and restricted to your workspace’s HTTPS origin.

## Limitations

Margin supports GitHub-flavored Markdown. Some Outline-specific rich blocks and protected attachments may not display fully. Editing uses Markdown with formatting controls; a visual editor and comments are not yet available.

## Development

See [DEVELOPING.md](DEVELOPING.md) for building, testing, and contributing to Margin.
