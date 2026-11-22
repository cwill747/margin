# Xcode Cloud

Margin uses Xcode Cloud's hosted workflows for pull-request checks and TestFlight archives. Workflow definitions live in Apple's service, not in a YAML file in this repository. Complete the account setup below before expecting builds to run.

## Repository configuration

- Project: `Margin.xcodeproj`; shared scheme: `Margin`.
- App: `us.cwill.margin`; development team: `5XZ5XQ2F3F`; automatic signing is enabled.
- `ci_scripts/ci_post_clone.sh` runs `swift test` before each action that clones the source. A failure stops that action. These core tests are not included in the Xcode scheme.
- The scheme's Test action runs `MarginUITests`, including accessibility audits and palette contrast tests against deterministic sample data. No Outline credentials are needed.
- Xcode resolves MarkdownUI and its dependencies using the committed `Margin.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

No Fastlane, Homebrew, App Store Connect API keys, or custom upload scripts are required. Do not add credentials to this repository or to the validation workflow. Keep simulator code signing enabled: the app needs its application-identifier entitlement for Keychain writes.

## Activate the service

1. Push the branch containing `ci_scripts` to GitHub so Xcode Cloud can clone it. Merge it into `main` before enabling workflows that build `main`.
2. Open this worktree's `Margin.xcodeproj` in Xcode, select the **Margin** scheme, and sign in with an Apple Developer account for team `5XZ5XQ2F3F` that can configure Xcode Cloud.
3. Choose **Product > Xcode Cloud > Create Workflow**. Select the existing Margin App Store Connect app record for `us.cwill.margin` (or create it if missing).
4. Authorize Xcode Cloud to access `cwill747/margin` on GitHub. Approve the GitHub integration's repository access when prompted. This requires the appropriate GitHub permissions as well as Apple's account access.
5. Configure the validation workflow below and start a build from the setup branch. After the first build, workflows can also be managed in App Store Connect's Xcode Cloud tab.

The app requires iOS 27 or newer; use Xcode 27.1 or newer and a compatible macOS image. Prefer pinning an available Xcode 27.2 image to match local development. If Xcode Cloud does not yet offer the required SDK/runtime, wait for a compatible image rather than lowering deployment targets or skipping tests.

## Workflow: Margin Validation

| Setting | Value |
| --- | --- |
| Repository / project / scheme | `cwill747/margin` / `Margin.xcodeproj` / `Margin` |
| Start conditions | Pull request changes targeting `main`, plus branch changes on `main` |
| Environment | Compatible Xcode 27.1+ and macOS; cached builds allowed |
| Test action | iOS Simulator; Debug configuration; all tests in the Margin scheme |
| Test destinations | An available iPhone and iPad mini on iOS 27+; include iPhone Duo when available |
| Analyze action | iOS; Margin scheme |
| Archive / TestFlight | None |
| Notifications | Build failures to the team |

A Test action already builds for testing; a separate Build action is unnecessary. Include an iPad destination: the linked-document sidebar regression test intentionally skips on phones. The post-clone hook also runs the separate MarginCore tests for Analyze and other source-cloning actions; it does not run on source-less test runners.

Review the first build's logs to confirm the post-clone step executes and both test suites pass. Only then consider making the reported GitHub validation check required in branch protection. Inspect the actual check name rather than guessing it.

## Workflow: Margin TestFlight

Create this separately from PR validation so unreviewed pull requests cannot upload builds.

| Setting | Value |
| --- | --- |
| Repository / project / scheme | Same as validation |
| Start conditions | Tags starting with `v`, created on reviewed commits from `main` |
| General | Restrict editing for distribution |
| Environment | Compatible pinned Xcode/macOS; **Clean** builds |
| Test action | Same iPhone and iPad destinations and all scheme tests as validation |
| Archive action | iOS device archive; Release; **TestFlight and App Store** distribution |
| Post-action | TestFlight distribution to the intended tester group; successful builds only |

Only create release tags on reviewed commits that passed validation. Tag start conditions match names, not branch ancestry; the release process must enforce that the tagged commit is on `main`. A tag such as `v0.1.0-beta.1` does not change the app's numeric marketing version. Update `MARKETING_VERSION` when preparing a release, following `DEVELOPING.md`.

Before the first upload, inspect existing TestFlight builds and configure Xcode Cloud's next build number above the latest uploaded number for that version. Let Xcode Cloud manage its build numbers; do not rewrite `CURRENT_PROJECT_VERSION` in a hook. Coordinate any later uploads with `scripts/testflight` to avoid reusing numbers.

Use **TestFlight and App Store**, not **TestFlight (Internal Testing Only)**, for builds intended for the public beta signup in the README. Configure the appropriate external group in the post-action. External Beta App Review and any export-compliance prompts remain in App Store Connect; a successful archive does not guarantee immediate availability to external testers. Uploading a build does not publish an App Store release.

## Verify locally

From the repository root, run the same core-test hook used by the service:

```sh
ci_scripts/ci_post_clone.sh
```

To explicitly exercise the Cloud checkout-path handling:

```sh
CI_PRIMARY_REPOSITORY_PATH="$PWD" ci_scripts/ci_post_clone.sh
```

Also run a signed simulator build:

```sh
xcodebuild -project Margin.xcodeproj -scheme Margin \
  -destination 'generic/platform=iOS Simulator' build
```

For the full local accessibility matrix, use `scripts/check-accessibility <dedicated-simulator-UUID>` as documented in `DEVELOPING.md`. Hosted tests supplement, not replace, manual VoiceOver, largest-text, real-workspace, and physical-device release checks.

## Apple references

- [Configure the first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
- [Custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Workflow settings](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference)
- [Distribution workflows](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)
- [Next build number](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)
