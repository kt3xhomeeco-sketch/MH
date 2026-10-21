# Verification

- `bundle exec ruby tools/check.rb`:157 files, RuboCop clean;314 tests,
  3887 assertions, no failures/errors/skips.
- Browser assembly workflow passes: separate names before relationship buttons,
  three grouped member names, explicit coplanar labels and correct load dispatch;
  automatic selection action and existing gap/fit/repeat/rename fields retained.
- `outputs/native-059.json`:17 checks pass in real SketchUp2025 PID17292.
  Two adjacent boxes produce one3mm contact plus four coplanar planes; no movement
  at creation, no duplicates, editable front offset with B fitting while A stays
  fixed, exact restoration, reflected rotation, third member and grouped selection.
  Native tree lists all three members before types and its visible button dispatches
  the real auto-links action. Actual saved/reread SKP retains all8 coplanar records.
- `outputs/undo-059.json`: one Undo removes the mixed five-link batch; Redo
  restores IDs and verified planes without modifying original geometry.
- `outputs/ui-059-17292.json`: live HtmlDialog button visible at47px; actual
  existing linked module names render as two separate rows, then their type.
  Native overlay draws without error. Normal request callbacks restored.
- Both running SketchUp sessions received the new Ruby definitions; existing
  active HUD was refreshed in the selected-model session. The empty other
  session received code only. Source user geometry and selections retained.
- Package `outputs/MH_Module_Studio-0.1.0.rbz` rebuilt and archive checked.

Coplanar inference uses rectangular captured faces,0.02mm plane tolerance and
actual polygon proximity within the existing search range. Existing links are
retained; selecting the modules/group and pressing inference adds missing links.
