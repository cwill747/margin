---
name: testflight
description: Build signed Margin release archives and upload them to App Store Connect for TestFlight using this repository's CLI. Use for preparing or uploading Margin beta builds.
---

Work from the repository root containing `scripts/testflight`. Read the TestFlight section in `DEVELOPING.md` and run `scripts/testflight --help` for authentication and command usage.

- Inspect the working tree so the user knows which source is being shipped; do not discard changes or commit as part of uploading.
- Run `swift test` before preparing a release. Select an unused build number above the last uploaded build for the current version. If App Store Connect history is unavailable, ask for the number; do not guess that a local counter is unused.
- Run `scripts/testflight archive BUILD_NUMBER`. This performs the local signed Release build. Report the archive path and version/build identity. The project version is not edited.
- For an authorized upload, run `scripts/testflight upload ARCHIVE_PATH` on that exact archive. A request to upload a build already authorizes this step; a request only to prepare a build or add tooling does not.
- Use an existing Xcode account or the three documented ASC environment variables. Never print or read the contents of private keys into chat, or add them to git. If credentials/signing are missing, report the concrete failure and needed setup.
- If upload fails or times out, inspect its log and App Store Connect before retrying: the server may already have accepted the build. Do not automatically rebuild, bump, or repeatedly upload.
- Report upload acceptance separately from processing/tester availability. This CLI does not configure tester groups, resolve export compliance, submit Beta App Review, or publish an App Store release.
