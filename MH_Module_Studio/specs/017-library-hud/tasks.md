# Tasks

- [x] Portable catalog/settings/payload/layout + regression checks
- [x] Native folder/export/import adapter and app-owned metadata round trip
- [x] Library tab UI, grid/list, sizes, search, preview, cancellation
- [x] Native HUD/placement tool, settings, assignable menu command, key lifecycle
- [x] ATT coordinate/local-origin fix, conditional expressions, regression cases
- [x] Native geometry/export/import/copy/Undo/Redo and Chromium UI checks
- [x] RuboCop/test gate, packaging and user instructions
- [ ] Manual physical shortcut test in the intended foreground SketchUp session

The native key callback tests passed. Bounded physical-key QA refused to type
when another SketchUp process held focus; do not report that as a passed physical
keyboard test. This limitation is documented in README and the verification log.
