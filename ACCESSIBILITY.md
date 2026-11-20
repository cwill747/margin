# Accessibility verification

Accessibility is a requirement for each UI change; see [AGENTS.md](AGENTS.md).

## Local gate

Use a booted, dedicated simulator with the app's supported iOS runtime. Do not run the UI suite on a simulator containing a real workspace: the debug fixtures change preferences and save sample drafts. Credentials are not loaded in UI-test mode. Keep simulator signing enabled for Keychain support.

```sh
xcrun simctl list devices available
scripts/check-accessibility <dedicated-simulator-UDID>
```

The command runs core tests, builds locally, and runs the shared Margin scheme's UI tests. It also repeats the reader palette audits in system dark mode with Increase Contrast, then restores those simulator settings. Its dated `build/accessibility-*.xcresult` contains audit failures and screenshots. Open the result in Xcode. Do this before pushing; use the same command on a Mac runner with the required Xcode/runtime when adding CI.

The debug-only `--ui-testing` launch argument and `MARGIN_TEST_SCREEN` environment select deterministic sample screens without network authentication. Fixtures cover onboarding, library, search results, empty results, reader, reference, editor, compose, Settings, and reader loading/error/offline states. Tests audit visible content before and after scrolling, all reading palettes, and the largest accessibility text size. One exception is contrast on elements that XCTest confirms are disabled, matching the [WCAG inactive-control exception](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum#inactive-user-interface-components). Enabled controls remain checked. On iOS 27.2, four identified Settings labels (`appearance-help`, `offline-heading`, `offline-count`, `offline-help`) produce false Dynamic Type findings. Only that audit type on those identifiers is filtered: `testTextScaling` independently verifies that their actual rendered height grows by more than 40% at the largest accessibility size. Clipping and contrast on those labels remain audited. A passing screen audit does not certify an entire workflow or content supplied by an Outline workspace.

The app's actual palette source is also compiled into `PaletteContrastTests`, which numerically checks text/link colors on both surfaces in light/dark and normal/increased contrast. The largest-editor test verifies that the keyboard appears and leaves an editable area, and records a screenshot. It does not audit Apple's keyboard internals: iOS 27.2 exposes three unnamed empty prediction buttons and reports contrast on text hidden behind the keyboard. Editing is audited before keyboard presentation; the keyboard workflow has separate interaction/layout checks. The editor-to-preview transition asserts that the editor leaves the accessibility tree; preview is then audited in a fresh process because iOS 27.2’s auditor retains the removed text view’s old text frames.

## Manual release gate

Record device, OS, palette, text size, tested flow, result, and unresolved issue. Do not mark these checks passed based on XCTest, screenshots, or a successful build.

| Setting / input | Checks |
| --- | --- |
| VoiceOver | Complete onboarding, browse/search, open a document, use the headings and links rotor, pin/switch/close a reference, edit/preview/save/cancel, create a draft, change Settings. Check reading order, focus restoration, errors and save announcements. Hidden panes must not be reachable. |
| Voice Control | Activate controls by visible name and by number. Check repeated document titles, disclosures, formatting controls, and pane controls. |
| Switch Control | Reach and activate every action, scroll the formatting strip and Markdown tables/code, enter/exit sheets, and recover from errors without touch gestures. |
| Full Keyboard Access | Traverse and activate navigation, search, editor, formatting, picker, sheet, and dialog controls. Verify visible focus and no traps. Check Command-N and native text editing/undo. |
| Dynamic Type / Bold Text | Largest accessibility size, smallest supported phone width, iPad split view, landscape, keyboard shown. No clipped controls or lost actions. Long titles and Markdown must remain readable. |
| Increase Contrast | System light/dark, Paper, Sepia, Night; include secondary text, links, selected rows, error messages, quotes, tables, code, and checkboxes. |
| Reduce Motion / Reduce Transparency | Expand/collapse and navigate with both settings enabled. Custom expansion must not animate with Reduce Motion. System materials should follow Reduce Transparency; custom surfaces are opaque. |
| Content and state | Long Markdown headings, meaningful image alt text, missing images, links, code, tables, quotes, checked/unchecked tasks; loading, empty, errors, offline, and queued saves. Test real sign-in pages separately; those are owned by the workspace/identity provider. |

Use Accessibility Inspector to inspect hierarchy and contrast on each screen. Aim for 4.5:1 for normal text, 3:1 for large text and meaningful control boundaries/icons, and at least 44 × 44 pt for custom touch targets. Links are underlined and selected rows expose selection traits, so color is not the only cue.

## Evidence and limits

Automated results belong in `.xcresult` artifacts. Manual VoiceOver, Voice Control, Switch Control, Full Keyboard Access, and physical-device checks require an interactive device session; leave them explicitly unverified until performed. Recheck image descriptions and table navigation with real workspace content, since source content and third-party Markdown rendering affect the accessibility tree.

### Local validation — 2026-11-20

Xcode 27.2 / iOS 27.2, dedicated iPhone 17 Pro and iPad mini simulators; sample workspace only. The local build and all 24 core tests passed. Palette contrast calculations passed for every palette, both appearances, and both contrast settings. Individual phone audits covered the main screens, largest text, reader states, and keyboard create/edit/save. On iPad, the full run passed 12 of 16 test cases; subsequent fixes passed the largest-text library audit and the complete library/search/empty-results test. Reference/editor/preview, keyboard editing, reader palettes/states, and measured text scaling passed on iPad. Screenshots were inspected for paired reading and large-text editing with the keyboard.

The UI gate is **not fully green**. Largest-text compose still produces two unidentified contrast findings; scrolled Settings produces another. The auditor supplied no target element for these findings, so they remain failures rather than being suppressed or classified as false positives. Normal-size compose also produced an unidentified potentially-inaccessible-text finding in the full run. A follow-up run encountered screenshot/audit timeouts; restarting the dedicated simulator resolved the library retry. Manual assistive-technology checks remain unverified because simulator UI control was unavailable.

All four reader palettes also passed the iPad audit in system dark mode with Increase Contrast enabled. The simulator's appearance settings were restored afterward.

Local artifacts (ignored by Git): `build/accessibility-20261120-164204-light.xcresult`, `build/accessibility-ipad-fixes.xcresult`, `build/accessibility-ipad-library.xcresult`, and `build/accessibility-ipad-dark-contrast.xcresult`. Preserve these when investigating the outstanding findings.

[Apple: Performing accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
