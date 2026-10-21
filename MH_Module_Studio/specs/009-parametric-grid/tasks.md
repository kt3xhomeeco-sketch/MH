# Tasks

- [x] T01 Implement approved flat grid and accessible group toggles.
- [x] T02 Verify editor, shared scrolling, collapse and focus preserve drafts.
- [x] T03 Run scoped checks, visual QA and native reload without losing drafts.
- [x] T04 Update documentation, package and record actual validation.

Validated: standalone Electron editor checks pass, including group collapse during
dirty edits, focus opening the collapsed variable group, one horizontal scroll at
850px width, group actions staying reachable, original requests and scoped ATT
data. Visual screenshot reviewed against the approved flat gray mockup.
RuboCop: 30 files clean; Ruby: 102 tests / 597 assertions pass.

Native VBO PID 31852: child reopened with the new assets, existing draft captured
and restored (it was clean), 9/7 columns retained, gray adjacent bands and shared
scroll verified, toggles kept data, committed rule and model unchanged. Report:
outputs/native-grid-ui-009.json; original draft backup is retained in outputs.
No geometry/Undo claim is made for this presentation-only change. RBZ has 22
runtime entries; development artifacts remain excluded.
