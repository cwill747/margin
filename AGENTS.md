# Repository Instructions

## Commits and Versioning

- Always use Conventional Commits: `<type>[optional scope][!]: <description>` (for example, `feat(editor): add outline folding` or `fix(sync): preserve item order`).
- Use `feat` for new features, `fix` for bug fixes, and appropriate types such as `docs`, `refactor`, `test`, `build`, `ci`, or `chore` for other changes.
- Mark breaking changes with `!` after the type/scope or a `BREAKING CHANGE:` footer explaining the incompatibility and migration.
- Always use Semantic Versioning (`MAJOR.MINOR.PATCH`) for release versions: increment MAJOR for breaking changes, MINOR for backward-compatible features, and PATCH for backward-compatible bug fixes. Choose the bump from all changes since the previous release, using the highest required level.
- Keep prerelease identifiers (for example, `1.2.0-beta.1`) and platform build numbers distinct from the release version. Do not bump release versions for every commit; update them when preparing a release or when explicitly requested.
