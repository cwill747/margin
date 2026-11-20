# Interactive Margin demo

Buildless HTML, CSS, and JavaScript. The landing page embeds `demo/` in an iframe;
GitHub Pages already publishes the entire `site/` directory.

The device uses the Duo simulator display dimensions at 3×: 951 × 669 points
unfolded and 466 × 678 folded. The entire device scales to fit its container,
while folding changes the app layout. The black bezel, asymmetric folded corners,
camera cutout, and right-side controls follow the Device Hub simulator.

Sample documents, edits, drafts, saved-page selections, and appearance choices
live under `margin-web-demo-v2` in localStorage. Reset demo restores the samples.
No Outline credentials or network API calls are used. Saved reading is a local
collection; this demo does not install a service worker or cache the site offline.
The Markdown preview supports headings, paragraphs, lists, quotes, bold, italics,
inline code, and HTTP(S) links. Editable text is escaped before rendering.

## Local preview

Serve `site/` with a static server. The Pages workflow copies the app icon to
`site/icon.png` during deployment; that icon is absent in a bare local preview.

## Checks

- `node --check site/demo/demo.js`
- Browse and search; save a page and check the Saved filter.
- Keep a reference, open another document, fold and unfold without losing place.
- Edit or create a document, reload, and verify saved text or draft recovery.
- Change theme and text size, then reset the demo.
- Check the embedded page and standalone demo at narrow and wide widths.

Native interaction references: `Margin/ReaderView.swift`, `Margin/MarginApp.swift`,
`Margin/Appearance.swift`, and `docs/screenshots/`. This is a separate web
implementation; update it when native controls or layouts change.
