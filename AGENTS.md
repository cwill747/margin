# Repository Instructions

## Accessibility is part of every UI change

- Consider accessibility during design and implementation, not only before release. Preserve native control semantics; give custom controls meaningful labels, values, states, and actions. Hide decorative images and inactive panes without hiding useful content.
- Support Dynamic Type through the largest accessibility sizes, Bold Text, and compact layouts without clipped text or unreachable actions. Keep custom touch targets at least 44 × 44 points.
- Check VoiceOver reading order, heading/link navigation, and focus when opening or closing documents, switching reading panes, presenting sheets, and entering or leaving the editor. Expose disclosure state and announce important asynchronous results or errors without excessive announcements.
- Make all actions reachable with VoiceOver, Voice Control, Switch Control, and Full Keyboard Access. Provide accessible alternatives to gesture-only interactions and context-menu actions.
- Check text, links, icons, and controls in System (light and dark), Paper, Sepia, and Night. Do not communicate state through color alone. Respect Increase Contrast, Reduce Motion, and Reduce Transparency where applicable.
- For UI test coverage, use XCTest's `XCUIApplication.performAccessibilityAudit()` on each relevant screen and state with deterministic sample data. Do not blanket-ignore audit failures; document any narrowly scoped false positive. Automated audits supplement manual assistive-technology testing.
- Before pushing UI changes, run a local Xcode build and applicable UI audits. Manually verify the changed flow with VoiceOver and the largest Dynamic Type size. State exactly what was tested and what remains unverified; never imply a build or source inspection proves accessibility.
- Release checks cover onboarding/sign-in, browsing/search, reading/reference panes, composing/editing, Settings, and loading/empty/error/offline states. Include Markdown headings, links, images, code, and tables. See Apple's [accessibility audit guidance](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app).

## Commits and Versioning

- Always use Conventional Commits: `<type>[optional scope][!]: <description>` (for example, `feat(editor): add outline folding` or `fix(sync): preserve item order`).
- Use `feat` for new features, `fix` for bug fixes, and appropriate types such as `docs`, `refactor`, `test`, `build`, `ci`, or `chore` for other changes.
- Mark breaking changes with `!` after the type/scope or a `BREAKING CHANGE:` footer explaining the incompatibility and migration.
- Always use Semantic Versioning (`MAJOR.MINOR.PATCH`) for release versions: increment MAJOR for breaking changes, MINOR for backward-compatible features, and PATCH for backward-compatible bug fixes. Choose the bump from all changes since the previous release, using the highest required level.
- Keep prerelease identifiers (for example, `1.2.0-beta.1`) and platform build numbers distinct from the release version. Do not bump release versions for every commit; update them when preparing a release or when explicitly requested.
